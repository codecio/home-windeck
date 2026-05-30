<#
.SYNOPSIS
    PowerTweaks module — configure machine for a console-like always-on experience.

.DESCRIPTION
    Enable-PowerTweaks  : Creates/activates a High-Performance based power scheme,
                         disables hibernation, and sets display/sleep timeouts to never.
    Disable-PowerTweaks : Restores the previously active power scheme (if available)
                         and re-enables hibernation.

    This module writes a small snapshot file to backups/powertweaks_<timestamp>.txt
    recording the previous active scheme GUID so Disable-PowerTweaks can restore it.
#>

function Enable-PowerTweaks {
    <#
    .SYNOPSIS
        Apply console-style power settings: never sleep, never turn off display.
    #>
    [CmdletBinding()]
    param()

    # Record current active scheme
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $script:RepoRoot 'backups'
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

    $current = (powercfg /GetActiveScheme) 2>&1
    # Output sample: "Power Scheme GUID: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  (Balanced)"
    $match = $current -match '([0-9a-fA-F\-]{36})'
    $currentGuid = if ($match) { $Matches[1] } else { $null }
    if ($currentGuid) {
        $metaFile = Join-Path $backupDir "powertweaks_${timestamp}.txt"
        "PreviousActiveScheme=$currentGuid" | Out-File -FilePath $metaFile -Encoding ASCII
        Write-Log -Level INFO -Message "Saved previous power scheme GUID $currentGuid → $metaFile"
    } else {
        Write-Log -Level WARN -Message "Could not determine current active power scheme."
    }

    # Find a High Performance scheme if present
    $list = (powercfg /L) 2>&1
    $hpMatch = ($list | Select-String -Pattern 'High' -SimpleMatch | Select-Object -First 1)
    if ($hpMatch) {
        if ($hpMatch -match '([0-9a-fA-F\-]{36})') { $hpGuid = $Matches[1] }
    }

    # If no HP scheme, duplicate Balanced and rename
    if (-not $hpGuid) {
        Write-Log -Level INFO -Message 'High Performance scheme not found — duplicating Balanced scheme.'
        # Balanced GUID is commonly 381b4222-f694-41f0-9685-ff5bb260df2e
        $balanced = ($list | Select-String -Pattern 'Balanced' -SimpleMatch | Select-Object -First 1)
        if ($balanced -and $balanced -match '([0-9a-fA-F\-]{36})') { $balGuid = $Matches[1] } else { $balGuid = '381b4222-f694-41f0-9685-ff5bb260df2e' }
        $dup = (powercfg -duplicatescheme $balGuid) 2>&1
        if ($dup -match '([0-9a-fA-F\-]{36})') { $hpGuid = $Matches[1] }
        if ($hpGuid) { powercfg -changename $hpGuid "SteamConsole-HighPerformance" | Out-Null }
    }

    if (-not $hpGuid) {
        Write-Log -Level ERROR -Message 'Failed to determine or create a High Performance power scheme.'
        return
    }

    # Activate scheme
    powercfg -setactive $hpGuid | Out-Null
    Write-Log -Level INFO -Message "Activated power scheme $hpGuid"

    # Disable hibernation
    try {
        powercfg -h off | Out-Null
        Write-Log -Level INFO -Message 'Disabled hibernation.'
    } catch {
        Write-Log -Level WARN -Message "Unable to disable hibernation: $_"
    }

    # Set display and sleep to never (0 = never)
    try {
        powercfg /change monitor-timeout-ac 0 | Out-Null
        powercfg /change monitor-timeout-dc 0 | Out-Null
        powercfg /change standby-timeout-ac 0 | Out-Null
        powercfg /change standby-timeout-dc 0 | Out-Null
        Write-Log -Level INFO -Message 'Set display and sleep timeouts to never (AC/DC).'
    } catch {
        Write-Log -Level WARN -Message "Failed to set timeouts: $_"
    }
}

function Disable-PowerTweaks {
    <#
    .SYNOPSIS
        Restore the previously active power scheme and re-enable hibernation.
    #>
    [CmdletBinding()]
    param()

    $backupDir = Join-Path $script:RepoRoot 'backups'
    $meta = Get-ChildItem -Path $backupDir -Filter 'powertweaks_*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $meta) {
        Write-Log -Level WARN -Message 'No powertweaks backup found — cannot restore previous scheme automatically.'
    } else {
        $content = Get-Content -Path $meta.FullName -ErrorAction SilentlyContinue
        foreach ($line in $content) {
            if ($line -match '^PreviousActiveScheme=(?<g>[0-9a-fA-F\-]{36})') {
                $prev = $Matches['g']
                try {
                    powercfg -setactive $prev | Out-Null
                    Write-Log -Level INFO -Message "Restored previous power scheme $prev from $($meta.Name)."
                } catch {
                    Write-Log -Level WARN -Message ("Failed to restore previous scheme $prev: $($_)")
                }
            }
        }
    }

    try {
        powercfg -h on | Out-Null
        Write-Log -Level INFO -Message 'Re-enabled hibernation.'
    } catch {
        Write-Log -Level WARN -Message "Unable to re-enable hibernation: $_"
    }
}
