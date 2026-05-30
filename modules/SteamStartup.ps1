<#
.SYNOPSIS
    SteamStartup module — registers/removes a scheduled task that launches Steam
    in Big Picture mode at logon.

.DESCRIPTION
    Register-SteamStartupTask   : Creates a Task Scheduler job that runs
                                  steam.exe -bigpicture -silent at logon for the
                                  specified user, using a LIMITED-privilege principal.
    Unregister-SteamStartupTask : Removes the task by its canonical name.
#>

$_TaskName = 'SteamConsoleSetup-BigPictureAutostart'

function _Find-SteamExe {
    # Prefer registry lookup; fall back to default install path
    $regPath   = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'
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

    # Idempotency check
    if (-not $script:DryRun) {
        $existing = Get-ScheduledTask -TaskName $_TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log -Level INFO -Message "Scheduled task '$_TaskName' already exists — skipping."
            return
        }
    }

    $steamExe = _Find-SteamExe
    if (-not $steamExe -and -not $script:DryRun) {
        Write-Log -Level WARN -Message 'steam.exe not found. Install Steam first (run with -Modules SteamInstall) then re-run.'
        $steamExe = 'C:\Program Files (x86)\Steam\steam.exe'  # use default for task definition
    }
    if (-not $steamExe) { $steamExe = 'C:\Program Files (x86)\Steam\steam.exe' }

    Invoke-Action -Description "Register scheduled task '$_TaskName' for user '$User' (steam.exe -bigpicture -silent)" -ScriptBlock {
        # Use schtasks.exe to create the task (portable and avoids Register-ScheduledTask parameter issues)
        $tr = "`"$steamExe`" -bigpicture -silent"
        if ($User -match '\\') { $userId = $User } else { $userId = "$env:COMPUTERNAME\$User" }

        # Build a single argument string to preserve the /TR value with inner quotes
        $trQuoted = '"' + $steamExe + ' -bigpicture -silent' + '"'
        $argString = "/Create /TN `"$($_TaskName)`" /TR $trQuoted /SC ONLOGON /RU `"$userId`" /F"

        $proc = Start-Process -FilePath 'schtasks.exe' -ArgumentList $argString -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
        if ($proc -and $proc.ExitCode -eq 0) {
            Write-Log -Level INFO -Message "Scheduled task '$_TaskName' created via schtasks.exe."
        } else {
            # Attempt to capture standard output by running schtasks synchronously with & and redirecting
            try {
                $output = schtasks.exe /Create /TN "$_TaskName" /TR "$steamExe -bigpicture -silent" /SC ONLOGON /RU "$userId" /F 2>&1
            } catch {
                $output = "schtasks invocation failed"
            }
            $out = if ($proc) { "ExitCode=$($proc.ExitCode); Output=$($output -join ' | ')" } else { "Start-Process failed; Output=$($output -join ' | ')" }
            Write-Log -Level ERROR -Message "schtasks.exe failed to create task: $out"
            throw
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

    Invoke-Action -Description "Unregister scheduled task '$_TaskName'" -ScriptBlock {
        $existing = Get-ScheduledTask -TaskName $_TaskName -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Log -Level INFO -Message "Scheduled task '$_TaskName' not found — nothing to remove."
            return
        }
        Unregister-ScheduledTask -TaskName $_TaskName -Confirm:$false
        Write-Log -Level INFO -Message "Scheduled task '$_TaskName' removed."
    }
}
