<#
.SYNOPSIS
    Setup-SteamConsole.ps1 — transforms a Windows 11 PC into a Steam console
    experience with automatic logon, Big Picture startup, and reduced desktop
    friction.

.DESCRIPTION
    Single entry point that dot-sources feature modules from the modules\ folder
    and orchestrates install or revert operations with structured logging,
    dry-run support, and registry backups.

.PARAMETER Install
    (Default) Run the Enable-* / Install-* function for each selected module.

.PARAMETER Revert
    Run the Disable-* / Uninstall-* function for each selected module.
    Mutually exclusive with -Install.

.PARAMETER DryRun
    Log every action that WOULD be taken without making any changes.
    Safe to run without administrator privileges.

.PARAMETER Modules
    Comma-separated list of modules to act on.
    Valid values: AutoLogin, SteamInstall, SteamStartup, NvidiaDriver, DesktopFriction
    Default (when -Install): AutoLogin, SteamInstall, SteamStartup, DesktopFriction
    NvidiaDriver is opt-in due to download size and hardware specificity.

.PARAMETER User
    Windows local username passed to AutoLogin and SteamStartup modules.
    Defaults to the current user ($env:USERNAME).

.PARAMETER LogPath
    Override the log file path. Default: logs\<timestamp>.log inside the repo.

.PARAMETER Yes
    Skip interactive confirmation prompts (e.g., for NvidiaDriver installation).

.EXAMPLE
    # Full install with default modules (requires elevation)
    .\Setup-SteamConsole.ps1

.EXAMPLE
    # Dry-run to preview what would happen
    .\Setup-SteamConsole.ps1 -DryRun

.EXAMPLE
    # Install only the scheduled task for a specific user
    .\Setup-SteamConsole.ps1 -Modules SteamStartup -User gamer

.EXAMPLE
    # Opt into NVIDIA driver install alongside defaults
    .\Setup-SteamConsole.ps1 -Modules AutoLogin,SteamInstall,SteamStartup,DesktopFriction,NvidiaDriver -Yes

.EXAMPLE
    # Revert all default modules
    .\Setup-SteamConsole.ps1 -Revert

.EXAMPLE
    # Dry-run revert for a specific module
    .\Setup-SteamConsole.ps1 -Revert -DryRun -Modules SteamStartup
#>

[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [switch] $Install,

    [Parameter(ParameterSetName = 'Revert', Mandatory)]
    [switch] $Revert,

    [switch]   $DryRun,

    [string[]] $Modules,

    [string]   $User = $env:USERNAME,

    [string]   $LogPath,

    [switch]   $Yes,

    [string]   $Wallpaper
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Repo root & script-scope state ───────────────────────────────────────

$script:RepoRoot = $PSScriptRoot
$script:DryRun   = $DryRun.IsPresent

#endregion

#region ── Dot-source modules ───────────────────────────────────────────────────

. (Join-Path $PSScriptRoot 'modules\Common.ps1')

foreach ($modFile in Get-ChildItem -Path (Join-Path $PSScriptRoot 'modules') -Filter '*.ps1' | Where-Object Name -ne 'Common.ps1') {
    . $modFile.FullName
}

#endregion

#region ── Logging initialisation ───────────────────────────────────────────────

$logsDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir | Out-Null }

if ($LogPath) {
    $script:LogFile = $LogPath
} else {
    $timestamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $logsDir "$timestamp.log"
}

Start-Transcript -Path $script:LogFile -Append -NoClobber -ErrorAction SilentlyContinue | Out-Null

Write-Log -Level INFO -Message "=== SteamConsoleSetup started ($(Get-Date -Format 'u')) ==="
if ($script:DryRun) { Write-Log -Level DRY -Message '*** DRY-RUN MODE — no changes will be made ***' }

#endregion

#region ── Admin check (skipped in DryRun) ──────────────────────────────────────

if (-not $script:DryRun) { Assert-Administrator }

#endregion

#region ── Module selection ─────────────────────────────────────────────────────

$validModules   = @('AutoLogin','SteamInstall','SteamStartup','NvidiaDriver','DesktopFriction','PowerTweaks')
$defaultModules = @('AutoLogin','SteamInstall','SteamStartup','DesktopFriction','PowerTweaks')

