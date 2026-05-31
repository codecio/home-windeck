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
            New-Item -Path $_PersonalizationPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        try {
            Set-ItemProperty -Path $_PersonalizationPath -Name 'NoLockScreen' -Value 1 -Type DWord -ErrorAction Stop
            Write-Log -Level INFO -Message 'Lock screen disabled. Changes take effect at next logon.'
        }
        catch {
            Write-Log -Level ERROR -Message "Failed to set NoLockScreen: $_"
            throw
        }
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
        try {
            if (Test-Path $_PersonalizationPath) {
                Remove-ItemProperty -Path $_PersonalizationPath -Name 'NoLockScreen' -ErrorAction SilentlyContinue
                Write-Log -Level INFO -Message 'Lock screen re-enabled. Changes take effect at next logon.'
            } else {
                Write-Log -Level INFO -Message 'Personalization policy key not found — lock screen already at default.'
            }
        }
        catch {
            Write-Log -Level ERROR -Message "Failed to remove NoLockScreen: $_"
            throw
        }
    }
}

function Set-LockScreenWallpaper {
    <#
    .SYNOPSIS
        Sets a custom lock screen wallpaper via the Personalization policy (LockScreenImage).

    .DESCRIPTION
        Copies the provided image into C:\ProgramData\Home-WinDeck\LockScreen, grants SYSTEM
        read access (required by the logon screen process), and sets both LockScreenImage and
        LockScreenImageStatus=1 under HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization.
        Also removes NoLockScreen so the wallpaper is actually visible.

        Run gpupdate /force and lock (Win+L) to verify.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string] $ImagePath,

        [string] $DestinationRoot = 'C:\ProgramData\Home-WinDeck\LockScreen'
    )

    if (-not (Test-Path -Path $ImagePath)) {
        Write-Log -Level ERROR -Message "Image not found: $ImagePath"
        return
    }

    # Validate format — Windows lock screen only renders JPEG, PNG, BMP
    $validExts = @('.jpg', '.jpeg', '.png', '.bmp')
    $ext = [IO.Path]::GetExtension($ImagePath).ToLower()
    if ($ext -notin $validExts) {
        Write-Log -Level ERROR -Message "Unsupported format '$ext'. Accepted: $($validExts -join ', ')"
        return
    }

    Backup-RegistryKey -Path $_PersonalizationPath -Name 'LockScreenImage'

    $destDir  = $DestinationRoot
    $destFile = Join-Path $destDir ("lockscreen" + $ext)

    Invoke-Action -Description "Copy image to '$destFile', grant SYSTEM read, apply LockScreenImage + LockScreenImageStatus=1, clear NoLockScreen" -ScriptBlock {
        try {
            # Copy image
            if (-not (Test-Path -Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item -Path $ImagePath -Destination $destFile -Force -ErrorAction Stop

            # Grant SYSTEM read — the logon/lock screen process runs as SYSTEM and must read the file
            icacls "$destFile" /grant "NT AUTHORITY\SYSTEM:(R)" 2>&1 | Out-Null

            # Ensure policy key exists
            if (-not (Test-Path $_PersonalizationPath)) {
                New-Item -Path $_PersonalizationPath -Force | Out-Null
            }

            # Remove NoLockScreen — if set to 1 the lock screen is bypassed entirely and the wallpaper won't show
            Remove-ItemProperty -Path $_PersonalizationPath -Name 'NoLockScreen' -ErrorAction SilentlyContinue

            # Set image path
            Set-ItemProperty -Path $_PersonalizationPath -Name 'LockScreenImage'       -Value $destFile -Type String -ErrorAction Stop
            # LockScreenImageStatus = 1 signals Windows that the policy is active (required)
            Set-ItemProperty -Path $_PersonalizationPath -Name 'LockScreenImageStatus' -Value 1         -Type DWord  -ErrorAction Stop

            Write-Log -Level INFO -Message "Lock screen wallpaper set: $destFile"
            Write-Log -Level INFO -Message 'Run: gpupdate /force   then Win+L to verify.'
        }
        catch {
            Write-Log -Level ERROR -Message "Failed to set lock screen image: $_"
            throw
        }
    }
}

function Remove-LockScreenWallpaper {
    <#
    .SYNOPSIS
        Removes the LockScreenImage policy value and cleans up the copied image file.
    #>
    [CmdletBinding()]
    param()

    Backup-RegistryKey -Path $_PersonalizationPath -Name 'LockScreenImage'

    Invoke-Action -Description 'Remove LockScreenImage policy and cleanup copied file' -ScriptBlock {
        try {
            if (Test-Path $_PersonalizationPath) {
                $existing = (Get-ItemProperty -Path $_PersonalizationPath -Name 'LockScreenImage' -ErrorAction SilentlyContinue).LockScreenImage
                if ($existing) {
                    Remove-ItemProperty -Path $_PersonalizationPath -Name 'LockScreenImage' -ErrorAction SilentlyContinue
                    Write-Log -Level INFO -Message 'Removed LockScreenImage policy value.'

                    if (Test-Path -Path $existing) {
                        try {
                            Remove-Item -LiteralPath $existing -Force -ErrorAction SilentlyContinue
                            Write-Log -Level INFO -Message "Removed copied lockscreen file: $existing"
                        }
                        catch {
                            Write-Log -Level WARN -Message "Failed to remove lockscreen file: $_"
                        }
                    }
                }
                else {
                    Write-Log -Level INFO -Message 'No LockScreenImage policy value present.'
                }
            }
            else {
                Write-Log -Level INFO -Message 'Personalization policy key not present.'
            }
        }
        catch {
            Write-Log -Level ERROR -Message "Failed to remove LockScreenImage: $_"
            throw
        }
    }
}
