# Helpers + capabilities + config + runner for storyteller

# Basic dir and IO helpers
function Ensure-Dir($path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }  # guard null/empty
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
}
function Assert-FileExists($path, $desc) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        Write-Host "ERROR: $desc not found at: $path" -ForegroundColor Red
        exit 1
    }
}

# UI helpers
function Select-FromList($title, $items, $includeNone=$true, $defaultIndex=0) {
    Write-Host ""
    Write-Host "== $title ==" -ForegroundColor Cyan

    # FIX: ensure we have an array even if a single item (string) was passed
    $list = @($items)

    $offset = 0
    if ($includeNone) { Write-Host "  0) None"; $offset = 1 }
    for ($i=0; $i -lt $list.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + $offset), $list[$i])
    }
    while ($true) {
        $choice = Read-Host "Select a number [default: $defaultIndex]"
        if ([string]::IsNullOrWhiteSpace($choice)) { return $defaultIndex }
        if ($choice -as [int] -ne $null) {
            $idx = [int]$choice
            if ($idx -eq 0 -and $includeNone) { return 0 }
            $realIdx = $idx - $offset
            if ($realIdx -ge 0 -and $realIdx -lt $list.Count) { return $idx }
        }
        Write-Host "Invalid selection. Try again." -ForegroundColor Yellow
    }
}
function Read-Number($prompt, $default, $min=$null, $max=$null) {
    while ($true) {
        $val = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($val)) { return [double]$default }
        if ($val -as [double] -ne $null) {
            $num = [double]$val
            if (($min -ne $null -and $num -lt $min) -or ($max -ne $null -and $num -gt $max)) {
                Write-Host "Value must be in range [$min, $max]" -ForegroundColor Yellow
            } else { return $num }
        } else { Write-Host "Please enter a number" -ForegroundColor Yellow }
    }
}
function Read-Int($prompt, $default, $min=$null, $max=$null) {
    while ($true) {
        $val = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($val)) { return [int]$default }
        if ($val -as [int] -ne $null) {
            $num = [int]$val
            if (($min -ne $null -and $num -lt $min) -or ($max -ne $null -and $num -gt $max)) {
                Write-Host "Value must be in range [$min, $max]" -ForegroundColor Yellow
            } else { return $num }
        } else { Write-Host "Please enter an integer" -ForegroundColor Yellow }
    }
}
function Read-YesNo($prompt, $defaultNo=$true) {
    $suffix = $(if ($defaultNo) { "y/N" } else { "Y/n" })
    while ($true) {
        $val = Read-Host "$prompt [$suffix]"
        if ([string]::IsNullOrWhiteSpace($val)) { return -not $defaultNo }
        switch ($val.ToLower()) {
            "y" { return $true }; "yes" { return $true }; "n" { return $false }; "no" { return $false }
            default { Write-Host "Please answer y or n" -ForegroundColor Yellow }
        }
    }
}
function Read-String($prompt, $default) {
    $val = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $default }
    return $val
}

# Helper: select integer from common presets (with a Custom option and extra info)
function Select-IntFromPresets {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][int]$Current,
        [Parameter(Mandatory=$true)][int[]]$Presets,
        [string]$ExtraInfo = $null,
        [string]$Unit = "tokens"
    )

    function Format-PresetLabel {
        param([int]$n)
        if ($n -ge 1024 -and ($n % 1024 -eq 0)) {
            return ("{0}k (= {1})" -f ($n/1024), $n)
        }
        return [string]$n
    }

    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor Cyan
    if ($ExtraInfo) {
        Write-Host ($ExtraInfo) -ForegroundColor DarkCyan
    }
    Write-Host ("Current: {0} {1}" -f $Current, $Unit)

    for ($i = 0; $i -lt $Presets.Count; $i++) {
        $label = Format-PresetLabel -n $Presets[$i]
        Write-Host ("  {0}) {1}" -f ($i + 1), $label)
    }
    Write-Host "  C) Custom..."
    Write-Host "  Enter = keep current"

    while ($true) {
        $choice = Read-Host "Select 1-$($Presets.Count), C for custom, or Enter"
        if ([string]::IsNullOrWhiteSpace($choice)) { return $Current }
        if ($choice -match '^[cC]$') {
            $val = Read-Int "$Title (custom integer)" $Current 1
            return $val
        }
        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx)) {
            if ($idx -ge 1 -and $idx -le $Presets.Count) {
                return $Presets[$idx - 1]
            }
        }
        Write-Host "Invalid selection. Try again." -ForegroundColor Yellow
    }
}

# Misc helpers
function BaseName { param([string]$path) if (-not $path) { return "None" } [IO.Path]::GetFileName($path) }
function Sanitize-Filename($name) {
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $name.ToCharArray()) { [void]$sb.Append($(if ($invalid -contains $ch) { "_" } else { $ch })) }
    $sb.ToString()
}
function Read-TextFile($path) { if ($path -and (Test-Path $path)) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 } }
function Convert-FloatInvariant { param([double]$Value) $Value.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }

