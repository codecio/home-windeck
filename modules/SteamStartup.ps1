<#
.SYNOPSIS
    SteamStartup module — registers/removes a scheduled task that launches Steam
    in Big Picture mode at logon.

.DESCRIPTION
    Register-SteamStartupTask   : Sets Steam's StartupMode registry value to 7
                                  (Big Picture) so Steam always opens in Big Picture
                                  regardless of how it is launched. Also removes
                                  Steam's own Run-key autostart (which would race
                                  with our task and launch in normal mode), and
                                  registers a Task Scheduler job at logon with a
                                  30-second delay.
    Unregister-SteamStartupTask : Removes the task and restores StartupMode to 0
                                  (normal/desktop mode).
#>

$_TaskName    = 'Home-WinDeck-BigPictureAutostart'
$_OldTaskName = 'SteamConsoleSetup-BigPictureAutostart'   # legacy name — cleaned up on register
$_SteamRunKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$_SteamUserRegPath = 'HKCU:\SOFTWARE\Valve\Steam'

function Get-SteamExePath {
    # Prefer registry lookup; fall back to well-known default path
    $regPath    = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'
    $installDir = $null

    try {
        $installDir = (Get-ItemProperty -Path $regPath -Name 'InstallPath' -ErrorAction Stop).InstallPath
    } catch { }

    if ($installDir) {
        $candidate = Join-Path $installDir 'steam.exe'
        if (Test-Path $candidate) { return $candidate }
    }

    $default = 'C:\Program Files (x86)\Steam\steam.exe'
    if (Test-Path $default) { return $default }

    return $null
}

function Register-SteamStartupTask {
    <#
    .SYNOPSIS
        Configures Steam to always start in Big Picture mode and registers the logon task.
    .PARAMETER User
        The Windows user account the task runs for. Defaults to the current user.
    #>
    [CmdletBinding()]
    param(
        [string] $User = $env:USERNAME
    )

    # Remove legacy task name left by earlier versions of this script
    Invoke-Action -Description "Remove legacy task '$_OldTaskName' if present" -ScriptBlock {
        $old = Get-ScheduledTask -TaskName $_OldTaskName -ErrorAction SilentlyContinue
        if ($old) {
            schtasks /Delete /TN "$_OldTaskName" /F 2>&1 | Out-Null
            Write-Log -Level INFO -Message "Removed legacy task '$_OldTaskName'."
        }
    }

    # Set Steam's own StartupMode = 7 (Big Picture).
    # This is the most reliable method — Steam reads this on every launch and
    # overrides whatever command-line flags are passed.
    Invoke-Action -Description "Set Steam StartupMode=7 (Big Picture) in HKCU registry" -ScriptBlock {
        if (-not (Test-Path $_SteamUserRegPath)) {
            New-Item -Path $_SteamUserRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $_SteamUserRegPath -Name 'StartupMode' -Value 7 -Type DWord
        Write-Log -Level INFO -Message "Steam StartupMode set to 7 (Big Picture)."
    }

    # Remove Steam's own Run-key autostart — it launches steam.exe with no flags
    # (normal/desktop mode) and races with our scheduled task.
    Invoke-Action -Description "Remove Steam self-registered Run key autostart (prevents normal-mode race)" -ScriptBlock {
        $steamRunValue = (Get-ItemProperty -Path $_SteamRunKey -ErrorAction SilentlyContinue).Steam
        if ($steamRunValue) {
            Remove-ItemProperty -Path $_SteamRunKey -Name 'Steam' -ErrorAction SilentlyContinue
            Write-Log -Level INFO -Message "Removed Steam Run key autostart entry."
        } else {
            Write-Log -Level INFO -Message "No Steam Run key autostart found — nothing to remove."
        }
    }

    $steamExe = Get-SteamExePath
    if (-not $steamExe -and -not $script:DryRun) {
        Write-Log -Level WARN -Message 'steam.exe not found. Install Steam first (run with -Modules SteamInstall) then re-run.'
        $steamExe = 'C:\Program Files (x86)\Steam\steam.exe'
    }
    if (-not $steamExe) { $steamExe = 'C:\Program Files (x86)\Steam\steam.exe' }

    Invoke-Action -Description "Register task '$_TaskName' → '$steamExe' at logon (30s delay)" -ScriptBlock {
        if ($User -match '\\') { $userId = $User } else { $userId = "$env:COMPUTERNAME\$User" }

        # Primary: Register-ScheduledTask (handles exe paths with spaces natively)
        try {
            $action    = New-ScheduledTaskAction -Execute $steamExe
            $trigger   = New-ScheduledTaskTrigger -AtLogOn
            $trigger.Delay = 'PT30S'   # ISO 8601 — 30 second delay for desktop readiness
            $settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew
            $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
            Register-ScheduledTask -TaskName $_TaskName -Action $action -Trigger $trigger `
                -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
            Write-Log -Level INFO -Message "Task '$_TaskName' created via Register-ScheduledTask."
        }
        catch {
            Write-Log -Level WARN -Message "Register-ScheduledTask failed ($($_.Exception.Message)) — trying schtasks fallback."
            $argStr = "/Create /TN `"$_TaskName`" /TR `"`"$steamExe`"`" /SC ONLOGON /DELAY 0:30 /RU `"$userId`" /F"
            $proc   = Start-Process -FilePath "$env:SystemRoot\System32\schtasks.exe" `
                          -ArgumentList $argStr -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
            if (-not $proc -or $proc.ExitCode -ne 0) {
                Write-Log -Level ERROR -Message "schtasks fallback failed (exit $($proc.ExitCode))."
                throw 'Task registration failed.'
            }
            Write-Log -Level INFO -Message "Task '$_TaskName' created via schtasks fallback."
        }
    }
}

function Unregister-SteamStartupTask {
    <#
    .SYNOPSIS
        Removes the Steam Big Picture startup task and restores normal Steam startup mode.
    #>
    [CmdletBinding()]
    param()

    Invoke-Action -Description "Unregister task '$_TaskName'" -ScriptBlock {
        $existing = Get-ScheduledTask -TaskName $_TaskName -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Log -Level INFO -Message "Task '$_TaskName' not found — nothing to remove."
        } else {
            Unregister-ScheduledTask -TaskName $_TaskName -Confirm:$false
            Write-Log -Level INFO -Message "Task '$_TaskName' removed."
        }
    }

    # Restore Steam to normal/desktop startup mode
    Invoke-Action -Description "Restore Steam StartupMode=0 (normal desktop mode)" -ScriptBlock {
        if (Test-Path $_SteamUserRegPath) {
            Set-ItemProperty -Path $_SteamUserRegPath -Name 'StartupMode' -Value 0 -Type DWord
            Write-Log -Level INFO -Message "Steam StartupMode restored to 0 (desktop mode)."
        }
    }
}
