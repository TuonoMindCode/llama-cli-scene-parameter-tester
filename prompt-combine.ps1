# Combined prompt helpers: profiles, rendering, creation, and menu

function Get-BuiltinCombineProfileNames {
    @('basic-headers','chatml','story-mode','minimal')
}

function Get-CombineProfileText {
    param([Parameter(Mandatory=$true)][string]$ProfileName)

    # Try external profile file first
    if ($CombinedProfilesDir -and (Test-Path -LiteralPath $CombinedProfilesDir)) {
        $candidate = Join-Path $CombinedProfilesDir ("{0}.txt" -f $ProfileName)
        if (Test-Path -LiteralPath $candidate) {
            return (Get-Content -LiteralPath $candidate -Raw -Encoding UTF8)
        }
    }

    switch ($ProfileName.ToLower()) {
        'basic-headers' {
@'
### System:
{{SYSTEM}}

### User:
{{USER}}
'@
        }
        'chatml' {
@'
<system>
{{SYSTEM}}
</system>

<user>
{{USER}}
</user>
'@
        }
        'story-mode' {
@'
You are a storyteller specialized in writing highly immersive, first-person scenes.

{{SYSTEM}}

---

TASK:

Write a single, continuous first-person scene based on the following instructions.

Important hard constraints:
- Output ONLY the story as one block of narrative prose.
- Do NOT include any headings (no "Scene Start", "Scene Middle", "My Revised Scene", "Final Answer", etc.).
- Do NOT explain your reasoning.
- Do NOT analyze or comment on your own writing.
- Do NOT produce multiple versions; only ONE final version of the scene.
- No bullet points, lists, options, or meta commentary of any kind.

SCENE REQUEST:

{{USER}}
'@
        }
        'minimal' {
@'
{{SYSTEM}}

{{USER}}
'@
        }
        default {
@'
### System:
{{SYSTEM}}

### User:
{{USER}}
'@
        }
    }
}

function Render-CombinedContent {
    param(
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [string]$SystemText,
        [string]$UserText
    )
    $tmpl = Get-CombineProfileText -ProfileName $ProfileName
    if (-not $tmpl) { return $null }
    $sys = $(if ($SystemText) { $SystemText } else { "" })
    $usr = $(if ($UserText)   { $UserText   } else { "" })
    
    # Replace double-brace placeholders ({{SYSTEM}}, {{USER}}, {{User}})
    $out = $tmpl.Replace("{{SYSTEM}}", $sys)
    $out = $out.Replace("{{User}}",   $usr)  # tolerate different casing
    $out = $out.Replace("{{USER}}",   $usr)
    
    # Replace single-brace placeholders (common in Vicuna/HuggingFace formats)
    $combined = "$sys`n$usr"  # System and user combined with newline
    $out = $out.Replace("{system}", $sys)
    $out = $out.Replace("{System}", $sys)
    $out = $out.Replace("{prompt}",  $combined)   # {prompt} = system + user combined (Vicuna format)
    $out = $out.Replace("{Prompt}",  $combined)
    $out = $out.Replace("{user}",    $usr)
    $out = $out.Replace("{User}",    $usr)
    
    return $out
}

function New-CombinedPromptFile {
    param(
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [Parameter(Mandatory=$true)][string]$SystemPath,
        [Parameter(Mandatory=$true)][string]$UserPath,
        [Parameter(Mandatory=$true)][string]$CombinedDir,
        [string]$FileName = $null
    )
    if (-not (Test-Path -LiteralPath $SystemPath)) { Write-Host "System file not found: $SystemPath" -ForegroundColor Yellow; return $null }
    if (-not (Test-Path -LiteralPath $UserPath))   { Write-Host "User file not found: $UserPath"   -ForegroundColor Yellow; return $null }

    if (-not (Test-Path -LiteralPath $CombinedDir)) { New-Item -ItemType Directory -Path $CombinedDir | Out-Null }

    $sysText = Get-Content -LiteralPath $SystemPath -Raw -Encoding UTF8
    $usrText = Get-Content -LiteralPath $UserPath   -Raw -Encoding UTF8
    $content = Render-CombinedContent -ProfileName $ProfileName -SystemText $sysText -UserText $usrText
    if (-not $content) { Write-Host "Failed to render combined content." -ForegroundColor Red; return $null }

    if (-not $FileName -or [string]::IsNullOrWhiteSpace($FileName)) {
        $sysName = Sanitize-Filename ([IO.Path]::GetFileNameWithoutExtension($SystemPath))
        $usrName = Sanitize-Filename ([IO.Path]::GetFileNameWithoutExtension($UserPath))
        $profName = Sanitize-Filename $ProfileName
        $stamp   = Get-Date -Format "yyyyMMdd_HHmmss"
        $FileName = "{0}__{1}__{2}__{3}.txt" -f $sysName, $usrName, $profName, $stamp
    }
    $outPath = Join-Path $CombinedDir $FileName
    Set-Content -LiteralPath $outPath -Value $content -Encoding UTF8
    return $outPath
}