# File selectors
function Select-PromptFile {
    param([Parameter(Mandatory=$true)][string]$dir, [Parameter(Mandatory=$true)][string]$label)
    Ensure-Dir $dir
    # FIX: force array
    $files = @(Get-ChildItem -LiteralPath $dir -File -Filter "*.txt" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    if (-not $files -or $files.Count -eq 0) { Write-Host "No .txt files found in: $dir" -ForegroundColor Yellow; return $null }
    $choice = Select-FromList "Select $label (.txt) from $dir" $files $true 0
    if ($choice -gt 0) { return $files[$choice - 1] }
    return $null
}
function Select-Model {
    param([string]$ModelFolder = $ModelsDir)
    # FIX: force array
    $models = @(Get-ChildItem -LiteralPath $ModelFolder -File -Filter "*.gguf" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    if (-not $models -or $models.Count -eq 0) { Write-Host "No .gguf models found in: $ModelFolder" -ForegroundColor Yellow; return $null }
    $mdChoice = Select-FromList "Select model (.gguf) from $ModelFolder" $models $false 0
    return $models[$mdChoice]
}
function Select-Template {
    Ensure-Dir $TemplatesDir
    # FIX: force array
    $files = @(Get-ChildItem -LiteralPath $TemplatesDir -File -Filter "*.txt" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    if (-not $files -or $files.Count -eq 0) { Write-Host "No template .txt files found in: $TemplatesDir" -ForegroundColor Yellow; return $null }
    $choice = Select-FromList "Select chat template (.txt) from $TemplatesDir" $files $true 0
    if ($choice -gt 0) { return $files[$choice - 1] }
    return $null
}
function Select-LlamaExe {
    param([string]$StartDir = $null)
    if ([string]::IsNullOrWhiteSpace($StartDir)) { $StartDir = $env:ProgramFiles }
    
    Write-Host ""
    Write-Host "== Select llama-cli.exe ===" -ForegroundColor Cyan
    Write-Host "Enter the full path to llama-cli.exe (or press Enter to browse):" -ForegroundColor DarkCyan
    $input = Read-Host "Path"
    
    if (-not [string]::IsNullOrWhiteSpace($input)) {
        if (Test-Path -LiteralPath $input -PathType Leaf) {
            if ($input -like '*.exe') {
                return $input
            } else {
                Write-Host "Selected file is not an .exe" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Path not found: $input" -ForegroundColor Yellow
        }
    }
    
    # Fallback: try PATH search
    Write-Host "Searching PATH for llama-cli.exe..." -ForegroundColor DarkCyan
    $found = Get-Command "llama-cli.exe" -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "Found: $($found.Source)" -ForegroundColor Green
        $confirm = Read-Host "Use this? (y/n) [default: y]"
        if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -match '^y') {
            return $found.Source
        }
    }
    
    Write-Host "Could not find llama-cli.exe. Please install llama.cpp or ensure it is in PATH." -ForegroundColor Yellow
    return $null
}

# llama-cli capabilities + templates
function Get-LlamaCliCapabilities($exePath) {
    try {
        $help = & $exePath "-h" 2>&1 | Out-String
        $noCnvName = $null
        if ($help -match "(^|\s)--no-conversation(\s|$)") { $noCnvName = "--no-conversation" }
        elseif ($help -match "(^|\s)--no-conv(\s|$)")    { $noCnvName = "--no-conv" }
        elseif ($help -match "(^|\s)--no-cnv(\s|$)")     { $noCnvName = "--no-cnv" }
        elseif ($help -match "(^|\s)-no-cnv(\s|$)")      { $noCnvName = "-no-cnv" }

        $tmplNameFlag = $null; $tmplFileFlag = $null
        if ($help -match "(^|\s)--chat-template(\s|$)") { $tmplNameFlag = "--chat-template" }
        elseif ($help -match "(^|\s)--template(\s|$)")  { $tmplNameFlag = "--template" }
        if ($help -match "(^|\s)--chat-template-file(\s|$)") { $tmplFileFlag = "--chat-template-file" }
        elseif ($help -match "(^|\s)--template-file(\s|$)")  { $tmplFileFlag = "--template-file" }

        $listFlag = $null
        if ($help -match "(^|\s)--list-chat-templates(\s|$)") { $listFlag = "--list-chat-templates" }

        # NEW: --no-display-prompt detection
        $hasNoDisplayPrompt = ($help -match "(^|\s)--no-display-prompt(\s|$)")

        $hasSmoothingFactor = ($help -match "(^|\s)--smoothing-factor(\s|$)")
        # NEW: detect mirostat flags
        $hasMirostat     = ($help -match "(^|\s)--mirostat(\s|$)")
        $hasMirostatLR   = ($help -match "(^|\s)--mirostat-lr(\s|$)")
        $hasMirostatEnt  = ($help -match "(^|\s)--mirostat-ent(\s|$)")

        return @{
            hasSystem            = ($help -match "(^|\s)--system(\s|$)")
            hasSystemPromptFile  = ($help -match "(^|\s)--system-prompt-file(\s|$)")
            hasFile              = ($help -match "(^|\s)--file(\s|$)")
            hasSingleTurn        = ($help -match "(^|\s)--single-turn(\s|$)")
            hasNoCnv             = ($noCnvName -ne $null)
            noCnvName            = $noCnvName
            hasSimpleIO          = ($help -match "(^|\s)--simple-io(\s|$)")
            hasTemplateNameFlag  = ($tmplNameFlag -ne $null)
            templateNameFlag     = $tmplNameFlag
            hasTemplateFileFlag  = ($tmplFileFlag -ne $null)
            templateFileFlag     = $tmplFileFlag
            hasListTemplates     = ($listFlag -ne $null)
            listTemplatesFlag    = $listFlag
            hasNoDisplayPrompt   = $hasNoDisplayPrompt
            hasSmoothingFactor   = $hasSmoothingFactor
            # NEW: mirostat flags
            hasMirostat          = $hasMirostat
            hasMirostatLR        = $hasMirostatLR
            hasMirostatEnt       = $hasMirostatEnt
        }
    } catch {
        return @{
            hasSystem=$false; hasSystemPromptFile=$false; hasFile=$false
            hasSingleTurn=$false; hasNoCnv=$false; noCnvName=$null
            hasSimpleIO=$false; hasTemplateNameFlag=$false; templateNameFlag=$null
            hasTemplateFileFlag=$false; templateFileFlag=$null; hasListTemplates=$false; listTemplatesFlag=$null
            hasNoDisplayPrompt=$false; hasSmoothingFactor=$false
            # NEW: mirostat defaults
            hasMirostat=$false; hasMirostatLR=$false; hasMirostatEnt=$false
        }
    }
}
function Get-ChatTemplates { param([string]$Exe,[hashtable]$Capabilities)
    if (-not $Capabilities.hasListTemplates) { return @() }
    try {
        $output = & $Exe $Capabilities.listTemplatesFlag 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }
        return ($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    } catch { return @() }
}
function Get-KnownChatTemplateNames {
    @(
        'bailing','bailing-think','bailing2',
        'chatglm3','chatglm4','chatml',
        'command-r',
        'deepseek','deepseek2','deepseek3',
        'exaone3','exaone4',
        'falcon3',
        'gemma',
        'gigachat',
        'glmedge',
        'gpt-oss',
        'granite',
        'grok-2',
        'hunyuan-dense','hunyuan-moe',
        'kimi-k2',
        'llama2','llama2-sys','llama2-sys-bos','llama2-sys-strip',
        'llama3','llama4',
        'megrez',
        'minicpm',
        'mistral-v1','mistral-v3','mistral-v3-tekken','mistral-v7','mistral-v7-tekken',
        'monarch',
        'openchat',
        'orion',
        'phi3','phi4',
        'rwkv-world',
        'seed_oss',
        'smolvlm',
        'vicuna','vicuna-orca',
        'yandex',
        'zephyr'
    )
}
function Select-ChatTemplateBuiltin { param([string]$Exe, [hashtable]$Capabilities)
    $templates = @()
    if ($Capabilities.hasListTemplates) { $templates = Get-ChatTemplates -Exe $Exe -Capabilities $Capabilities }
    $usingFallback = $false
    if (-not $templates -or $templates.Count -eq 0) { $templates = Get-KnownChatTemplateNames; $usingFallback = $true }
    if (-not $templates -or $templates.Count -eq 0) {
        Write-Host "No built-in templates available. Type a name (e.g. 'command-r') or Enter to cancel." -ForegroundColor Yellow
        $manual = Read-Host "Chat template name"; if ([string]::IsNullOrWhiteSpace($manual)) { return $null }; return $manual.Trim()
    }
    if ($usingFallback) { Write-Host "Showing known chat template names (curated list):" -ForegroundColor Cyan }
    else { Write-Host "Available built-in chat templates from llama-cli:" -ForegroundColor Cyan }
    for ($i=0; $i -lt $templates.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $templates[$i]) }
    $choice = Read-Host "Select template number, or Enter to cancel"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
    $idx = 0; if (-not [int]::TryParse($choice, [ref]$idx)) { Write-Host "Invalid selection." -ForegroundColor Yellow; return $null }
    $idx--; if ($idx -lt 0 -or $idx -ge $templates.Count) { Write-Host "Selection out of range." -ForegroundColor Yellow; return $null }
    return $templates[$idx]
}

# Template file application
function Apply-Template($templateText, $systemText, $userText) {
    if (-not $templateText) { return $null }
    $sys = $(if ($systemText) { $systemText } else { "" })
    $usr = $(if ($userText)  { $userText  } else { "" })
    $out = $templateText.Replace("{{SYSTEM}}", $sys).Replace("{{User}}", $usr).Replace("{{USER}}", $usr)
    $out = $out.Replace("{{ASSISTANT}}", "")
    return $out
}

# NEW: filter output to remove banner/model info, showing only response after "... (truncated)"
function Apply-ExtraFilter {
    param([object[]]$Lines)
    
    # Find the line with "... (truncated)" and start from the next line
    $startIdx = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        if ($line -match '\.\.\.\s*\(truncated\)') {
            $startIdx = $i + 1
            break
        }
    }
    
    # If "... (truncated)" not found, look for first real response line (non-empty, not metadata)
    if ($startIdx -lt 0) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $line = [string]$Lines[$i]
            # Skip empty lines and metadata lines
            if (-not [string]::IsNullOrWhiteSpace($line) -and 
                $line -notmatch '(Loading model|build|model|modalities|available commands|/exit|/regen|/clear|/read|▄|██|▀)') {
                $startIdx = $i
                break
            }
        }
    }
    
    if ($startIdx -lt 0) { $startIdx = 0 }
    
    # Find the end - remove "[ Prompt: X t/s | Generation: X t/s ]" and "Exiting..." lines
    $endIdx = $Lines.Count - 1
    for ($i = $Lines.Count - 1; $i -ge $startIdx; $i--) {
        $line = [string]$Lines[$i]
        if ($line -match '\[\s*Prompt:.*Generation:.*\]' -or $line -match 'Exiting') {
            $endIdx = $i - 1
        } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
            break
        }
    }
    
    if ($endIdx -lt $startIdx) { return @() }
    
    return @($Lines[$startIdx..$endIdx])
}

