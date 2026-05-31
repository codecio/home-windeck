<#
.SYNOPSIS
    SteamStartup module — registers/removes a scheduled task that launches Steam
    in Big Picture mode at logon.

.DESCRIPTION
    Register-SteamStartupTask   : Creates a Task Scheduler job that runs
                                  steam.exe -bigpicture -silent at logon for the
                                  specified user, with a 30-second delay to ensure
                                  the desktop shell is ready.
    Unregister-SteamStartupTask : Removes the task by its canonical name.
#>

$_TaskName    = 'Home-WinDeck-BigPictureAutostart'
$_OldTaskName = 'SteamConsoleSetup-BigPictureAutostart'   # legacy name — cleaned up on register

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
        Creates a Task Scheduler job that starts Steam in Big Picture mode at logon.
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

    # Idempotency check
    if (-not $script:DryRun) {
        $existing = Get-ScheduledTask -TaskName $_TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log -Level INFO -Message "Scheduled task '$_TaskName' already exists — skipping."
            return
        }
    }

    $steamExe = Get-SteamExePath
    if (-not $steamExe -and -not $script:DryRun) {
        Write-Log -Level WARN -Message 'steam.exe not found. Install Steam first (run with -Modules SteamInstall) then re-run.'
        $steamExe = 'C:\Program Files (x86)\Steam\steam.exe'
    }
    if (-not $steamExe) { $steamExe = 'C:\Program Files (x86)\Steam\steam.exe' }

    Invoke-Action -Description "Register task '$_TaskName' → '$steamExe -bigpicture -silent' at logon (30s delay)" -ScriptBlock {
        if ($User -match '\\') { $userId = $User } else { $userId = "$env:COMPUTERNAME\$User" }

        # /TR must quote the exe path when it contains spaces.
        # /DELAY 0:30 allows the desktop shell to fully initialize before Steam launches.
        $output = schtasks /Create /TN "$_TaskName" /TR "`"$steamExe`" -bigpicture -silent" /SC ONLOGON /DELAY 0:30 /RU "$userId" /F 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Level INFO -Message "Task '$_TaskName' created successfully."
        } else {
            Write-Log -Level ERROR -Message "schtasks.exe failed (exit $LASTEXITCODE): $($output -join ' | ')"
            throw 'Task registration failed.'
        }
    }
}

function Unregister-SteamStartupTask {
    <#
    .SYNOPSIS
        Removes the Steam Big Picture startup task if it exists.
    #>
    [CmdletBinding()]
    param()

    Invoke-Action -Description "Unregister task '$_TaskName'" -ScriptBlock {
        $existing = Get-ScheduledTask -TaskName $_TaskName -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Log -Level INFO -Message "Task '$_TaskName' not found — nothing to remove."
            return
        }
        Unregister-ScheduledTask -TaskName $_TaskName -Confirm:$false
        Write-Log -Level INFO -Message "Task '$_TaskName' removed."
    }
}
