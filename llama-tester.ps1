# Menu-driven runner for llama-cli.exe (ggml-org/llama.cpp)

# Force UTF‑8 for console and redirection
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8   # affects > redirection in Windows PowerShell

# Default all content-writing cmdlets to UTF‑8
$PSDefaultParameterValues['Out-File:Encoding']      = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding']   = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding']   = 'utf8'

# --------------------------
# Locations
# --------------------------
$Root          = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModelsDir     = Join-Path $Root "models"
$SystemDir     = Join-Path $Root "system_prompt"
$UserDir       = Join-Path $Root "user_prompt"
$TemplatesDir  = Join-Path $Root "templates"
$OutputDir     = Join-Path $Root "outputs"
# NEW: combined prompt dirs
$CombinedDir        = Join-Path $Root "combined_prompt"
$CombinedProfilesDir= Join-Path $Root "combined_formats"
$ConfigPath    = Join-Path $Root "config.txt"
# Note: $LlamaExe path will be determined from config or PATH, no hardcoded local path

# Ensure folders
. "$PSScriptRoot\core\llama-core.ps1"   # helpers, capabilities, config, runner
Ensure-Dir $ModelsDir
Ensure-Dir $SystemDir
Ensure-Dir $UserDir
Ensure-Dir $TemplatesDir
Ensure-Dir $OutputDir
Ensure-Dir $CombinedDir
Ensure-Dir $CombinedProfilesDir

# Load combine helpers (supports both core\ and root\ locations)
$combineScriptCore = Join-Path $PSScriptRoot 'core\prompt-combine.ps1'
$combineScriptRoot = Join-Path $PSScriptRoot 'prompt-combine.ps1'
if (Test-Path -LiteralPath $combineScriptCore) {
    . $combineScriptCore
} elseif (Test-Path -LiteralPath $combineScriptRoot) {
    . $combineScriptRoot
} else {
    Write-Host "WARNING: prompt-combine.ps1 not found under 'core\' or root. Combine prompts features will be unavailable." -ForegroundColor Yellow
}

# Load sampling helpers + config
. "$PSScriptRoot\sampling.ps1"
$SamplingConfigPath = Join-Path $PSScriptRoot 'sampling-config.json'
$SamplingConfig = Get-SamplingConfig -Path $SamplingConfigPath

# Defaults/state
$DefaultNPredict = 32768
$DefaultCtx      = 32768
$DefaultTemp     = 0.8
$DefaultTopP     = 0.95
$DefaultSeed     = -1
$DefaultRuns     = 1

$State = @{
    LlamaExePath  = $null
    ModelFolder   = $ModelsDir
    ModelPath     = $null
    SystemPath    = $null
    UserPath      = $null
    TemplatePath  = $null
    TemplateName  = $null
    NPredict      = $DefaultNPredict
    Ctx           = $DefaultCtx
    Temp          = $DefaultTemp
    TopP          = $DefaultTopP
    Seed          = $DefaultSeed
    NGpuLayers    = -1   # -1 = default/disabled (do not emit --n-gpu-layers)
    NoWarmup      = $true
    IgnoreEOS     = $false   # default Not added: allow EOS to stop generation; toggle On to ignore EOS (may ramble)
    SingleTurn    = $true
    NoCnv         = $false   # default Not added: conversation mode enabled by default
    Interactive   = $false
    Runs          = $DefaultRuns
    SaveOutput    = $true
    OutputDir     = $OutputDir
    SaveOutputMode= 'append'  # default: append (no effect when runs=1; adds sections for multi-run)
    SimpleIO      = $true
    TopK          = 40
    RepeatPenalty = 1.1
    RepeatLastN   = 64
    QuietOutput   = $false
    ExtraFilter   = $false   # filters out banner/model info; shows only response after setup text
    MinP          = 0.05  # default per CLI: 0.05 (0.0 = disabled)
    SmoothingFactor = 0.0
    MirostatMode  = 0
    MirostatLRFixed = 0.1
    MirostatLRMin = 0.05
    MirostatLRMax = 0.15
    MirostatEntFixed = 5.0
    MirostatEntMin = 4.0
    MirostatEntMax = 7.0
    # Combined prompt state
    CombinedMode        = 'Off'
    CombinedPath        = $null
    CombinedProfileName = 'basic-headers'
}

# Load or initialize config (restores saved values)
if (-not (Load-Config ([ref]$State))) {
    Save-Config $State
}

# Use configured exe path if available, otherwise search PATH
if ($State.LlamaExePath -and (Test-Path $State.LlamaExePath)) {
    $LlamaExe = $State.LlamaExePath
} else {
    $which = (Get-Command "llama-cli.exe" -ErrorAction SilentlyContinue)
    if ($which) { 
        $LlamaExe = $which.Source
        $State.LlamaExePath = $LlamaExe
    }
}

# If still not found, allow user to select via menu (will fail gracefully when running)
if ([string]::IsNullOrWhiteSpace($LlamaExe)) {
    Write-Host "WARNING: llama-cli.exe not found in config or PATH. You can select it from the menu (option 0)." -ForegroundColor Yellow
    $LlamaExe = "llama-cli.exe"  # placeholder; user will need to set it from menu
} else {
    Assert-FileExists $LlamaExe "llama-cli.exe"
}

# FIX: set capabilities before calling Start-Storyteller
$caps = Get-LlamaCliCapabilities $LlamaExe

# Start menu
. "$PSScriptRoot\core\menu.ps1"
Start-Storyteller -State $State `
                  -LlamaExe $LlamaExe `
                  -Caps $caps `
                  -ConfigPath $ConfigPath `
                  -SamplingConfig ([ref]$SamplingConfig) `
                  -SamplingConfigPath $SamplingConfigPath
