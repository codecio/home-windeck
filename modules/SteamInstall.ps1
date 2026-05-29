<#
.SYNOPSIS
    SteamInstall module — installs Steam via winget.

.DESCRIPTION
    Install-Steam   : Installs Steam (Valve.Steam) if not already present.
    Uninstall-Steam : Advisory only — prints guidance without taking action.
                      Silently uninstalling Steam could destroy game library data,
                      so this is intentionally left to the user.
#>

function Install-Steam {
    <#
    .SYNOPSIS
        Installs Steam using winget if it is not already installed.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Winget)) { return }

    # Idempotency check
    if (-not $script:DryRun) {
        $listed = winget list --id Valve.Steam --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -and ($listed -match 'Valve\.Steam')) {
            Write-Log -Level INFO -Message 'Steam is already installed — skipping.'
            return
        }
    }

    Invoke-Action -Description 'Install Steam via winget (Valve.Steam)' -ScriptBlock {
        $ok = Invoke-Winget -Arguments @('install', '--id', 'Valve.Steam', '--silent')
        if ($ok) {
            Write-Log -Level INFO -Message 'Steam installed successfully.'
        } else {
            Write-Log -Level ERROR -Message 'Steam installation failed. Check winget output above.'
        }
    }
}

function Uninstall-Steam {
    <#
    .SYNOPSIS
        Advisory only — prints uninstall guidance without taking action.
    #>
    [CmdletBinding()]
    param()

    Write-Log -Level WARN -Message @'
Uninstalling Steam is intentionally NOT automated by this script.

Removing Steam via winget or the uninstaller would also delete your game library
data if the library folder is inside the default Steam directory. To uninstall:
  1. Move or back up any game libraries you want to keep.
  2. Open "Add or Remove Programs" → search for Steam → Uninstall.
  3. Delete the remaining Steam folder (default: C:\Program Files (x86)\Steam).

Revert of SteamInstall is complete (advisory only).
'@
}