# Config save/load (uses $ConfigPath and folder variables from caller scope)
function Save-Config($state) {
    $llamaExePath = $(if ($state.LlamaExePath) { $state.LlamaExePath } else { "" })
    $modelFolder  = $(if ($state.ModelFolder)  { $state.ModelFolder } else { "" })
    $modelName    = $(if ($state.ModelPath)    { [IO.Path]::GetFileName($state.ModelPath) } else { "" })
    $systemName   = $(if ($state.SystemPath)   { [IO.Path]::GetFileName($state.SystemPath) } else { "" })
    $userName     = $(if ($state.UserPath)     { [IO.Path]::GetFileName($state.UserPath) } else { "" })
    $templateName = $(if ($state.TemplatePath) { [IO.Path]::GetFileName($state.TemplatePath) } else { "" })
    $fmt = [Globalization.CultureInfo]::InvariantCulture

    $lines = @(
        "llama_exe_path=$llamaExePath"
        "model_folder=$modelFolder"
        "model_name=$modelName"
        "system_prompt_name=$systemName"
        "user_prompt_name=$userName"
        "template_name=$templateName"
        "template_builtin=$($state.TemplateName)"
        "n_predict=$($state.NPredict)"
        "ctx=$($state.Ctx)"
        "temp=$($state.Temp)"
        "top_p=$($state.TopP)"
        "seed=$($state.Seed)"
        "n_gpu_layers=$($state.NGpuLayers)"
        "no_warmup=$($state.NoWarmup)"
        "ignore_eos=$($state.IgnoreEOS)"
        "single_turn=$($state.SingleTurn)"
        "no_cnv=$($state.NoCnv)"
        "interactive=$($state.Interactive)"
        "runs=$([int]$state.Runs)"   # NEW: persist run count
        "repeat_last_n=$($state.RepeatLastN)"
        "quiet_output=$($state.QuietOutput)"
        "extra_filter=$($state.ExtraFilter)"
        "save_output_mode=$($state.SaveOutputMode)"
        "repeat_penalty={0}" -f ($state.RepeatPenalty.ToString('0.###', $fmt))
        "min_p={0}" -f ($state.MinP.ToString('0.###', $fmt))
        "smoothing_factor={0}" -f ($state.SmoothingFactor.ToString('0.###', $fmt))
        "combined_mode=$($state.CombinedMode)"
        "combined_path=$($state.CombinedPath)"
        "combined_profile=$($state.CombinedProfileName)"
        # NEW: persist mirostat settings
        "mirostat_mode=$($state.MirostatMode)"
        "mirostat_lr_min={0}" -f ([double]$state.MirostatLRMin).ToString('0.###', $fmt)
        "mirostat_lr_max={0}" -f ([double]$state.MirostatLRMax).ToString('0.###', $fmt)
        "mirostat_ent_min={0}" -f ([double]$state.MirostatEntMin).ToString('0.###', $fmt)
        "mirostat_ent_max={0}" -f ([double]$state.MirostatEntMax).ToString('0.###', $fmt)
        # NEW: persist mirostat fixed values
        "mirostat_lr_fixed={0}" -f ([double]$state.MirostatLRFixed).ToString('0.##', $fmt)
        "mirostat_ent_fixed={0}" -f ([double]$state.MirostatEntFixed).ToString('0.#',  $fmt)
        # NEW: persist logg toggle/path
        "save_logg=$($state.SaveLogg)"
        "logg_path=$($state.LoggPath)"
    )
    Set-Content -LiteralPath $ConfigPath -Value $lines -Encoding UTF8
}
function Load-Config([ref]$stateRef) {
    if (-not (Test-Path $ConfigPath)) { return $false }
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $ConfigPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $kv = $line.Split("=", 2)
        if ($kv.Count -eq 2) { $map[$kv[0].Trim()] = $kv[1].Trim() }
    }
    $state = $stateRef.Value
    $llamaExePath = $map["llama_exe_path"]
    $modelFolder  = $map["model_folder"]
    $modelName    = $map["model_name"]
    $systemName   = $map["system_prompt_name"]
    $userName     = $map["user_prompt_name"]
    $templateName = $map["template_name"]
    $builtinName  = $map["template_builtin"]

    $state.LlamaExePath  = $(if ($llamaExePath) { $llamaExePath } else { $null })
    $state.ModelFolder   = $(if ($modelFolder)  { $modelFolder } else { $ModelsDir })
    $state.ModelPath     = $(if ($modelName)    { Join-Path $state.ModelFolder $modelName } else { $null })
    $state.SystemPath    = $(if ($systemName)   { Join-Path $SystemDir    $systemName } else { $null })
    $state.UserPath      = $(if ($userName)     { Join-Path $UserDir      $userName } else { $null })
    $state.TemplatePath  = $(if ($templateName) { Join-Path $TemplatesDir $templateName } else { $null })
    $state.TemplateName  = $(if ($builtinName)  { $builtinName } else { $null })

    if ($map.ContainsKey("n_predict"))      { $state.NPredict      = [int]$map["n_predict"] }
    if ($map.ContainsKey("ctx"))            { $state.Ctx           = [int]$map["ctx"] }
    if ($map.ContainsKey("temp"))           { $state.Temp          = [double]$map["temp"] }
    if ($map.ContainsKey("top_p"))          { $state.TopP          = [double]$map["top_p"] }
    if ($map.ContainsKey("seed"))           { $state.Seed          = [int]$map["seed"] }
    if ($map.ContainsKey("n_gpu_layers"))   { $state.NGpuLayers    = [int]$map["n_gpu_layers"] }
    if ($map.ContainsKey("no_warmup"))      { $state.NoWarmup      = [bool]::Parse($map["no_warmup"]) }
    if ($map.ContainsKey("ignore_eos"))     { $state.IgnoreEOS     = [bool]::Parse($map["ignore_eos"]) }
    if ($map.ContainsKey("single_turn"))    { $state.SingleTurn    = [bool]::Parse($map["single_turn"]) }
    if ($map.ContainsKey("no_cnv"))         { $state.NoCnv         = [bool]::Parse($map["no_cnv"]) }
    if ($map.ContainsKey("interactive"))    { $state.Interactive   = [bool]::Parse($map["interactive"]) }
    if ($map.ContainsKey("runs"))           { 
        try { $state.Runs = [int]$map["runs"] } catch { $state.Runs = [int]$state.Runs }
        if ($state.Runs -lt 1) { $state.Runs = 1 }
    }

    if ($map.ContainsKey("repeat_last_n"))  { $state.RepeatLastN   = [int]$map["repeat_last_n"] }
    if ($map.ContainsKey("quiet_output"))   { $state.QuietOutput   = [bool]::Parse($map["quiet_output"]) }
    if ($map.ContainsKey("extra_filter"))   { $state.ExtraFilter   = [bool]::Parse($map["extra_filter"]) }
    if ($map.ContainsKey("save_output_mode")) { $state.SaveOutputMode = $map["save_output_mode"] } else { if (-not $state.SaveOutputMode) { $state.SaveOutputMode = 'separate' } }
    if ($map.ContainsKey("repeat_penalty")) {
        try {
            $state.RepeatPenalty = [double]::Parse($map["repeat_penalty"], [Globalization.CultureInfo]::InvariantCulture)
        } catch {
            # fallback: leave as-is if parse fails
        }
    }

    if ($map.ContainsKey("min_p")) {
        try {
            $state.MinP = [double]::Parse($map["min_p"], [Globalization.CultureInfo]::InvariantCulture)
        } catch { }
    }

    if ($map.ContainsKey("smoothing_factor")) {
        try {
            $state.SmoothingFactor = [double]::Parse($map["smoothing_factor"], [Globalization.CultureInfo]::InvariantCulture)
        } catch { }
    }

    # ... existing assignments (quiet_output, save_output_mode, combined_*) ...
    if ($map.ContainsKey("combined_mode"))    { $state.CombinedMode        = $map["combined_mode"] }
    if ($map.ContainsKey("combined_path"))    { $state.CombinedPath        = $map["combined_path"] }
    if ($map.ContainsKey("combined_profile")) { $state.CombinedProfileName = $map["combined_profile"] }

    # NEW: load mirostat settings with sane defaults
    if ($map.ContainsKey("mirostat_mode")) { $state.MirostatMode = [int]$map["mirostat_mode"] } else { if (-not $state.MirostatMode) { $state.MirostatMode = 0 } }
    try {
        if ($map.ContainsKey("mirostat_lr_min")) { $state.MirostatLRMin = [double]::Parse($map["mirostat_lr_min"], [Globalization.CultureInfo]::InvariantCulture) }
        if ($map.ContainsKey("mirostat_lr_max")) { $state.MirostatLRMax = [double]::Parse($map["mirostat_lr_max"], [Globalization.CultureInfo]::InvariantCulture) }
        if ($map.ContainsKey("mirostat_ent_min")) { $state.MirostatEntMin = [double]::Parse($map["mirostat_ent_min"], [Globalization.CultureInfo]::InvariantCulture) }
        if ($map.ContainsKey("mirostat_ent_max")) { $state.MirostatEntMax = [double]::Parse($map["mirostat_ent_max"], [Globalization.CultureInfo]::InvariantCulture) }
    } catch { }
    # defaults if any are null
    if ($state.MirostatMode -eq $null) { $state.MirostatMode = 0 }  # 0 = disabled
    if ($state.MirostatLRMin -eq $null)  { $state.MirostatLRMin  = 0.05 }  # default min
    if ($state.MirostatLRMax -eq $null)  { $state.MirostatLRMax  = 0.15 }  # default max
    if ($state.MirostatEntMin -eq $null) { $state.MirostatEntMin = 4.0 }   # default min
    if ($state.MirostatEntMax -eq $null) { $state.MirostatEntMax = 7.0 }   # default max

    # NEW: load mirostat fixed values (with defaults)
    try {
        if ($map.ContainsKey("mirostat_lr_fixed"))  { $state.MirostatLRFixed  = [double]::Parse($map["mirostat_lr_fixed"],  [Globalization.CultureInfo]::InvariantCulture) }
        if ($map.ContainsKey("mirostat_ent_fixed")) { $state.MirostatEntFixed = [double]::Parse($map["mirostat_ent_fixed"], [Globalization.CultureInfo]::InvariantCulture) }
    } catch { }
    if ($state.MirostatLRFixed  -eq $null) { $state.MirostatLRFixed  = 0.1 }
    if ($state.MirostatEntFixed -eq $null) { $state.MirostatEntFixed = 5.0 }

    # NEW: load logg toggle/path
    $state.SaveLogg = Parse-ConfigBool -map $map -key "save_logg" -default $state.SaveLogg
    if ($map.ContainsKey("logg_path")) { $state.LoggPath = $map["logg_path"] }

    if ($state.LlamaExePath  -and -not (Test-Path $state.LlamaExePath))  { $state.LlamaExePath  = $null }
    if ($state.ModelPath     -and -not (Test-Path $state.ModelPath))     { $state.ModelPath     = $null }
    if ($state.SystemPath    -and -not (Test-Path $state.SystemPath))    { $state.SystemPath    = $null }
    if ($state.UserPath      -and -not (Test-Path $state.UserPath))      { $state.UserPath      = $null }
    if ($state.TemplatePath  -and -not (Test-Path $state.TemplatePath))  { $state.TemplatePath  = $null }
    if ($state.CombinedPath  -and -not (Test-Path -LiteralPath $state.CombinedPath)) { $state.CombinedPath = $null }

    $stateRef.Value = $state
    return $true
}