function New-CombinedPromptEphemeral {
    param(
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [Parameter(Mandatory=$true)][string]$SystemPath,
        [Parameter(Mandatory=$true)][string]$UserPath,
        [Parameter(Mandatory=$true)][string]$CombinedDir,
        [string]$SessionTag = $null
    )
    if (-not (Test-Path -LiteralPath $SystemPath) -or -not (Test-Path -LiteralPath $UserPath)) { return $null }
    if (-not (Test-Path -LiteralPath $CombinedDir)) { New-Item -ItemType Directory -Path $CombinedDir | Out-Null }

    $sysText = Get-Content -LiteralPath $SystemPath -Raw -Encoding UTF8
    $usrText = Get-Content -LiteralPath $UserPath   -Raw -Encoding UTF8
    $content = Render-CombinedContent -ProfileName $ProfileName -SystemText $sysText -UserText $usrText
    if (-not $content) { return $null }

    $stamp    = Get-Date -Format "yyyyMMdd_HHmmss"
    $tagSafe  = $(if ($SessionTag) { Sanitize-Filename $SessionTag } else { Sanitize-Filename ([IO.Path]::GetFileNameWithoutExtension($SystemPath)) })
    $fileName = "{0}_{1}_combined_session.txt" -f $stamp, $tagSafe
    $outPath  = Join-Path $CombinedDir $fileName
    Set-Content -LiteralPath $outPath -Value $content -Encoding UTF8
    return $outPath
}

function Select-CombinedFile {
    param([Parameter(Mandatory=$true)][string]$CombinedDir)
    Ensure-Dir $CombinedDir
    $files = @(Get-ChildItem -LiteralPath $CombinedDir -File -Filter "*.txt" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    if (-not $files -or $files.Count -eq 0) { Write-Host "No combined .txt files found in: $CombinedDir" -ForegroundColor Yellow; return $null }
    $choice = Select-FromList "Select combined prompt (.txt) from $CombinedDir" $files $true 0
    if ($choice -gt 0) { return $files[$choice - 1] }
    return $null
}

function Select-CombineProfile {
    $names = @()

    if ($CombinedProfilesDir -and (Test-Path -LiteralPath $CombinedProfilesDir)) {
        $profileFiles = Get-ChildItem -LiteralPath $CombinedProfilesDir -File -Filter "*.txt" -ErrorAction SilentlyContinue
        foreach ($pf in $profileFiles) { $names += [IO.Path]::GetFileNameWithoutExtension($pf.Name) }
    }
    foreach ($bn in Get-BuiltinCombineProfileNames) { if (-not ($names -contains $bn)) { $names += $bn } }

    if (-not $names -or $names.Count -eq 0) {
        Write-Host "No combine profiles available." -ForegroundColor Yellow
        return $null
    }

    $choice = Select-FromList "Select combine profile" $names $false 1
    return $names[$choice]
}

function Prepare-CombinedForSession {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$CombinedDir
    )
    if ($State.CombinedMode -eq 'Ephemeral') {
        if (-not $State.SystemPath -or -not $State.UserPath) {
            Write-Host "Ephemeral combine requires both System and User prompt files selected." -ForegroundColor Yellow
            return $null
        }
        $tag = [IO.Path]::GetFileNameWithoutExtension($State.ModelPath)
        $path = New-CombinedPromptEphemeral -ProfileName $State.CombinedProfileName -SystemPath $State.SystemPath -UserPath $State.UserPath -CombinedDir $CombinedDir -SessionTag $tag
        if ($path) { Write-Host "Prepared ephemeral combined prompt: $path" -ForegroundColor DarkGreen }
        return $path
    }
    return $null
}

function Show-CombinePromptsMenu {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$CombinedDir
    )

    Write-Host "Combine prompts options:" -ForegroundColor Cyan
    Write-Host "  1) Create new combined file (persistent)"
    Write-Host "  2) Use existing combined file"
    Write-Host "  3) Clear (use separate system + user)"
    $sel = Read-Host "Choose 1-3 [default: 1]"
    if ([string]::IsNullOrWhiteSpace($sel)) { $sel = "1" }

    switch ($sel) {
        "1" {
            $profile = Select-CombineProfile
            if (-not $profile) { return }
            if (-not $State.SystemPath) { $State.SystemPath = Select-PromptFile $SystemDir "system prompt" }
            if (-not $State.UserPath)   { $State.UserPath   = Select-PromptFile $UserDir   "user prompt" }
            if (-not $State.SystemPath -or -not $State.UserPath) { Write-Host "Need both system and user prompts." -ForegroundColor Yellow; return }

            $suggest = "{0}__{1}__{2}.txt" -f ([IO.Path]::GetFileNameWithoutExtension($State.SystemPath)), ([IO.Path]::GetFileNameWithoutExtension($State.UserPath)), $profile
            $name = Read-String "Combined file name" $suggest
            $path = New-CombinedPromptFile -ProfileName $profile -SystemPath $State.SystemPath -UserPath $State.UserPath -CombinedDir $CombinedDir -FileName $name
            if ($path) {
                $State.CombinedMode        = 'File'
                $State.CombinedPath        = $path
                $State.CombinedProfileName = $profile
                Write-Host "Created combined file: $path" -ForegroundColor Green
            }
        }
        "2" {
            $path = Select-CombinedFile -CombinedDir $CombinedDir
            if ($path) {
                $State.CombinedMode = 'File'
                $State.CombinedPath = $path
                Write-Host "Using combined file: $path" -ForegroundColor Green
            }
        }
        "3" {
            $State.CombinedMode = 'Off'
            $State.CombinedPath = $null
            Write-Host "Combined mode cleared; using separate system + user prompts." -ForegroundColor Yellow
        }
        default {
            Write-Host "Invalid selection." -ForegroundColor Yellow
        }
    }
}
