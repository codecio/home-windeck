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
        $password = Read-Host "Enter password for '$User' (will be stored securely with Autologon if available, otherwise in registry)" -AsSecureString
        $plainPw  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    }

    Backup-RegistryKey -Path $_WinlogonPath -Name 'Winlogon'

    # Detect or download Autologon.exe (tools/Autologon.exe in repo or on PATH). If missing, download by default.
    $autologonPath = $null
    $toolsDir = Join-Path $script:RepoRoot 'tools'
    $candidate = Join-Path $toolsDir 'Autologon.exe'
    if (Test-Path $candidate) { $autologonPath = $candidate } else {
        $cmd = Get-Command Autologon.exe -ErrorAction SilentlyContinue
        if ($cmd) { $autologonPath = $cmd.Source }
    }

    if (-not $autologonPath) {
        $downloadUrl = 'https://download.sysinternals.com/files/AutoLogon.zip'
        $zipPath = Join-Path $toolsDir 'AutoLogon.zip'

        if ($script:DryRun) {
            Write-Log -Level DRY -Message "WOULD: Download Autologon from $downloadUrl to $zipPath and extract to $toolsDir"
        } else {
            try {
                if (-not (Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir | Out-Null }
                Write-Log -Level INFO -Message "Downloading Autologon from $downloadUrl → $zipPath"
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -ErrorAction Stop
                Expand-Archive -LiteralPath $zipPath -DestinationPath $toolsDir -Force -ErrorAction Stop
                Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
                $autologonCandidate = Join-Path $toolsDir 'Autologon.exe'
                if (Test-Path $autologonCandidate) {
                    $autologonPath = $autologonCandidate
                    Write-Log -Level INFO -Message "Autologon.exe downloaded to $autologonPath"
                } else {
                    Write-Log -Level WARN -Message 'Downloaded archive did not contain Autologon.exe; falling back to registry method.'
                }
            } catch {
                Write-Log -Level WARN -Message "Failed to download or extract Autologon.exe: $_. Falling back to registry method."
            }
        }
    }

    if ($autologonPath) {
        Invoke-Action -Description "Configure Autologon via $autologonPath for $User" -ScriptBlock {
            if ($script:DryRun) {
                Write-Log -Level DRY -Message "WOULD: Run $autologonPath /accepteula $User $env:COMPUTERNAME <password hidden>"
            } else {
                $autologonArgs = @('/accepteula', $User, $env:COMPUTERNAME, $plainPw)
                $proc = Start-Process -FilePath $autologonPath -ArgumentList $autologonArgs -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
                if ($proc -and $proc.ExitCode -eq 0) {
                    Write-Log -Level INFO -Message "Autologon configured via Autologon.exe; credentials stored as LSA secret."
                    # Ensure AutoAdminLogon and DefaultUserName set (Autologon may set these itself)
                    Set-ItemProperty -Path $_WinlogonPath -Name 'AutoAdminLogon' -Value '1' -Type String -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $_WinlogonPath -Name 'DefaultUserName' -Value $User -Type String -ErrorAction SilentlyContinue
                } else {
                    Write-Log -Level WARN -Message "Autologon.exe failed (exit $($proc.ExitCode)); falling back to registry DefaultPassword."
                    Set-ItemProperty -Path $_WinlogonPath -Name 'AutoAdminLogon'  -Value '1'      -Type String
                    Set-ItemProperty -Path $_WinlogonPath -Name 'DefaultUserName' -Value $User    -Type String
                    Set-ItemProperty -Path $_WinlogonPath -Name 'DefaultPassword' -Value $plainPw -Type String
                }
                Remove-ItemProperty -Path $_WinlogonPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
                Write-Log -Level INFO -Message "AutoLogin enabled for '$User'. Reboot to activate."
            }
        }
    } else {
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
}

function Disable-AutoLogin {
    <#
    .SYNOPSIS
        Removes AutoLogin settings, restoring the Windows login prompt.
    #>
    [CmdletBinding()]
    param()

    Backup-RegistryKey -Path $_WinlogonPath -Name 'Winlogon'

    # If Autologon.exe is available, attempt to disable it first
    $autologonPath = $null
    $candidate = Join-Path $script:RepoRoot 'tools\Autologon.exe'
    if (Test-Path $candidate) { $autologonPath = $candidate } else {
        $cmd = Get-Command Autologon.exe -ErrorAction SilentlyContinue
        if ($cmd) { $autologonPath = $cmd.Source }
    }

    if ($autologonPath) {
        Invoke-Action -Description "Disable Autologon via $autologonPath" -ScriptBlock {
            if ($script:DryRun) {
                Write-Log -Level DRY -Message "WOULD: Run $autologonPath /delete"
            } else {
                try {
                    $proc = Start-Process -FilePath $autologonPath -ArgumentList '/delete' -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
                    if ($proc -and $proc.ExitCode -eq 0) {
                        Write-Log -Level INFO -Message 'Autologon disabled via Autologon.exe.'
                    } else {
                        Write-Log -Level WARN -Message 'Autologon.exe did not report success — continuing with registry cleanup.'
                    }
                } catch {
                    Write-Log -Level WARN -Message "Failed to run Autologon.exe: $_"
                }
            }
        }
    }

    Invoke-Action -Description 'Remove AutoAdminLogon, DefaultUserName, DefaultPassword from Winlogon' -ScriptBlock {
        $key = $_WinlogonPath
        Set-ItemProperty -Path $key -Name 'AutoAdminLogon' -Value '0' -Type String -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key -Name 'DefaultPassword'  -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key -Name 'AutoLogonCount'   -ErrorAction SilentlyContinue
        Write-Log -Level INFO -Message 'AutoLogin disabled. Manual login will be required after reboot.'
    }
}