# ADD: robust boolean parser for config values (accepts true/false, 1/0, yes/no, on/off)
function Parse-ConfigBool {
    param(
        [hashtable]$map,
        [string]$key,
        [object]$default = $false
    )

    # Coerce provided default to a boolean safely
    $defVal = $false
    if ($default -is [bool]) {
        $defVal = [bool]$default
    } elseif ($default -is [string] -and -not [string]::IsNullOrWhiteSpace($default)) {
        $ds = $default.Trim().ToLowerInvariant()
        if ($ds -in @('true','t','1','yes','y','on')) { $defVal = $true }
        elseif ($ds -in @('false','f','0','no','n','off')) { $defVal = $false }
    }

    if (-not $map.ContainsKey($key)) { return $defVal }
    $raw = $map[$key]
    if ([string]::IsNullOrWhiteSpace($raw)) { return $defVal }
    $s = $raw.Trim().ToLowerInvariant()
    if ($s -in @('true','t','1','yes','y','on')) { return $true }
    if ($s -in @('false','f','0','no','n','off')) { return $false }
    return $defVal
}

# REPLACE: robust parse for save_logg (avoid crash on non-True/False values)
# if ($map.ContainsKey("save_logg")) { $state.SaveLogg = [bool]::Parse($map["save_logg"]) }

