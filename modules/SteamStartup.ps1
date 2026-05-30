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
        $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $User
        $action    = New-ScheduledTaskAction  -Execute $steamExe -Argument '-bigpicture -silent'
        $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
                                                   -MultipleInstances IgnoreNew

        # Qualify user name to MACHINE\User if needed
        if ($User -match '\\') { $userId = $User } else { $userId = "$env:COMPUTERNAME\$User" }

        try {
            # Try the native Register-ScheduledTask with -User/-RunLevel first
            Register-ScheduledTask -TaskName $_TaskName `
                                   -Trigger   $trigger   `
                                   -Action    $action    `
                                   -Settings  $settings  `
                                   -User      $userId    `
                                   -RunLevel  'Limited'  `
                                   -Force | Out-Null

            Write-Log -Level INFO -Message "Scheduled task '$_TaskName' registered. Steam Big Picture will start at next logon for '$User'."
        }
        catch {
            Write-Log -Level WARN -Message "Register-ScheduledTask failed: $_. Attempting schtasks.exe fallback..."

            # Fallback to schtasks.exe which tends to accept MACHINE\User
            $tr = "`"$steamExe`" -bigpicture -silent"
            $args = @('/Create','/TN',$_TaskName,'/TR',$tr,'/SC','ONLOGON','/RU',$userId,'/F')
            $proc = Start-Process -FilePath 'schtasks.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
            if ($proc -and $proc.ExitCode -eq 0) {
                Write-Log -Level INFO -Message "Scheduled task '$_TaskName' created via schtasks.exe fallback."
            } else {
                $out = if ($proc) { "ExitCode=$($proc.ExitCode)" } else { 'Start-Process failed' }
                Write-Log -Level ERROR -Message "schtasks.exe fallback failed: $out"
                throw
            }
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
