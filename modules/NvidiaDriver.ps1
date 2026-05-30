<#
.SYNOPSIS
    NvidiaDriver module — installs the NVIDIA graphics driver via winget.

.DESCRIPTION
    Install-NvidiaDriver   : Installs Nvidia.GraphicsDriver via winget. Prompts
                             for confirmation unless -Yes is supplied.
    Uninstall-NvidiaDriver : Advisory only — driver uninstallation is not
                             automated to avoid leaving the system in a broken
                             display state.

    winget package choice: Nvidia.GraphicsDriver
        - Ships the full DCH display driver without GeForce Experience telemetry.
        - Alternative: Nvidia.GeForceExperience (includes GFE overlay; larger).
          Switch the $PackageId variable below to prefer GFE.

    Note: This module is opt-in. It is not included in the default -Modules list
    because it is hardware-specific and takes several minutes to install.
#>

$_NvidiaPackageId = 'Nvidia.GraphicsDriver'

function Install-NvidiaDriver {
    <#
    .SYNOPSIS
        Installs the NVIDIA graphics driver (Nvidia.GraphicsDriver) via winget.
    .PARAMETER Yes
        Skip the confirmation prompt and install immediately.
    #>
    [CmdletBinding()]
    param(
        [switch] $Yes
    )

    if (-not (Test-Winget)) { return }

    if (-not $Yes -and -not $script:DryRun) {
        $confirm = Read-Host "This will download and install the NVIDIA graphics driver ($_NvidiaPackageId). Continue? [y/N]"
        if ($confirm -notmatch '^[Yy]') {
            Write-Log -Level INFO -Message 'NVIDIA driver installation cancelled by user.'
            return
        }
    }

    # Idempotency check
    if (-not $script:DryRun) {
        $listed = winget list --id $_NvidiaPackageId --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -and ($listed -match [regex]::Escape($_NvidiaPackageId))) {
            Write-Log -Level INFO -Message "NVIDIA driver ($_NvidiaPackageId) is already installed — skipping."
            return
        }
    }

    Invoke-Action -Description "Install NVIDIA graphics driver via winget ($_NvidiaPackageId)" -ScriptBlock {
        $ok = Invoke-Winget -Arguments @('install', '--id', $_NvidiaPackageId, '--silent')
        if ($ok) {
            Write-Log -Level INFO -Message 'NVIDIA driver installed. A reboot may be required.'
        } else {
            Write-Log -Level ERROR -Message 'NVIDIA driver installation failed. Check winget output above.'
        }
    }
}

function Uninstall-NvidiaDriver {
    <#
    .SYNOPSIS
        Advisory only — prints guidance without taking action.
    #>
    [CmdletBinding()]
    param()

    Write-Log -Level WARN -Message @'
Uninstalling the NVIDIA driver is intentionally NOT automated by this script.

Removing a display driver can leave the system with only basic VGA output until
a driver is reinstalled. To uninstall manually:
  1. Open "Add or Remove Programs" → search for "NVIDIA" → Uninstall each component.
  2. Optionally use DDU (Display Driver Uninstaller) in Safe Mode for a clean removal.

Revert of NvidiaDriver is complete (advisory only).
'@
}