# Build llama-cli args
function Build-Args {
    param(
        [Parameter(Mandatory=$true)]$state,
        [Parameter(Mandatory=$true)][hashtable]$caps,
        [Parameter()][object]$SamplingValues,
        [Parameter()][string]$CombinedOverridePath = $null
    )

    $argv = @("-m", $state.ModelPath)
    # NEW: use invariant culture for numeric flags
    $fmt = [Globalization.CultureInfo]::InvariantCulture

    # Insert sampling flags immediately after -m (handle PSCustomObject or Hashtable)
    if ($SamplingValues) {
        $svTemp = $null
        $svTopP = $null
        $svTopK = $null
        $svTopK = $null

        if ($SamplingValues -is [hashtable]) {
            if ($SamplingValues.ContainsKey('temperature')) { $svTemp = [double]$SamplingValues['temperature'] }
            if ($SamplingValues.ContainsKey('top_p'))       { $svTopP = [double]$SamplingValues['top_p'] }
            if ($SamplingValues.ContainsKey('top_k'))       { $svTopK = [int]$SamplingValues['top_k'] }
        } else {
            try { $svTemp = [double]$SamplingValues.temperature } catch { }
            try { $svTopP = [double]$SamplingValues.top_p }      catch { }
            try { $svTopK = [int]$SamplingValues.top_k }         catch { }
        }

        if ($svTemp -ne $null) { $argv += @('--temp',  ($svTemp.ToString('0.###', $fmt))) }
        if ($svTopP -ne $null) { $argv += @('--top-p', ($svTopP.ToString('0.###', $fmt))) }
        if ($svTopK -ne $null -and $svTopK -gt 0) { $argv += @('--top-k', [string]$svTopK) }
    }

    # Core generation settings
    $argv += @("-n", "$($state.NPredict)", "-c", "$($state.Ctx)")

    # Only add repeat-penalty when not default 1.0
    if ($state.RepeatPenalty -ne 1.0) {
        $argv += @("--repeat-penalty", "$($state.RepeatPenalty)")
    }

    # Only add --repeat-last-n when not default 64
    if ($state.RepeatLastN -ne 64) {
        $argv += @("--repeat-last-n", "$($state.RepeatLastN)")
    }

    # CHANGE: always add --min-p explicitly (default is 0.05 in our UI)
    $mp = [double]$state.MinP
    if ($mp -lt 0.0) { $mp = 0.0 }
    if ($mp -gt 1.0) { $mp = 1.0 }
    $argv += @('--min-p', ($mp.ToString('0.###', $fmt)))

    # Seed: do not add -s when -1 (random)
    if ($state.Seed -ge 0) {
        $argv += @("-s", "$($state.Seed)")
    }
    # Emit --n-gpu-layers only when not auto (-1)
    if ($state.NGpuLayers -ne -1) { $argv += @("--n-gpu-layers", "$($state.NGpuLayers)") }
    if ($state.NoWarmup)                         { $argv += @("--no-warmup") }
    if ($state.IgnoreEOS)                        { $argv += @("--ignore-eos") }
    if ($state.NoCnv)                            { $argv += @("-no-cnv") }
    if ($state.SingleTurn)                       { $argv += @("--single-turn") }
    if ($state.SimpleIO -and $caps.hasSimpleIO)  { $argv += @("--simple-io") }

    # NEW: add --no-display-prompt when QuietOutput is enabled
    if ($state.QuietOutput) {
        $argv += @("--no-display-prompt")
    }

    # --- Combined prompt precedence (detect early) ---
    $useCombined  = $false
    $combinedPath = $null

    if ($CombinedOverridePath) {
        $useCombined  = $true
        $combinedPath = $CombinedOverridePath
    } elseif ($state.CombinedMode -eq 'File' -and $state.CombinedPath) {
        $useCombined  = $true
        $combinedPath = $state.CombinedPath
    }

    # INSERT: If using combined prompt, send ONLY the combined file and return (skip any chat template flags)
    if ($useCombined -and $combinedPath) {
        $argv += @("--file", $combinedPath)
        return $argv
    }

    # Use an explicit template only if the user selected one; do not auto-pick based on model name
    $templateName = $state.TemplateName

    $useTemplateInline = $false
    if ($templateName) {
        if ($caps.hasTemplateNameFlag) {
            $argv += @($caps.templateNameFlag, $templateName)
        } elseif ($caps.hasTemplateFileFlag) {
            $argv += @($caps.templateFileFlag, $templateName)
        } else {
            Write-Host "Selected built-in template '$templateName' but llama-cli build does not support template flags." -ForegroundColor Yellow
        }
    } elseif ($state.TemplatePath) {
        if ($caps.hasTemplateFileFlag) {
            $argv += @($caps.templateFileFlag, $state.TemplatePath)
        } else {
            $useTemplateInline = $true
        }
    }

    # Inline template rendering if needed and supported by our fallback
    if ($useTemplateInline -and $state.TemplatePath) {
        $sysText  = Read-TextFile $state.SystemPath
        $userText = Read-TextFile $state.UserPath
        $tmplText = Read-TextFile $state.TemplatePath
        $combined = Apply-Template $tmplText $sysText $userText
        if ($combined) { $argv += @("-p", $combined) }
        return $argv
    }

    # Otherwise: separate system/user handling
    $sysText  = Read-TextFile $state.SystemPath
    $userText = Read-TextFile $state.UserPath

    if ($state.SystemPath) {
        $argv += @("--system-prompt-file", $state.SystemPath)
    } elseif ($sysText -and -not $state.UserPath) {
        $argv += @("-p", "### System:`n$sysText`n`n")
    }

    if ($state.UserPath) {
        $argv += @("--file", $state.UserPath)
    } elseif ($userText) {
        $argv += @("-p", $userText)
    }

    # Mirostat flags: use per-run SamplingValues when available
    $miroMode = [int]$state.MirostatMode
    if ($miroMode -gt 0) {
        $argv += @('--mirostat', [string]$miroMode)
        $svLR  = $null; $svENT = $null
        if ($SamplingValues) {
            try { $svLR  = [double]$SamplingValues.mirostat_lr }  catch { }
            try { $svENT = [double]$SamplingValues.mirostat_ent } catch { }
        }
        if ($svLR  -eq $null -or $svLR  -le 0.0) { $svLR  = 0.02 }
        if ($svENT -eq $null -or $svENT -le 0.0) { $svENT = 5.0 }
        # Format: lr with 2 decimals, ent with 1 decimal
        $argv += @('--mirostat-lr',  ($svLR.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)))
        $argv += @('--mirostat-ent', ($svENT.ToString('0.#',  [Globalization.CultureInfo]::InvariantCulture)))
    }

    return $argv
}