if (-not $Modules -or $Modules.Count -eq 0) {
    $selectedModules = $defaultModules
} else {
    # Flatten comma-separated strings that arrive as a single element when using -File
    $selectedModules = $Modules | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

# Validate
foreach ($m in $selectedModules) {
    if ($m -notin $validModules) {
        Write-Log -Level ERROR -Message "Unknown module '$m'. Valid modules: $($validModules -join ', ')"
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }
}

Write-Log -Level INFO -Message "Mode     : $($PSCmdlet.ParameterSetName.ToUpper())"
Write-Log -Level INFO -Message "Modules  : $($selectedModules -join ', ')"
Write-Log -Level INFO -Message "User     : $User"
Write-Log -Level INFO -Message "Log file : $($script:LogFile)"

# Handle wallpaper parameter (manual one-shot action)
if (-not $Revert -and $PSBoundParameters.ContainsKey('Wallpaper') -and $Wallpaper) {
    Write-Log -Level INFO -Message "Wallpaper parameter provided: $Wallpaper"

    if (-not (Test-Path -Path $Wallpaper)) {
        Write-Log -Level ERROR -Message "Wallpaper file not found: $Wallpaper"
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }

    # Prevent the main loop from flipping NoLockScreen back to '1' by removing DesktopFriction
    if ($selectedModules -contains 'DesktopFriction') {
        Write-Log -Level WARN -Message "Removing DesktopFriction from module list to avoid conflicting NoLockScreen changes when applying wallpaper."
        $selectedModules = $selectedModules | Where-Object { $_ -ne 'DesktopFriction' }
    }

    try {
        Set-LockScreenWallpaper -ImagePath $Wallpaper
        Write-Log -Level INFO -Message "Applied lock screen wallpaper: $Wallpaper"

        # Ensure lock screen is enabled so the image is visible
        try {
            Enable-LockScreen
            Write-Log -Level INFO -Message 'Ensured lock screen is enabled (NoLockScreen removed) so wallpaper will display.'
        }
        catch {
            Write-Log -Level WARN -Message "Failed to ensure lock screen enabled: $_"
        }
    }
    catch {
        Write-Log -Level ERROR -Message "Failed to apply wallpaper: $_"
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }

    Write-Log -Level INFO -Message "Continuing with remaining modules: $($selectedModules -join ', ')"

    if ($selectedModules.Count -eq 0) {
        Write-Log -Level INFO -Message 'No modules remaining after wallpaper setup. Done.'
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0
    }
}

#endregion

#region ── Dispatch table ───────────────────────────────────────────────────────

$dispatch = @{
    AutoLogin      = @{ Enable = { Enable-AutoLogin     -User $User };    Disable = { Disable-AutoLogin } }
    SteamInstall   = @{ Enable = { Install-Steam };                       Disable = { Uninstall-Steam   } }
    SteamStartup   = @{ Enable = { Register-SteamStartupTask -User $User }; Disable = { Unregister-SteamStartupTask } }
    NvidiaDriver   = @{ Enable = { Install-NvidiaDriver -Yes:$Yes };      Disable = { Uninstall-NvidiaDriver } }
    DesktopFriction= @{ Enable = { Disable-LockScreen };                  Disable = { Enable-LockScreen  } }
    PowerTweaks     = @{ Enable = { Enable-PowerTweaks };                  Disable = { Disable-PowerTweaks } }
}

#endregion

#region ── Main loop ────────────────────────────────────────────────────────────

$results = [ordered]@{}

foreach ($modName in $selectedModules) {
    Write-Log -Level INFO -Message "--- $modName ---"
    $action = if ($Revert) { 'Disable' } else { 'Enable' }
    $fn     = $dispatch[$modName][$action]

    try {
        & $fn
        $results[$modName] = 'OK'
    }
    catch {
        Write-Log -Level ERROR -Message "${modName}: $_"
        $results[$modName] = 'FAILED'
    }
}

#endregion

#region ── Summary ──────────────────────────────────────────────────────────────

Write-Log -Level INFO -Message '=== Summary ==='
$failCount = 0
foreach ($kv in $results.GetEnumerator()) {
    $lvl = if ($kv.Value -eq 'FAILED') { 'ERROR' } elseif ($script:DryRun) { 'DRY' } else { 'INFO' }
    $status = if ($script:DryRun -and $kv.Value -eq 'OK') { 'DRY-RUN OK' } else { $kv.Value }
    Write-Log -Level $lvl -Message "  $($kv.Key.PadRight(18)) $status"
    if ($kv.Value -eq 'FAILED') { $failCount++ }
}

if ($failCount -gt 0) {
    Write-Log -Level ERROR -Message "$failCount module(s) failed. Review errors above."
} else {
    Write-Log -Level INFO -Message 'All modules completed successfully.'
}

if ($script:RebootRequired) {
    Write-Log -Level WARN -Message '*** Reboot required — run: Restart-Computer ***'
}

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null

exit $failCount

#endregion
