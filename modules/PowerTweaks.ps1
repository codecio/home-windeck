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

    $backupDir = Join-Path $script:RepoRoot 'backups'

    # --- Read-only discovery (safe in DryRun) ---
    $currentOutput = (powercfg /GetActiveScheme) 2>&1
    $currentGuid   = if ($currentOutput -match '([0-9a-fA-F-]{36})') { $Matches[1] } else { $null }

    $schemeList = (powercfg /L) 2>&1
    $hpGuid     = $null
    $hpLine     = $schemeList | Select-String -Pattern 'High' -SimpleMatch | Select-Object -First 1
    if ($hpLine -and ($hpLine.Line -match '([0-9a-fA-F-]{36})')) { $hpGuid = $Matches[1] }

    # --- Save current scheme for revert ---
    Invoke-Action -Description "Save current power scheme GUID ($currentGuid) to backups/" -ScriptBlock {
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
        if ($currentGuid) {
            $metaFile = Join-Path $backupDir "powertweaks_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
            "PreviousActiveScheme=$currentGuid" | Out-File -FilePath $metaFile -Encoding ASCII
            Write-Log -Level INFO -Message "Saved previous power scheme $currentGuid → $metaFile"
        } else {
            Write-Log -Level WARN -Message 'Could not determine current active power scheme; backup skipped.'
        }
    }

    # --- Create Home-WinDeck scheme if no High Performance variant exists ---
    if (-not $hpGuid) {
        Invoke-Action -Description "Duplicate Balanced scheme as 'Home-WinDeck-HighPerformance'" -ScriptBlock {
            $balLine = $schemeList | Select-String -Pattern 'Balanced' -SimpleMatch | Select-Object -First 1
            $balGuid = if ($balLine -and ($balLine.Line -match '([0-9a-fA-F-]{36})')) { $Matches[1] } else { '381b4222-f694-41f0-9685-ff5bb260df2e' }
            $dupOutput = (powercfg -duplicatescheme $balGuid) 2>&1
            if ($dupOutput -match '([0-9a-fA-F-]{36})') {
                $script:_pendingHpGuid = $Matches[1]
                powercfg -changename $script:_pendingHpGuid 'Home-WinDeck-HighPerformance' | Out-Null
                Write-Log -Level INFO -Message "Created 'Home-WinDeck-HighPerformance' scheme ($script:_pendingHpGuid)."
            } else {
                Write-Log -Level ERROR -Message "Failed to duplicate Balanced scheme: $dupOutput"
                throw 'Power scheme creation failed.'
            }
        }
        # Pull GUID out of script scope after Invoke-Action
        if (Get-Variable -Name _pendingHpGuid -Scope Script -ErrorAction SilentlyContinue) {
            $hpGuid = $script:_pendingHpGuid
            Remove-Variable -Name _pendingHpGuid -Scope Script -ErrorAction SilentlyContinue
        }
    }

    # --- Activate scheme and configure timeouts ---
    Invoke-Action -Description "Activate 'Home-WinDeck-HighPerformance' scheme; disable hibernate; set never-sleep/display-off (AC+DC)" -ScriptBlock {
        if (-not $hpGuid) {
            Write-Log -Level WARN -Message 'No scheme GUID available; skipping activation.'
            return
        }

        powercfg -setactive $hpGuid | Out-Null
        Write-Log -Level INFO -Message "Activated power scheme $hpGuid."

        powercfg -h off | Out-Null
        Write-Log -Level INFO -Message 'Disabled hibernation.'

        powercfg /change monitor-timeout-ac 0 | Out-Null
        powercfg /change monitor-timeout-dc 0 | Out-Null
        powercfg /change standby-timeout-ac  0 | Out-Null
        powercfg /change standby-timeout-dc  0 | Out-Null
        Write-Log -Level INFO -Message 'Set display and sleep timeouts to never (AC/DC).'
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
    $prev      = $null

    if (Test-Path $backupDir) {
        $meta = Get-ChildItem -Path $backupDir -Filter 'powertweaks_*.txt' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($meta) {
            foreach ($line in (Get-Content -Path $meta.FullName -ErrorAction SilentlyContinue)) {
                if ($line -match '^PreviousActiveScheme=(?<g>[0-9a-fA-F-]{36})') { $prev = $Matches['g'] }
            }
        }
    }

    Invoke-Action -Description "Restore power scheme $(if ($prev) { $prev } else { '(Balanced default)' }) and re-enable hibernation" -ScriptBlock {
        if ($prev) {
            powercfg -setactive $prev | Out-Null
            Write-Log -Level INFO -Message "Restored power scheme $prev."
        } else {
            Write-Log -Level WARN -Message 'No powertweaks backup found — activating Windows Balanced scheme.'
            powercfg -setactive '381b4222-f694-41f0-9685-ff5bb260df2e' | Out-Null
        }

        powercfg -h on | Out-Null
        Write-Log -Level INFO -Message 'Re-enabled hibernation.'
    }
}