function Print-Summary($state, $caps, $LlamaExe) {
    Write-Host ""
    Write-Host "---------- Summary ----------" -ForegroundColor Cyan
    Write-Host "llama-cli.exe: $LlamaExe"
    Write-Host "Model:         " + ($(if ($state.ModelPath) { $state.ModelPath } else { "None" }))
    Write-Host "System file:   " + ($(if ($state.SystemPath){ $state.SystemPath } else { "None" }))
    Write-Host "User file:     " + ($(if ($state.UserPath)  { $state.UserPath  } else { "None" }))
    # Chat template summary: default means rely on model-provided template (no flags)
    $tmplDisp = if ($state.TemplateName) {
        "builtin: $($state.TemplateName)"
    } elseif ($state.TemplatePath) {
        $state.TemplatePath
    } else {
        "default (model-provided; no --chat-template flags)"
    }
    if ($state.CombinedMode -ne 'Off' -and ($state.TemplateName -or $state.TemplatePath)) {
        $tmplDisp += " (ignored; combined prompt active)"
    }
    Write-Host "Chat template: $tmplDisp"

    # Combined prompt summary
    $comb = switch ($state.CombinedMode) {
        'File'      { "File: $($state.CombinedPath) (profile: $($state.CombinedProfileName))" }
        'Ephemeral' { "Ephemeral (profile: $($state.CombinedProfileName))" }
        default     { "Off" }
    }
    Write-Host "Combined prompt: $comb"
    Write-Host "n_predict:     $($state.NPredict)"
    Write-Host "ctx_size:      $($state.Ctx)"
    Write-Host "temp:          $($state.Temp)"
    Write-Host "top_p:         $($state.TopP)"
    Write-Host "top_k:         $($state.TopK)"

    # UPDATED: min_p summary default is 0.05
    $mp = [double]$state.MinP
    $mpLabel = ('{0:0.###}' -f $mp)
    $mpDisp  = if ([math]::Abs($mp - 0.05) -lt 1e-9) { "$mpLabel (default)" } elseif ($mp -le 0.0) { "$mpLabel (disabled; 0.0)" } else { "$mpLabel (--min-p)" }
    Write-Host "min_p:         $mpDisp"

    # UPDATED: smoothing summary warns when unsupported
    $sf = [double]$state.SmoothingFactor
    $sfLabel = ('{0:0.###}' -f $sf)
    if ($sf -le 0.0) {
        Write-Host "smoothing:     $sfLabel (default; disabled)"
    } else {
        $flagInfo = if ($caps.hasSmoothingFactor) { "(--smoothing-factor)" } else { "(requested; this llama-cli likely does not support it)" }
        Write-Host "smoothing:     $sfLabel $flagInfo"
    }

    Write-Host "repeat_pen:    $($state.RepeatPenalty)"
    $rlndisp = switch ($state.RepeatLastN) { 0 { "0 (disabled)" } -1 { "-1 (full context)" } default { "$($state.RepeatLastN)" } }
    Write-Host "repeat_last_n: $rlndisp"
    $seedDisp = if ($state.Seed -lt 0) { "$($state.Seed) (random)" } else { "$($state.Seed)" }
    Write-Host "seed:          $seedDisp"
    $nglSum = if ($state.NGpuLayers -eq -1) { "-1 (auto: max VRAM)" } else { "$($state.NGpuLayers)" }
    Write-Host "n_gpu_layers:  $nglSum"
    Write-Host ("no_warmup:      {0}" -f (Format-FlagStatus $state.NoWarmup '--no-warmup'))
    Write-Host ("ignore_eos:     {0}" -f (Format-FlagStatus $state.IgnoreEOS '--ignore-eos'))  # prevents early stop; may ramble when added
    Write-Host ("single_turn:    {0}" -f (Format-FlagStatus $state.SingleTurn '--single-turn'))
    Write-Host ("no_cnv:         {0}" -f (Format-FlagStatus $state.NoCnv '-no-cnv'))
    Write-Host ("simple_io:      {0}" -f (Format-FlagStatus $state.SimpleIO '--simple-io' $caps.hasSimpleIO))
    Write-Host "quiet_output:  " + ($(if ($state.QuietOutput) { "On (--no-display-prompt, stderr suppressed)" } else { "Off" }))

    # UPDATED: reflect what we actually pass for the selected files
    $sysFlag  = if ($state.SystemPath) { "--system-prompt-file" } elseif ($caps.hasSystem) { "--system" } else { "None" }
    $userFlag = if ($state.UserPath)   { "--file" } else { "-p (string)" }
    Write-Host "System flag:   $sysFlag"
    Write-Host "User flag:     $userFlag"

    $tmplFlags = @(); if ($caps.hasTemplateNameFlag) { $tmplFlags += $caps.templateNameFlag }; if ($caps.hasTemplateFileFlag) { $tmplFlags += $caps.templateFileFlag }
    Write-Host "Template flag: " + ($(if ($tmplFlags.Count -gt 0) { ($tmplFlags -join ', ') } else { "None (inline for file templates if selected)" }))
    Write-Host "Runs:          $($state.Runs)"
    $saveInfo = if ($state.SaveOutput) { "On ($($state.SaveOutputMode)) -> $($state.OutputDir)" } else { "Off" }
    Write-Host "Save output:   $saveInfo"
    # NEW: combined prompt summary
    Write-Host "-----------------------------" -ForegroundColor Cyan
    Write-Host ""
}

