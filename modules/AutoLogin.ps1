<#
.SYNOPSIS
    AutoLogin module — enables/disables automatic Windows logon.

.DESCRIPTION
    Enable-AutoLogin  : Sets AutoAdminLogon in the Winlogon registry key so the
                        specified local account logs in automatically after reboot.
    Disable-AutoLogin : Removes the AutoAdminLogon, DefaultUserName, and
                        DefaultPassword values, restoring manual login.

    ⚠ SECURITY WARNING: DefaultPassword is stored in PLAINTEXT under
      HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon.
      Use a dedicated, low-privilege local account — do NOT use an admin or
      Microsoft account for AutoLogin.
#>

$_WinlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

function Enable-AutoLogin {
    <#
    .SYNOPSIS
        Configures Windows to automatically log in as the specified local user.
    .PARAMETER User
        Local account username. Prompted interactively if not supplied.
    #>
    [CmdletBinding()]
    param(
        [string] $User
    )

    if (-not $User) {
        $User = Read-Host 'Enter the local username for AutoLogin'
    }

    # Validate the account exists
    if (-not $script:DryRun) {
        try {
            Get-LocalUser -Name $User -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Log -Level ERROR -Message "Local user '$User' not found. Create the account first and re-run."
            return
        }
    }

    $plainPw = $null
    if (-not $script:DryRun) {
        $password = Read-Host "Enter password for '$User' (stored in registry — see README)" -AsSecureString
        $plainPw  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    }

    Backup-RegistryKey -Path $_WinlogonPath -Name 'Winlogon'

    Invoke-Action -Description "Set AutoAdminLogon=1, DefaultUserName=$User in Winlogon" -ScriptBlock {
        $key = $_WinlogonPath
        Set-ItemProperty -Path $key -Name 'AutoAdminLogon'  -Value '1'      -Type String
        Set-ItemProperty -Path $key -Name 'DefaultUserName' -Value $User    -Type String
        Set-ItemProperty -Path $key -Name 'DefaultPassword' -Value $plainPw -Type String
        # Clear AutoLogonCount so the setting never expires
        Remove-ItemProperty -Path $key -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
        Write-Log -Level INFO -Message "AutoLogin enabled for '$User'. Reboot to activate."
    }
}

function Disable-AutoLogin {
    <#
    .SYNOPSIS
        Removes AutoLogin settings, restoring the Windows login prompt.
    #>
    [CmdletBinding()]
    param()

    Backup-RegistryKey -Path $_WinlogonPath -Name 'Winlogon'

    Invoke-Action -Description 'Remove AutoAdminLogon, DefaultUserName, DefaultPassword from Winlogon' -ScriptBlock {
        $key = $_WinlogonPath
        Set-ItemProperty -Path $key -Name 'AutoAdminLogon' -Value '0' -Type String -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key -Name 'DefaultPassword'  -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key -Name 'AutoLogonCount'   -ErrorAction SilentlyContinue
        Write-Log -Level INFO -Message 'AutoLogin disabled. Manual login will be required after reboot.'
    }
}
