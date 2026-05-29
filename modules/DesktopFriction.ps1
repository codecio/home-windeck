<#
.SYNOPSIS
    DesktopFriction module — reduces desktop friction for a console-like experience.

.DESCRIPTION
    Disable-LockScreen : Backs up and sets the NoLockScreen policy DWORD so the
                         lock screen is bypassed on wake/boot.
    Enable-LockScreen  : Restores the lock screen by removing the NoLockScreen
                         policy value.

    The policy key used is:
        HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization
        Value: NoLockScreen (DWORD) = 1

    Designed for extension: future sub-features (disable first-sign-in animation,
    suppress toast notifications, remove desktop icons) can be added here as
    additional Invoke-Action blocks inside each function.
#>

$_PersonalizationPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'

function Disable-LockScreen {
    <#
    .SYNOPSIS
        Disables the Windows lock screen via Group Policy registry key.
    #>
    [CmdletBinding()]
    param()

    Backup-RegistryKey -Path $_PersonalizationPath -Name 'Personalization'

    Invoke-Action -Description 'Create Personalization policy key and set NoLockScreen=1' -ScriptBlock {
        if (-not (Test-Path $_PersonalizationPath)) {
            New-Item -Path $_PersonalizationPath -Force | Out-Null
        }
        Set-ItemProperty -Path $_PersonalizationPath -Name 'NoLockScreen' -Value 1 -Type DWord
        Write-Log -Level INFO -Message 'Lock screen disabled. Changes take effect at next logon.'
    }
}

function Enable-LockScreen {
    <#
    .SYNOPSIS
        Re-enables the Windows lock screen by removing the NoLockScreen policy value.
    #>
    [CmdletBinding()]
    param()

    Backup-RegistryKey -Path $_PersonalizationPath -Name 'Personalization'

    Invoke-Action -Description 'Remove NoLockScreen from Personalization policy key' -ScriptBlock {
        if (Test-Path $_PersonalizationPath) {
            Remove-ItemProperty -Path $_PersonalizationPath -Name 'NoLockScreen' -ErrorAction SilentlyContinue
            Write-Log -Level INFO -Message 'Lock screen re-enabled. Changes take effect at next logon.'
        } else {
            Write-Log -Level INFO -Message 'Personalization policy key not found — lock screen already at default.'
        }
    }
}