# REPLACE the formatter: avoid $Args name and use -join safely
function Format-ArgsForDisplay {
    param([object[]]$ArgList)

    # Coerce to array and drop null/empty
    $safe = @($ArgList) | Where-Object { $_ -ne $null -and [string]$_ -ne '' }

    # Quote items containing whitespace/newlines or double quotes
    $quoted = foreach ($a in $safe) {
        $s = [string]$a
        if ($s -match '[\s\r\n"]') {
            '"' + ($s -replace '"','\"') + '"'
        } else {
            $s
        }
    }

    # Use -join to avoid .NET Join null issues
    return ($quoted -join ' ')
}

# NEW: preview helper – shows the exact one-run command without executing
function Preview-RunCommand {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$LlamaExe,
        [Parameter(Mandatory=$true)][hashtable]$Caps,
        [Parameter(Mandatory=$true)]$SamplingConfig,
        [string]$ConfigFilePath = $null,
        # NEW: allow passing a prepared combined prompt file for preview
        [string]$CombinedOverridePath = $null
    )
    $sv = Get-SamplingValuesForRun -Config $SamplingConfig -RunCount 1 -RunIndex 1

    $runArgs = @()
    if ($ConfigFilePath) { $runArgs += @('--config', $ConfigFilePath) }
    # PASS the combined override if provided so preview matches "Run now"
    $runArgs += (Build-Args -state $State -caps $Caps -SamplingValues $sv -CombinedOverridePath $CombinedOverridePath)
    $cmdLine = (Format-ArgsForDisplay -ArgList $runArgs)
    Write-Host "Command preview:" -ForegroundColor Cyan
    Write-Host "$LlamaExe $cmdLine"
}

