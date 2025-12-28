# sampling.ps1
# Encapsulates sampling config, prompts, and per-run value generation.

# Script-scope RNG so we can support optional seeding
$script:SamplingRandom = $null

function Initialize-Random {
    param(
        [Nullable[int]] $Seed
    )
    if ($Seed -ne $null) {
        $script:SamplingRandom = [System.Random]::new($Seed)
    } else {
        $script:SamplingRandom = [System.Random]::new()
    }
}

function Get-RandomFloat {
    param(
        [double] $Min,
        [double] $Max
    )
    if ($Max -lt $Min) { $t = $Min; $Min = $Max; $Max = $t }
    # NextDouble is [0,1); scale to [Min, Max]
    return $script:SamplingRandom.NextDouble() * ($Max - $Min) + $Min
}

function Get-RandomIntInclusive {
    param(
        [int] $Min,
        [int] $Max
    )
    if ($Max -lt $Min) { $t = $Min; $Min = $Max; $Max = $t }
    # Next upper bound is exclusive; add 1 to make Max inclusive
    return $script:SamplingRandom.Next($Min, $Max + 1)
}

function Save-SamplingConfig {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Config
    )
    $json = $Config | ConvertTo-Json -Depth 8
    $json | Set-Content -Path $Path -Encoding utf8
}

function Get-SamplingConfig {
    param(
        [Parameter(Mandatory)] [string] $Path
    )
    $cfg = $null
    if (Test-Path -LiteralPath $Path) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            $cfg = $raw | ConvertFrom-Json
        } catch {
            Write-Warning "sampling-config.json could not be read; recreating defaults. Error: $($_.Exception.Message)"
            $cfg = $null
        }
    }

    if (-not $cfg) {
        # File missing or unreadable: create with mirostat defaults
        $cfg = [pscustomobject]@{
            version      = 1
            seed         = $null
            temperature  = [pscustomobject]@{ fixed = 1.0;  min = 0.9;  max = 1.8 }
            top_p        = [pscustomobject]@{ fixed = 0.95; min = 0.8;  max = 0.98 }
            top_k        = [pscustomobject]@{ fixed = 50;   min = 40;   max = 200 }
            mirostat_lr  = [pscustomobject]@{ fixed = 0.1;  min = 0.05; max = 0.15 }
            mirostat_ent = [pscustomobject]@{ fixed = 5.0;  min = 4.0;  max = 7.0 }
        }
        Save-SamplingConfig -Path $Path -Config $cfg
    } else {
        # File exists: if blocks missing, add them with sensible defaults
        if (-not ($cfg.PSObject.Properties.Name -contains 'mirostat_lr')) {
            $cfg | Add-Member -NotePropertyName 'mirostat_lr' -NotePropertyValue ([pscustomobject]@{ fixed=0.1; min=0.05; max=0.15 })
        }
        if (-not ($cfg.PSObject.Properties.Name -contains 'mirostat_ent')) {
            $cfg | Add-Member -NotePropertyName 'mirostat_ent' -NotePropertyValue ([pscustomobject]@{ fixed=5.0; min=4.0; max=7.0 })
        }
    }

    # Normalize (fills any missing fields), then persist back so file gains mirostat blocks
    $cfg = Normalize-SamplingConfig -Config $cfg
    Save-SamplingConfig -Path $Path -Config $cfg
    return $cfg
}

