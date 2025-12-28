function Start-Storyteller {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$LlamaExe,
        [Parameter(Mandatory=$true)][hashtable]$Caps,
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [Parameter(Mandatory=$true)][ref]$SamplingConfig,
        [Parameter(Mandatory=$true)][string]$SamplingConfigPath
    )

    # Make LlamaExe mutable in this scope
    [string]$script:CurrentLlamaExe = $LlamaExe

    function Sync-SamplingMenuValues {
        $script:temperature = [double]$SamplingConfig.Value.temperature.fixed
        $script:top_p       = [double]$SamplingConfig.Value.top_p.fixed
        $script:top_k       = [int]   $SamplingConfig.Value.top_k.fixed
    }
    Sync-SamplingMenuValues

    # Ensure sampler config mirrors State's mirostat values (so summary and per-run sampling use them)
    function Sync-MirostatToSamplingConfig {
        param([ref]$Cfg, $St)
        # Ensure blocks exist
        if (-not ($Cfg.Value.PSObject.Properties.Name -contains 'mirostat_lr')) {
            $Cfg.Value | Add-Member -NotePropertyName 'mirostat_lr' -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not ($Cfg.Value.PSObject.Properties.Name -contains 'mirostat_ent')) {
            $Cfg.Value | Add-Member -NotePropertyName 'mirostat_ent' -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        # Copy fixed/range from State (config.txt) into runtime sampling config
        $Cfg.Value.mirostat_lr.fixed  = [double]$St.MirostatLRFixed
        $Cfg.Value.mirostat_lr.min    = [double]$St.MirostatLRMin
        $Cfg.Value.mirostat_lr.max    = [double]$St.MirostatLRMax
        $Cfg.Value.mirostat_ent.fixed = [double]$St.MirostatEntFixed
        $Cfg.Value.mirostat_ent.min   = [double]$St.MirostatEntMin
        $Cfg.Value.mirostat_ent.max   = [double]$St.MirostatEntMax
    }

    # INITIAL SYNC AND SUMMARY
    Sync-MirostatToSamplingConfig -Cfg $SamplingConfig -St $State
    $SamplingSummary = Format-SamplingSummary -Config (Normalize-SamplingConfig -Config $SamplingConfig.Value)

    # ADD: define before any usage
    function Format-FlagStatus {
        param($enabled, $flag, $supported = $true)
        if ($enabled) {
            if ($supported) { return "Added ($flag)" }
            else { return "Added ($flag; unsupported)" }
        } else {
            if ($supported) { return "Not added" }
            else { return "Not added (unsupported)" }
        }
    }

    # SYNC: copy mirostat fixed/range from State (config.txt) into SamplingConfig.Value
    if (-not ($SamplingConfig.Value.PSObject.Properties.Name -contains 'mirostat_lr')) {
        $SamplingConfig.Value | Add-Member -NotePropertyName 'mirostat_lr' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not ($SamplingConfig.Value.PSObject.Properties.Name -contains 'mirostat_ent')) {
        $SamplingConfig.Value | Add-Member -NotePropertyName 'mirostat_ent' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $SamplingConfig.Value.mirostat_lr.fixed  = [double]$State.MirostatLRFixed
    $SamplingConfig.Value.mirostat_lr.min    = [double]$State.MirostatLRMin
    $SamplingConfig.Value.mirostat_lr.max    = [double]$State.MirostatLRMax
    $SamplingConfig.Value.mirostat_ent.fixed = [double]$State.MirostatEntFixed
    $SamplingConfig.Value.mirostat_ent.min   = [double]$State.MirostatEntMin
    $SamplingConfig.Value.mirostat_ent.max   = [double]$State.MirostatEntMax

    # Recompute summary after sync (prevents 0/0 display)
    $SamplingSummary = Format-SamplingSummary -Config (Normalize-SamplingConfig -Config $SamplingConfig.Value)

    while ($true) {
        # Compute sampling summary but DO NOT print it here
        $SamplingSummary = Format-SamplingSummary -Config (Normalize-SamplingConfig -Config $SamplingConfig.Value)

        Write-Host ""
        Write-Host "==============================" -ForegroundColor Cyan
        Write-Host "llama-cli Scene Parameter Tester (enter number)"
        Write-Host " 0) Program:        $($State.LlamaExePath)"
        Write-Host "    Folder:         $($State.ModelFolder)"
        Write-Host " 1) Model:          $(BaseName $State.ModelPath) (folder: models)"

        # NEW: ensure combActive is defined
        $combActive = ($State.CombinedMode -ne 'Off')

        $sysLabel = BaseName $State.SystemPath
        if ($combActive) { $sysLabel += " (ignored; using combined)" }
        Write-Host " 2) System prompt:  $sysLabel (folder: system_prompt)"

        $usrLabel = BaseName $State.UserPath
        if ($combActive) { $usrLabel += " (ignored; using combined)" }
        Write-Host " 3) User prompt:    $usrLabel (folder: user_prompt)"

        # CHANGE: show "(default)" when no template is selected
        $tmplDisp = if ($State.TemplateName) { "builtin: $($State.TemplateName)" } else { $(BaseName $State.TemplatePath) }
        if ($combActive -and $tmplDisp -and $tmplDisp -ne "None") { $tmplDisp += " (note: combined + template can conflict)" }
        if (-not $tmplDisp -or $tmplDisp -eq "None") { $tmplDisp = "(default)" }
        Write-Host " 4) Chat template:  $tmplDisp"

        Write-Host " 5) n_predict:      $($State.NPredict)"
        Write-Host " 6) ctx_size:       $($State.Ctx)"
        Write-Host (" 7) temperature:    {0}" -f ('{0:0.###}' -f [double]$SamplingConfig.Value.temperature.fixed))
        Write-Host (" 8) top_p:          {0}" -f ('{0:0.###}' -f [double]$SamplingConfig.Value.top_p.fixed))
        Write-Host (" 9) top_k:          {0}" -f [int]$SamplingConfig.Value.top_k.fixed)

        # 10) min_p
        $mp = [double]$State.MinP
        $mpLabel = ('{0:0.###}' -f $mp)
        $mpDisplay = if ([math]::Abs($mp - 0.05) -lt 1e-9) {
            "$mpLabel (default: 0.05; recommended: min-p 0.02-0.05)"
        } elseif ($mp -le 0.0) {
            "$mpLabel (disabled; set 0.0 to disable; default is 0.05)"
        } else {
            "$mpLabel (default: 0.05; recommended: min-p 0.02-0.05)"
        }
        Write-Host "10) min_p:           $mpDisplay"

        # 11–13: mirostat (menu text already updated in previous patch)
        Write-Host ("11) mirostat mode:  {0} (default: 0, 0 = disabled, 1 = Mirostat, 2 = Mirostat 2.0)" -f [int]$State.MirostatMode)
        Write-Host ("12) mirostat-lr: {0:0.##} (default fixed 0.02, recommended: 0.05-0.15)" -f [double]$State.MirostatLRFixed)
        Write-Host ("13) mirostat-ent: {0:0.#}  (default fixed 5.0, recommended: 4.0-7.0)" -f [double]$State.MirostatEntFixed)

        # 14) smoothing
        $sf = [double]$State.SmoothingFactor
        $sfLabel = ('{0:0.###}' -f $sf)
        $sfDisplay = if ($sf -le 0.0) {
            "$sfLabel (default: 0.0; disabled; recommended 0.2-0.8; NOTE: may not work on all llama-cli versions)"
        } else {
            "$sfLabel (default: 0.0; recommended 0.2-0.8; NOTE: may not work on all llama-cli versions)"
        }
        Write-Host "14) smoothing_factor: $sfDisplay"

        # UPDATED: wording for repeat_penalty
        Write-Host "15) repeat_penalty: $(( '{0:0.###}' -f [double]$State.RepeatPenalty )) (default 1.0 - disabled; recommended 1.05-1.15)"

        $rlnVal = if ($State.RepeatLastN -eq 64) { "64 (default)" } else { "$($State.RepeatLastN)" }
        Write-Host "16) repeat_last_n:  $rlnVal (0 = disabled, -1 = full context)"
        Write-Host ("17) seed:           {0}" -f ($(if ($State.Seed -lt 0) { "$($State.Seed) (random)" } else { "$($State.Seed)" })))

        $nglDisp = if ($State.NGpuLayers -eq -1) { "-1 (auto: max VRAM)" } else { "$($State.NGpuLayers)" }
        Write-Host "18) n_gpu_layers:   $nglDisp (tip: -1 = auto; if CUDA OOM, lower this to offload to system RAM)"
        Write-Host ("19) no_warmup:      {0}" -f (Format-FlagStatus $State.NoWarmup '--no-warmup'))
        Write-Host ("20) ignore_eos:     {0}  (If added, prevents early stop; may ramble)" -f (Format-FlagStatus $State.IgnoreEOS '--ignore-eos'))
        Write-Host ("21) single_turn:    {0}" -f (Format-FlagStatus $State.SingleTurn '--single-turn'))
        Write-Host ("22) no_cnv:         {0}" -f (Format-FlagStatus $State.NoCnv '-no-cnv'))
        Write-Host ("23) simple_io:      {0}" -f (Format-FlagStatus $State.SimpleIO '--simple-io'))

        Write-Host "24) runs:           $($State.Runs) (how many independent stories to generate this session)"
        Write-Host "25) Preview command"
        Write-Host "26) Run now"
        Write-Host "27) Save config now"
        Write-Host "28) Reload config"

        if ($State.SaveOutput) {
            $mode = $State.SaveOutputMode
            if ($mode -eq 'append') {
                $annot = if ($State.Runs -gt 1) { ' (applies to multi-run only)' } else { ' (no effect with runs=1)' }
                $saveInfo = "On (append$annot) -> $($State.OutputDir)"
            } else {
                $saveInfo = "On ($mode) -> $($State.OutputDir)"
            }
        } else { $saveInfo = "Off" }
        Write-Host "29) Save mode:      $saveInfo"
        Write-Host "30) Quiet output:   " + ($(if ($State.QuietOutput) { "On (no prompt/logs)" } else { "Off" }))
        Write-Host "31) Extra filter:   " + ($(if ($State.ExtraFilter) { "On (hides banner/model info)" } else { "Off" }))
        $combInfo = switch ($State.CombinedMode) {
            'File'      { "File -> $(BaseName $State.CombinedPath) (this overrides system and user prompt)" }
            'Ephemeral' { "Ephemeral (this overrides system and user prompt)" }
            default     { "Off" }
        }
        Write-Host "32) Combine prompts: $combInfo"
        
        # MOVE: Save logg below Combine prompts as 33
        $loggInfo = if ($State.SaveLogg) {
            $p = if ($State.LoggPath) { $State.LoggPath } elseif ($State.OutputDir) { (Join-Path $State.OutputDir 'logg.txt') } else { 'logg.txt' }
            $size = if (Test-Path -LiteralPath $p) { 
                $file = Get-Item -LiteralPath $p
                $bytes = $file.Length
                if ($bytes -gt 1MB) { "{0:0.0}MB" -f ($bytes / 1MB) }
                elseif ($bytes -gt 1KB) { "{0:0.0}KB" -f ($bytes / 1KB) }
                else { "$bytes B" }
            } else { "0 B" }
            "On -> $p ($size)"
        } else { "Off" }
        Write-Host ("33) Save logg:      {0}" -f $loggInfo)
        Write-Host "34) Exit"
        Write-Host "Config file: $ConfigPath"
        Write-Host "==============================" -ForegroundColor Cyan

        # PRINT SAMPLING SUMMARY ONCE (ONLY AT BOTTOM)
        Write-Host ($SamplingSummary) -ForegroundColor DarkCyan

        $choice = Read-Host "Select option"
        switch ($choice) {
            "0" { 
                # Submenu for program and folder
                $exitSubmenu = $false
                while (-not $exitSubmenu) {
                    Write-Host ""
                    Write-Host "--- Program & Folder Settings ---" -ForegroundColor Cyan
                    Write-Host "  1) Program Location: $($State.LlamaExePath)"
                    Write-Host "  2) Model Folder:     $($State.ModelFolder)"
                    Write-Host "  3) Back to main menu"
                    $subChoice = Read-Host "Select option [1-3]"
                    
                    switch ($subChoice) {
                        "1" {
                            $sel = Select-LlamaExe
                            if ($sel) {
                                $State.LlamaExePath = $sel
                                $script:CurrentLlamaExe = $sel
                                Write-Host "llama-cli.exe path updated to: $sel" -ForegroundColor Green
                            }
                        }
                        "2" {
                            Write-Host "Enter path to model folder (or press Enter to cancel):" -ForegroundColor Cyan
                            $folderPath = Read-Host "Model folder path"
                            if ($folderPath -and (Test-Path $folderPath -PathType Container)) {
                                $State.ModelFolder = $folderPath
                                Write-Host "Model folder updated to: $folderPath" -ForegroundColor Green
                            } elseif ($folderPath) {
                                Write-Host "Path does not exist or is not a folder." -ForegroundColor Yellow
                            }
                        }
                        "3" { 
                            $exitSubmenu = $true
                            Write-Host "Returning to main menu..." -ForegroundColor Yellow
                        }
                        default { Write-Host "Invalid selection. Please enter 1, 2, or 3." -ForegroundColor Yellow }
                    }
                }
                continue
            }
            "1" {
                $sel = Select-Model -ModelFolder $State.ModelFolder
                if ($sel) {
                    $State.ModelPath = $sel
                    # NOTE: do not auto-select any chat template based on model name
                }
            }
            "2" { $State.SystemPath = Select-PromptFile $SystemDir "system prompt"; continue }
            "3" { $State.UserPath   = Select-PromptFile $UserDir   "user prompt"; continue }
            "4" {
                Write-Host "Select chat template source:" -ForegroundColor Cyan
                Write-Host "  1) Built-in (llama-cli)"
                Write-Host "  2) From templates folder (.txt file)"
                Write-Host "  3) Clear"
                $sel = Read-Host "Choose 1-3 [default: 1]"
                if ([string]::IsNullOrWhiteSpace($sel)) { $sel = "1" }
                switch ($sel) {
                    "1" {
                        $name = Select-ChatTemplateBuiltin -Exe $LlamaExe -Capabilities $Caps
                        if ($name) {
                            $State.TemplateName = $name
                            $State.TemplatePath = $null
                            Write-Host "Selected built-in chat template: $name" -ForegroundColor Green
                        }
                    }
                    "2" {
                        $path = Select-Template
                        if ($path) {
                            $State.TemplatePath = $path
                            $State.TemplateName = $null
                            Write-Host "Selected template file: $path" -ForegroundColor Green
                        }
                    }
                    "3" {
                        $State.TemplateName = $null
                        $State.TemplatePath = $null
                        Write-Host "Cleared chat template selection." -ForegroundColor Yellow
                    }
                    default { Write-Host "Invalid selection." -ForegroundColor Yellow }
                }
                continue
            }
            "5"  {
                $State.NPredict = Select-IntFromPresets `
                    -Title "Tokens to generate (-n)" `
                    -Current $State.NPredict `
                    -Presets @(-1, -2, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072) `
                    -ExtraInfo "Set -1 for infinite, -2 for 'until context filled', or choose a preset. Larger values take longer and may drift in quality." `
                    -Unit "tokens"
                continue
            }
            "6"  {
                $State.Ctx = Select-IntFromPresets `
                    -Title "Context tokens (-c)" `
                    -Current $State.Ctx `
                    -Presets @(4096, 8192, 16384, 32768, 65536, 131072) `
                    -ExtraInfo "Context window size. Common presets: 4k, 8k, 16k, 32k, 64k, 128k. Choose Custom to set an exact value supported by your model." `
                    -Unit "tokens"
                continue
            }
            "7"  {
                $SamplingConfig.Value = Set-TemperatureSettingsInteractive -Config $SamplingConfig.Value
                Save-SamplingConfig -Path $SamplingConfigPath -Config $SamplingConfig.Value
                Sync-SamplingMenuValues
                $SamplingSummary = Format-SamplingSummary -Config $SamplingConfig.Value
                Write-Host "Temperature settings updated." -ForegroundColor Green
                continue
            }
            "8"  {
                $SamplingConfig.Value = Set-TopPSettingsInteractive -Config $SamplingConfig.Value
                Save-SamplingConfig -Path $SamplingConfigPath -Config $SamplingConfig.Value
                Sync-SamplingMenuValues
                $SamplingSummary = Format-SamplingSummary -Config $SamplingConfig.Value
                Write-Host "top_p settings updated." -ForegroundColor Green
                continue
            }
            "9"  {
                $SamplingConfig.Value = Set-TopKSettingsInteractive -Config $SamplingConfig.Value
                Save-SamplingConfig -Path $SamplingConfigPath -Config $SamplingConfig.Value
                Sync-SamplingMenuValues
                $SamplingSummary = Format-SamplingSummary -Config $SamplingConfig.Value
                Write-Host "top_k settings updated." -ForegroundColor Green
                continue
            }
            "10" {
                $val = Read-Number 'min_p (--min-p): default 0.05 (0.0 = disabled). Recommended: min-p 0.02-0.05' $State.MinP
                if ($null -ne $val) {
                    if ($val -lt 0.0) { $val = 0.0 }
                    if ($val -gt 1.0) { $val = 1.0 }
                    $State.MinP = [double]$val
                }
                continue
            }
            "11" {
                $val = Read-Int 'Mirostat mode (--mirostat): 0=disabled, 1=Mirostat, 2=Mirostat 2.0' $State.MirostatMode 0 2
                if ($null -ne $val) { $State.MirostatMode = [int]$val }
                continue
            }
            "12" {
                # Ask sequentially: fixed -> min -> max (mirostat-lr)
                $fixed = Read-Number 'Fixed mirostat-lr (default 0.02; recommended 0.05-0.15)' $State.MirostatLRFixed
                if ($null -ne $fixed) {
                    if ($fixed -lt 0.0) { $fixed = 0.0 }
                    if ($fixed -gt 1.0) { $fixed = 1.0 }
                    $State.MirostatLRFixed = [double]$fixed
                }

                $min = Read-Number 'mirostat-lr MIN (recommended 0.05)' $State.MirostatLRMin
                if ($null -ne $min) {
                    if ($min -lt 0.0) { $min = 0.0 }
                    if ($min -gt 1.0) { $min = 1.0 }
                    $State.MirostatLRMin = [double]$min
                }

                $max = Read-Number 'mirostat-lr MAX (recommended 0.15)' $State.MirostatLRMax
                if ($null -ne $max) {
                    if ($max -lt 0.0) { $max = 0.0 }
                    if ($max -gt 1.0) { $max = 1.0 }
                    $State.MirostatLRMax = [double]$max
                }

                # Ensure min <= max
                if ($State.MirostatLRMin -gt $State.MirostatLRMax) {
                    $tmp = $State.MirostatLRMin
                    $State.MirostatLRMin = $State.MirostatLRMax
                    $State.MirostatLRMax = $tmp
                }

                # Sync to sampling-config and refresh summary
                if (-not ($SamplingConfig.Value.PSObject.Properties.Name -contains 'mirostat_lr')) {
                    $SamplingConfig.Value | Add-Member -NotePropertyName 'mirostat_lr' -NotePropertyValue ([pscustomobject]@{}) -Force
                }
                $SamplingConfig.Value.mirostat_lr.fixed = [double]$State.MirostatLRFixed
                $SamplingConfig.Value.mirostat_lr.min   = [double]$State.MirostatLRMin
                $SamplingConfig.Value.mirostat_lr.max   = [double]$State.MirostatLRMax
                Save-SamplingConfig -Path $SamplingConfigPath -Config $SamplingConfig.Value

                # Rebuild sampling summary to reflect changes
                $SamplingSummary = (
                    "7. Sampling settings`n" +
                    ("   temperature: {0} (fixed), {1} - {2} (random)" -f ('{0:0.###}' -f [double]$SamplingConfig.Value.temperature.fixed), ('{0:0.###}' -f [double]$SamplingConfig.Value.temperature.min), ('{0:0.###}' -f [double]$SamplingConfig.Value.temperature.max)) + "`n" +
                    ("   top_p:       {0} (fixed), {1} - {2} (random)" -f ('{0:0.###}' -f [double]$SamplingConfig.Value.top_p.fixed), ('{0:0.###}' -f [double]$SamplingConfig.Value.top_p.min), ('{0:0.###}' -f [double]$SamplingConfig.Value.top_p.max)) + "`n" +
                    ("   top_k:       {0} (fixed), {1} - {2} (random)" -f [int]$SamplingConfig.Value.top_k.fixed, [int]$SamplingConfig.Value.top_k.min, [int]$SamplingConfig.Value.top_k.max) + "`n" +
                    ("   mirostat-lr: {0:0.##} (fixed), {1:0.##} - {2:0.##} (random)" -f [double]$State.MirostatLRFixed, [double]$State.MirostatLRMin, [double]$State.MirostatLRMax) + "`n" +
                    ("   mirostat-ent:{0:0.#} (fixed), {1:0.#} - {2:0.#} (random)"   -f [double]$State.MirostatEntFixed, [double]$State.MirostatEntMin, [double]$State.MirostatEntMax)
                )
                continue
            }

            "13" {
                # Ask sequentially: fixed -> min -> max (mirostat-ent)
                $fixed = Read-Number 'Fixed mirostat-ent (default 5.0; recommended 4.0-7.0)' $State.MirostatEntFixed
                if ($null -ne $fixed) {
                    if ($fixed -lt 0.0)  { $fixed = 0.0 }
                    if ($fixed -gt 20.0) { $fixed = 20.0 }
                    $State.MirostatEntFixed = [double]$fixed
                }

                $min = Read-Number 'mirostat-ent MIN (recommended 4.0)' $State.MirostatEntMin
                if ($null -ne $min) {
                    if ($min -lt 0.0)  { $min = 0.0 }
                    if ($min -gt 20.0) { $min = 20.0 }
                    $State.MirostatEntMin = [double]$min
                }

                $max = Read-Number 'mirostat-ent MAX (recommended 7.0)' $State.MirostatEntMax
                if ($null -ne $max) {
                    if ($max -lt 0.0)  { $max = 0.0 }
                    if ($max -gt 20.0) { $max = 20.0 }
                    $State.MirostatEntMax = [double]$max
                }

                # Ensure min <= max
                if ($State.MirostatEntMin -gt $State.MirostatEntMax) {
                    $tmp = $State.MirostatEntMin
                    $State.MirostatEntMin = $State.MirostatEntMax
                    $State.MirostatEntMax = $tmp
                }

                # Sync to sampling-config and refresh summary
                if (-not ($SamplingConfig.Value.PSObject.Properties.Name -contains 'mirostat_ent')) {
                    $SamplingConfig.Value | Add-Member -NotePropertyName 'mirostat_ent' -NotePropertyValue ([pscustomobject]@{}) -Force
                }
                $SamplingConfig.Value.mirostat_ent.fixed = [double]$State.MirostatEntFixed
                $SamplingConfig.Value.mirostat_ent.min   = [double]$State.MirostatEntMin
                $SamplingConfig.Value.mirostat_ent.max   = [double]$State.MirostatEntMax
                Save-SamplingConfig -Path $SamplingConfigPath -Config $SamplingConfig.Value

                # Rebuild sampling summary to reflect changes
                $SamplingSummary = (
                    "7. Sampling settings`n" +
                    ("   temperature: {0} (fixed), {1} - {2} (random)" -f ('{0:0.###}' -f [double]$SamplingConfig.Value.temperature.fixed), ('{0:0.###}' -f [double]$SamplingConfig.Value.temperature.min), ('{0:0.###}' -f [double]$SamplingConfig.Value.temperature.max)) + "`n" +
                    ("   top_p:       {0} (fixed), {1} - {2} (random)" -f ('{0:0.###}' -f [double]$SamplingConfig.Value.top_p.fixed), ('{0:0.###}' -f [double]$SamplingConfig.Value.top_p.min), ('{0:0.###}' -f [double]$SamplingConfig.Value.top_p.max)) + "`n" +
                    ("   top_k:       {0} (fixed), {1} - {2} (random)" -f [int]$SamplingConfig.Value.top_k.fixed, [int]$SamplingConfig.Value.top_k.min, [int]$SamplingConfig.Value.top_k.max) + "`n" +
                    ("   mirostat-lr: {0:0.##} (fixed), {1:0.##} - {2:0.##} (random)" -f [double]$State.MirostatLRFixed, [double]$State.MirostatLRMin, [double]$State.MirostatLRMax) + "`n" +
                    ("   mirostat-ent:{0:0.#} (fixed), {1:0.#} - {2:0.#} (random)"   -f [double]$State.MirostatEntFixed, [double]$State.MirostatEntMin, [double]$State.MirostatEntMax)
                )
                continue
            }

            "14" { # smoothing_factor
                $val = Read-Number 'Smoothing factor (--smoothing-factor), default 0.0 (disabled). Recommended 0.2-0.8.' $State.SmoothingFactor
                if ($null -ne $val) {
                    if ($val -lt 0.0) { $val = 0.0 }
                    if ($val -gt 1.0) { $val = 1.0 }
                    $State.SmoothingFactor = [double]$val
                    if ($State.SmoothingFactor -gt 0.0 -and -not $Caps.hasSmoothingFactor) {
                        Write-Host "Heads up: your llama-cli help does not list --smoothing-factor; runs will skip this flag." -ForegroundColor Yellow
                    }
                }
                continue
            }
            "15" { # repeat_penalty
                $val = Read-Number 'Repeat penalty (--repeat-penalty), default 1.0 (disabled). Recommended 1.05-1.15' $State.RepeatPenalty
                if ($null -ne $val) {
                    if ($val -lt 0.0) { $val = 0.0 }
                    $State.RepeatPenalty = [double]$val
                }
                continue
            }
            "16" { $State.RepeatLastN   = Read-Int 'Repeat last N tokens (--repeat-last-n) [0 = disabled, -1 = full context]' $State.RepeatLastN -1; continue }
            "17" { $State.Seed          = Read-Int 'Seed (-s), -1 for random' $State.Seed; continue }
            "18" { $State.NGpuLayers    = Read-Int 'GPU layers (--n-gpu-layers), -1 = auto (max VRAM). Reduce if CUDA OOM to offload to system RAM.' $State.NGpuLayers -1; continue }
            "19" { $State.NoWarmup      = Read-YesNo 'Enable --no-warmup?' $false; continue }
            "20" { $State.IgnoreEOS     = Read-YesNo 'Enable --ignore-eos?' $false; continue }
            "21" { $State.SingleTurn    = Read-YesNo 'Enable --single-turn (one exchange then exit)?' $false; continue }
            "22" { $State.NoCnv         = Read-YesNo 'Disable conversation mode (-no-cnv)?' $false; continue }
            "23" { $State.SimpleIO      = Read-YesNo 'Enable --simple-io (if supported)?' $false; continue }
            "24" { $State.Runs          = Read-Int 'How many times to run' $State.Runs 1; try { $State.Runs = [int]$State.Runs } catch { $State.Runs = 1 }; continue }
            "25" {
                # FIX: make preview honor Ephemeral combined mode like "Run now"
                $previewCombined = $null
                if ($State.CombinedMode -eq 'Ephemeral' -and $CombinedDir) {
                    $previewCombined = Prepare-CombinedForSession -State $State -CombinedDir $CombinedDir
                }
                Preview-RunCommand -State $State -LlamaExe $script:CurrentLlamaExe -Caps $Caps -SamplingConfig $SamplingConfig.Value -CombinedOverridePath $previewCombined
                continue
            }

            "26" {
                $usingCombined = ($State.CombinedMode -ne 'Off')
                $isTwoPrompts  = ($State.SystemPath -and $State.UserPath)
                if (-not $usingCombined -and -not $isTwoPrompts -and -not $State.UserPath -and -not $State.Interactive -and -not $State.QuietOutput) {
                    $enable = Read-YesNo 'No user prompt selected and interactive mode is off. Enable interactive mode?' $true
                    if ($enable) { $State.Interactive = $true }
                }
                if (-not $State.QuietOutput) { Print-Summary -state $State -caps $Caps -LlamaExe $script:CurrentLlamaExe }
                Invoke-RunWithSampling -State $State -LlamaExe $script:CurrentLlamaExe -SamplingConfig $SamplingConfig.Value -SamplingConfigPath $SamplingConfigPath -Caps $Caps -CombinedDir $CombinedDir
                continue
            }
            "27" { Sync-SamplingMenuValues; Save-Config $State; Write-Host "Saved to $ConfigPath" -ForegroundColor Green; continue }
            "28" { if (Load-Config ([ref]$State)) { Write-Host "Reloaded from $ConfigPath" -ForegroundColor Green } else { Write-Host "No config to reload." -ForegroundColor Yellow }; continue }
            "29" {
                Write-Host "Select save mode:" -ForegroundColor Cyan
                Write-Host "  1) Separate files (each run saved individually)"
                Write-Host "  2) Append to single file (one file for this multi-run)"
                Write-Host "  3) No save"
                $modeSel = Read-Host "Choose 1-3 [default: 1]"
                if ([string]::IsNullOrWhiteSpace($modeSel)) { $modeSel = "1" }
                switch ($modeSel) {
                    "1" { $State.SaveOutputMode = 'separate'; $State.SaveOutput = $true }
                    "2" { $State.SaveOutputMode = 'append';   $State.SaveOutput = $true }
                    "3" { $State.SaveOutputMode = 'none';     $State.SaveOutput = $false }
                    default { Write-Host "Invalid selection." -ForegroundColor Yellow }
                }
                if ($State.SaveOutput -and [string]::IsNullOrWhiteSpace($State.OutputDir)) {
                    $State.OutputDir = Read-String 'Output folder path' $State.OutputDir
                }
                if ($State.SaveOutput) { Ensure-Dir $State.OutputDir }
                continue
            }
            "30" { $State.QuietOutput = -not $State.QuietOutput; Write-Host "Quiet output: " + ($(if ($State.QuietOutput) { "On" } else { "Off" })) -ForegroundColor Cyan; continue }
            "31" { $State.ExtraFilter = -not $State.ExtraFilter; Write-Host "Extra filter: " + ($(if ($State.ExtraFilter) { "On" } else { "Off" })) -ForegroundColor Cyan; continue }
            "32" { Show-CombinePromptsMenu -State $State -CombinedDir $CombinedDir; continue }
            "33" {
                $enable = Read-YesNo 'Enable "save logg" (append to logg.txt)?' $false
                $State.SaveLogg = $enable
                if ($enable) {
                    $defaultLogg = if (-not [string]::IsNullOrWhiteSpace($State.OutputDir)) { Join-Path $State.OutputDir 'logg.txt' } else { 'logg.txt' }
                    $current = if ($State.LoggPath) { $State.LoggPath } else { $defaultLogg }
                    $State.LoggPath = Read-String 'Logg file path' $current
                }
                continue
            }
            "34" { Save-Config $State; Write-Host "Saved to $ConfigPath. Exiting." -ForegroundColor Yellow; return }

            default { Write-Host "Invalid option. Enter a number 0-34." -ForegroundColor Yellow }
        }
    }
}