# Runner that honors sampling-config per run (matches menu "21")
function Invoke-RunWithSampling {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$LlamaExe,
        [Parameter(Mandatory=$true)]$SamplingConfig,
        [Parameter(Mandatory=$true)][string]$SamplingConfigPath,
        [Parameter(Mandatory=$true)][hashtable]$Caps,
        [string]$ConfigFilePath = $null,
        [string]$CombinedDir = $null
    )

    if (-not $State.ModelPath) {
        Write-Host "No model selected. Please choose a model first." -ForegroundColor Red
        return
    }

    # FIX: robustly compute RunCount from State.Runs
    $RunCount = 1
    if ([int]::TryParse([string]$State.Runs, [ref]$RunCount)) {
        if ($RunCount -lt 1) { $RunCount = 1 }
    } else {
        $RunCount = 1
    }

    Initialize-Random -Seed $SamplingConfig.seed

    # Prepare ephemeral combined file once per session (if enabled)
    $combinedOverride = $null
    if ($State.CombinedMode -eq 'Ephemeral' -and $CombinedDir) {
        $combinedOverride = Prepare-CombinedForSession -State $State -CombinedDir $CombinedDir
    }

    # NEW: pre-create session output path for append mode; guard against nulls
    $sessionOutPath = $null
    if ($State.SaveOutput -and $State.SaveOutputMode -eq 'append') {
        if ([string]::IsNullOrWhiteSpace($State.OutputDir)) {
            # fall back to default outputs dir (if defined)
            $State.OutputDir = $OutputDir
        }
        if (-not (Test-Path -LiteralPath $State.OutputDir)) {
            New-Item -ItemType Directory -Path $State.OutputDir | Out-Null
        }
        $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
        $model   = Sanitize-Filename (BaseName $State.ModelPath)
        $sessionOutPath = Join-Path $State.OutputDir ("{0}_{1}_session.txt" -f $stamp, $model)
        # Initialize empty file
        Set-Content -LiteralPath $sessionOutPath -Value "" -Encoding utf8
    }

    for ($i = 1; $i -le $RunCount; $i++) {
        # CHANGE: get all per-run values (including mirostat) from sampler
        $sv = Get-SamplingValuesForRun -Config $SamplingConfig -RunCount $RunCount -RunIndex $i

        $runArgs = @()
        if ($ConfigFilePath) { $runArgs += @('--config', $ConfigFilePath) }
        $runArgs += (Build-Args -state $State -caps $Caps -SamplingValues $sv -CombinedOverridePath $combinedOverride)

        # Build the exact command line string we will execute
        $cmdLine = (Format-ArgsForDisplay -ArgList $runArgs)
        if (-not $State.QuietOutput) {
            Write-Host ("Launching: {0} {1}" -f $LlamaExe, $cmdLine) -ForegroundColor Green
        }

        # INSERT: precompute separate-mode output file and write log BEFORE launching llama-cli
        $outPath = $null
        if ($State.SaveOutput -and $State.SaveOutputMode -eq 'separate' -and -not [string]::IsNullOrWhiteSpace($State.OutputDir)) {
            if (-not (Test-Path -LiteralPath $State.OutputDir)) {
                New-Item -ItemType Directory -Path $State.OutputDir | Out-Null
            }
            $stampPre = Get-Date -Format 'yyyyMMdd-HHmmss'
            $outPath  = Join-Path $State.OutputDir ("{0}_run{1:D3}.txt" -f $stampPre, $i)
        }

        $lines = @()

      if ($State.QuietOutput) {
            # Quiet mode: suppress stderr; stream stdout to screen and capture to $lines
            & $LlamaExe @runArgs 2>$null | Tee-Object -Variable lines | Write-Output
        } else {
            # Prefer PS 7.3+ behavior to honor -ErrorAction for native commands; else fallback to cmd /c
            $hadNativeSwitch = $false
            try {
                $null = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction Stop
                $hadNativeSwitch = $true
            } catch { }

            if ($hadNativeSwitch) {
                $oldNative = $PSNativeCommandUseErrorActionPreference
                $PSNativeCommandUseErrorActionPreference = $true
                try {
                    & $LlamaExe @runArgs 2>&1 -ErrorAction SilentlyContinue |
                        Tee-Object -Variable lines | Out-Host
                } finally {
                    $PSNativeCommandUseErrorActionPreference = $oldNative
                }
            } else {
                # Fallback for older PowerShell: run via cmd /c to avoid NativeCommandError records
                $fullCmd = ('"{0}" {1}' -f $LlamaExe, $cmdLine)
                cmd /c $fullCmd 2>&1 | Tee-Object -Variable lines | Out-Host
            }
        }
        
        # NEW: Apply extra filter to remove banner/model info
        if ($State.ExtraFilter) {
            $lines = Apply-ExtraFilter -Lines $lines
        }
        
        $exit = $LASTEXITCODE

        # NEW: Calculate word count and token count from output
        $contentText = ($lines -join [Environment]::NewLine).TrimEnd()
        $wordCount = if ($contentText -match '\S') {
            ($contentText -split '\s+' | Where-Object { $_ }).Count
        } else {
            0
        }
        # Estimate token count: ~1.3 words per token (common approximation for English)
        $tokenEstimate = [math]::Round($wordCount / 1.3)

        # INSERT: log AFTER llama-cli execution (append mode -> only first run's sessionOutPath; separate mode -> per run file)
        if ($State.SaveLogg) {
            $loggPath = $State.LoggPath
            if ([string]::IsNullOrWhiteSpace($loggPath)) {
                $loggPath = if (-not [string]::IsNullOrWhiteSpace($State.OutputDir)) { Join-Path $State.OutputDir 'logg.txt' } else { 'logg.txt' }
            }
            $parent = Split-Path -Path $loggPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) { Ensure-Dir $parent }

            if ($State.SaveOutputMode -eq 'append') {
                if ($i -eq 1 -and $sessionOutPath) {
                    Add-Content -LiteralPath $loggPath -Value $sessionOutPath -Encoding utf8
                }
            } elseif ($State.SaveOutputMode -eq 'separate') {
                if ($outPath) {
                    Add-Content -LiteralPath $loggPath -Value $outPath -Encoding utf8
                }
            }
            Add-Content -LiteralPath $loggPath -Value ("story {0}" -f $i) -Encoding utf8
            Add-Content -LiteralPath $loggPath -Value $cmdLine -Encoding utf8
            Add-Content -LiteralPath $loggPath -Value ("Words: {0}, Tokens (est.): {1}" -f $wordCount, $tokenEstimate) -Encoding utf8
            Add-Content -LiteralPath $loggPath -Value "" -Encoding utf8
        }

        # Saving behavior based on mode
        if ($State.SaveOutput -and -not [string]::IsNullOrWhiteSpace($State.OutputDir)) {
            if ($State.SaveOutputMode -eq 'append') {
                # NEW: lazy init session file if not created earlier (avoids null Add-Content path)
                if ([string]::IsNullOrWhiteSpace($sessionOutPath)) {
                    if (-not (Test-Path -LiteralPath $State.OutputDir)) {
                        New-Item -ItemType Directory -Path $State.OutputDir | Out-Null
                    }
                    $stamp2 = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $model2 = Sanitize-Filename (BaseName $State.ModelPath)
                    $sessionOutPath = Join-Path $State.OutputDir ("{0}_{1}_session.txt" -f $stamp2, $model2)
                    Set-Content -LiteralPath $sessionOutPath -Value "" -Encoding utf8
                }

                $sectionHeader = ("----story {0}-----" -f $i)
                $contentToWrite = (($lines -join [Environment]::NewLine).TrimEnd())

                Add-Content -LiteralPath $sessionOutPath -Value $sectionHeader -Encoding utf8
                Add-Content -LiteralPath $sessionOutPath -Value $contentToWrite -Encoding utf8
                Add-Content -LiteralPath $sessionOutPath -Value "" -Encoding utf8

                if (-not $State.QuietOutput) {
                    Write-Host "Appended output to $sessionOutPath (story $i)" -ForegroundColor DarkGreen
                }
            } elseif ($State.SaveOutputMode -eq 'separate') {
                if (-not (Test-Path -LiteralPath $State.OutputDir)) {
                    New-Item -ItemType Directory -Path $State.OutputDir | Out-Null
                }
                $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
                $outPath = Join-Path $State.OutputDir ("{0}_run{1:D3}.txt" -f $stamp, $i)
                if ($State.QuietOutput) {
                    Set-Content -LiteralPath $outPath -Value (($lines -join [Environment]::NewLine).TrimEnd()) -Encoding utf8
                } else {
                    $header  = "[Command] $LamaExe $cmdLine`r`n"
                    Set-Content -LiteralPath $outPath -Value ($header + (($lines -join [Environment]::NewLine).TrimEnd())) -Encoding utf8
                }
                if (-not $State.QuietOutput) {
                    Write-Host "Saved output to $outPath" -ForegroundColor DarkGreen
                }
            } else {
                # 'none' => do not save anything
            }
        }

        if (-not $State.QuietOutput -and $exit -ne 0) {
            Write-Host "llama-cli exited with code $exit" -ForegroundColor Red
        }
    }
}

# ADD: robust streaming runner to avoid cmd /c and & invocation issues
function Invoke-ProcessStreaming {
    param(
        [Parameter(Mandatory=$true)][string]$Exe,
        [Parameter(Mandatory=$true)][string[]]$Args,
        [switch]$SuppressStderr = $false
    )

    # Build a single argument string with safe quoting
    $argItems = @()
    foreach ($a in $Args) {
        if ($a -eq $null) { continue }
        $s = [string]$a
        if ($s -match '[\s\r\n"]') { $s = '"' + ($s -replace '"','\"') + '"' }
        $argItems += $s
    }
    $argLine = ($argItems -join ' ')

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [string]$Exe
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $sb = New-Object System.Text.StringBuilder

    $null = $proc.add_ErrorDataReceived({
        param($sender, $e)
        if ($e.Data -ne $null -and -not $SuppressStderr) {
            Write-Host $e.Data
        }
    })

    [void]$proc.Start()
    $proc.BeginErrorReadLine()

    $reader = $proc.StandardOutput
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line -ne $null) {
            [void]$sb.AppendLine($line)
            Write-Host $line
        }
    }

    $proc.WaitForExit()

    return @{
        ExitCode = $proc.ExitCode
        Text     = $sb.ToString()
    }
}