function Normalize-SamplingConfig {
    param(
        [Parameter(Mandatory)] $Config
    )

    # Ensure nested objects exist and properties are present
    foreach ($k in 'temperature','top_p','top_k','mirostat_lr','mirostat_ent') {
        if (-not ($Config.PSObject.Properties.Name -contains $k)) {
            $Config | Add-Member -NotePropertyName $k -NotePropertyValue ([pscustomobject]@{})
        }
        $obj = $Config.$k

        if ($k -eq 'mirostat_lr') {
            if (-not ($obj.PSObject.Properties.Name -contains 'fixed') -or $null -eq $obj.fixed) { $obj.fixed = 0.1 }
            if (-not ($obj.PSObject.Properties.Name -contains 'min')   -or $null -eq $obj.min)   { $obj.min   = 0.05 }
            if (-not ($obj.PSObject.Properties.Name -contains 'max')   -or $null -eq $obj.max)   { $obj.max   = 0.15 }
            continue
        }
        if ($k -eq 'mirostat_ent') {
            if (-not ($obj.PSObject.Properties.Name -contains 'fixed') -or $null -eq $obj.fixed) { $obj.fixed = 5.0 }
            if (-not ($obj.PSObject.Properties.Name -contains 'min')   -or $null -eq $obj.min)   { $obj.min   = 4.0 }
            if (-not ($obj.PSObject.Properties.Name -contains 'max')   -or $null -eq $obj.max)   { $obj.max   = 7.0 }
            continue
        }

        foreach ($p in 'fixed','min','max') {
            if (-not ($obj.PSObject.Properties.Name -contains $p)) {
                $obj | Add-Member -NotePropertyName $p -NotePropertyValue 0
            } elseif ($null -eq $obj.$p) {
                $obj.$p = 0
            }
        }
    }

    # Clamp values and fix ordering
    $Config.temperature.fixed = [double]([math]::Max(0.0, [math]::Min(2.0, [double]$Config.temperature.fixed)))
    $Config.temperature.min   = [double]([math]::Max(0.0, [math]::Min(2.0, [double]$Config.temperature.min)))
    $Config.temperature.max   = [double]([math]::Max(0.0, [math]::Min(2.0, [double]$Config.temperature.max)))
    if ($Config.temperature.min -gt $Config.temperature.max) {
        $tmp = $Config.temperature.min; $Config.temperature.min = $Config.temperature.max; $Config.temperature.max = $tmp
    }

    $Config.top_p.fixed = [double]([math]::Max(0.0, [math]::Min(1.0, [double]$Config.top_p.fixed)))
    $Config.top_p.min   = [double]([math]::Max(0.0, [math]::Min(1.0, [double]$Config.top_p.min)))
    $Config.top_p.max   = [double]([math]::Max(0.0, [math]::Min(1.0, [double]$Config.top_p.max)))
    if ($Config.top_p.min -gt $Config.top_p.max) {
        $tmp = $Config.top_p.min; $Config.top_p.min = $Config.top_p.max; $Config.top_p.max = $tmp
    }

    $Config.top_k.fixed = [int][math]::Max(0, [int]$Config.top_k.fixed)
    $Config.top_k.min   = [int][math]::Max(0, [int]$Config.top_k.min)
    $Config.top_k.max   = [int][math]::Max(0, [int]$Config.top_k.max)
    if ($Config.top_k.min -gt $Config.top_k.max) {
        $tmp = $Config.top_k.min; $Config.top_k.min = $Config.top_k.max; $Config.top_k.max = $tmp
    }

    # Clamp mirostat ranges and ordering
    $Config.mirostat_lr.fixed  = [double]([math]::Max(0.0, [math]::Min(1.0,  [double]$Config.mirostat_lr.fixed)))
    $Config.mirostat_lr.min    = [double]([math]::Max(0.0, [math]::Min(1.0,  [double]$Config.mirostat_lr.min)))
    $Config.mirostat_lr.max    = [double]([math]::Max(0.0, [math]::Min(1.0,  [double]$Config.mirostat_lr.max)))
    if ($Config.mirostat_lr.min -gt $Config.mirostat_lr.max) {
        $tmp = $Config.mirostat_lr.min; $Config.mirostat_lr.min = $Config.mirostat_lr.max; $Config.mirostat_lr.max = $tmp
    }

    $Config.mirostat_ent.fixed = [double]([math]::Max(0.0, [math]::Min(20.0, [double]$Config.mirostat_ent.fixed)))
    $Config.mirostat_ent.min   = [double]([math]::Max(0.0, [math]::Min(20.0, [double]$Config.mirostat_ent.min)))
    $Config.mirostat_ent.max   = [double]([math]::Max(0.0, [math]::Min(20.0, [double]$Config.mirostat_ent.max)))
    if ($Config.mirostat_ent.min -gt $Config.mirostat_ent.max) {
        $tmp = $Config.mirostat_ent.min; $Config.mirostat_ent.min = $Config.mirostat_ent.max; $Config.mirostat_ent.max = $tmp
    }

    return $Config
}

function Format-SamplingSummary {
    param(
        [Parameter(Mandatory)] $Config
    )

    function Fmt([double]$d) { '{0:0.###}' -f $d }

    @(
        "7. Sampling settings"
        ("   temperature: {0} (fixed), {1} - {2} (random)" -f (Fmt $Config.temperature.fixed), (Fmt $Config.temperature.min), (Fmt $Config.temperature.max))
        ("   top_p:       {0} (fixed), {1} - {2} (random)" -f (Fmt $Config.top_p.fixed),       (Fmt $Config.top_p.min),       (Fmt $Config.top_p.max))
        ("   top_k:       {0} (fixed), {1} - {2} (random)" -f $Config.top_k.fixed,             $Config.top_k.min,             $Config.top_k.max)
        ("   mirostat-lr: {0:0.##} (fixed), {1:0.##} - {2:0.##} (random)" -f [double]$State.MirostatLRFixed,  [double]$State.MirostatLRMin,  [double]$State.MirostatLRMax)
        ("   mirostat-ent:{0:0.#} (fixed), {1:0.#} - {2:0.#} (random)"   -f [double]$State.MirostatEntFixed, [double]$State.MirostatEntMin, [double]$State.MirostatEntMax)
    ) -join [Environment]::NewLine
}

function Get-SamplingValuesForRun {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [int] $RunCount,
        [int] $RunIndex = 1
    )
    if (-not $script:SamplingRandom) { Initialize-Random -Seed $Config.seed }

    if ($RunCount -le 1) {
        # NEW: provide fixed mirostat values for single-run
        return [pscustomobject]@{
            temperature  = [double]$Config.temperature.fixed
            top_p        = [double]$Config.top_p.fixed
            top_k        = [int]   $Config.top_k.fixed
            mirostat_lr  = [double]$Config.mirostat_lr.fixed
            mirostat_ent = [double]$Config.mirostat_ent.fixed
        }
    } else {
        # NEW: randomize mirostat within range for multi-run
        return [pscustomobject]@{
            temperature  = [double](Get-RandomFloat        -Min $Config.temperature.min -Max $Config.temperature.max)
            top_p        = [double](Get-RandomFloat        -Min $Config.top_p.min       -Max $Config.top_p.max)
            top_k        = [int]   (Get-RandomIntInclusive -Min $Config.top_k.min       -Max $Config.top_k.max)
            mirostat_lr  = [double](Get-RandomFloat        -Min $Config.mirostat_lr.min  -Max $Config.mirostat_lr.max)
            mirostat_ent = [double](Get-RandomFloat        -Min $Config.mirostat_ent.min -Max $Config.mirostat_ent.max)
        }
    }
}

function Read-Number {
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] $Default,
        [switch] $AsInt
    )
    while ($true) {
        $shownDefault = if ($AsInt) {
            [string]$Default
        } else {
            '{0:0.###}' -f [double]$Default
        }

        $input = Read-Host "$Prompt [$shownDefault]"
        if ([string]::IsNullOrWhiteSpace($input)) { return $Default }

        if ($AsInt) {
            $outInt = 0
            if ([int]::TryParse($input, [ref]$outInt)) { return $outInt }
        } else {
            $outDouble = 0.0
            if ([double]::TryParse($input, [ref]$outDouble)) { return $outDouble }
        }

        $numKind = if ($AsInt) { 'whole number' } else { 'decimal' }
        Write-Warning "Invalid number. Please enter a $numKind or press Enter to keep the current value."
    }
}

function Set-TemperatureSettingsInteractive {
    param(
        [Parameter(Mandatory)] $Config
    )
    Write-Host "Configure temperature. Press Enter to keep current values." -ForegroundColor Cyan

    $Config.temperature.fixed = Read-Number -Prompt 'Fixed temperature'            -Default $Config.temperature.fixed
    $Config.temperature.min   = Read-Number -Prompt 'Random temperature min (>=0)' -Default $Config.temperature.min
    $Config.temperature.max   = Read-Number -Prompt 'Random temperature max (<=2)' -Default $Config.temperature.max

    $Config = Normalize-SamplingConfig -Config $Config
    $script:SamplingRandom = $null
    return $Config
}

function Set-TopPSettingsInteractive {
    param(
        [Parameter(Mandatory)] $Config
    )
    Write-Host "Configure top_p. Press Enter to keep current values." -ForegroundColor Cyan

    $Config.top_p.fixed = Read-Number -Prompt 'Fixed top_p'            -Default $Config.top_p.fixed
    $Config.top_p.min   = Read-Number -Prompt 'Random top_p min (>=0)' -Default $Config.top_p.min
    $Config.top_p.max   = Read-Number -Prompt 'Random top_p max (<=1)' -Default $Config.top_p.max

    $Config = Normalize-SamplingConfig -Config $Config
    $script:SamplingRandom = $null
    return $Config
}

function Set-TopKSettingsInteractive {
    param(
        [Parameter(Mandatory)] $Config
    )
    Write-Host "Configure top_k. Press Enter to keep current values." -ForegroundColor Cyan

    $Config.top_k.fixed = Read-Number -Prompt 'Fixed top_k'            -Default $Config.top_k.fixed -AsInt
    $Config.top_k.min   = Read-Number -Prompt 'Random top_k min (int)' -Default $Config.top_k.min   -AsInt
    $Config.top_k.max   = Read-Number -Prompt 'Random top_k max (int)' -Default $Config.top_k.max   -AsInt

    $Config = Normalize-SamplingConfig -Config $Config
    $script:SamplingRandom = $null
    return $Config
}
