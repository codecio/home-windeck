<#
.SYNOPSIS
    Shared utilities for SteamConsoleSetup modules.

.DESCRIPTION
    Provides logging, admin validation, dry-run wrapping, registry backup, and
    winget helpers consumed by every feature module.

MODULE CONTRACT
    Each feature module (AutoLogin, SteamInstall, etc.) must export exactly two
    public functions following these conventions:

        Enable-<Feature>  [[-User] <string>] [-Yes]
            Idempotent — safe to call when already configured.
            Wraps every mutating operation in Invoke-Action so DryRun is honored.

        Disable-<Feature> [-Yes]
            Reverts changes made by Enable-<Feature>.
            For install-only operations (Steam, NVIDIA) this MUST log an advisory
            and return without performing any action — do not silently uninstall.

    Modules MUST NOT read or write $script:* variables directly; use the helpers
    exported below.

SCRIPT-SCOPE STATE (set by Setup-SteamConsole.ps1 before dot-sourcing modules)
    $script:DryRun   [bool]   — when $true Invoke-Action skips the ScriptBlock
    $script:LogFile  [string] — absolute path to the active log file
    $script:RepoRoot [string] — absolute path to the repo root directory
#>

#region ── Internal defaults (overridden by Setup-SteamConsole.ps1) ─────────────

if (-not (Get-Variable -Scope Script -Name DryRun         -ErrorAction SilentlyContinue)) { $script:DryRun         = $false }
if (-not (Get-Variable -Scope Script -Name LogFile        -ErrorAction SilentlyContinue)) { $script:LogFile        = $null  }
if (-not (Get-Variable -Scope Script -Name RebootRequired -ErrorAction SilentlyContinue)) { $script:RebootRequired = $false }
if (-not (Get-Variable -Scope Script -Name RepoRoot       -ErrorAction SilentlyContinue)) {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
}

#endregion

#region ── Write-Log ────────────────────────────────────────────────────────────

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped, levelled message to the console and optionally to
        $script:LogFile.
    .PARAMETER Level
        INFO (default), WARN, ERROR, DRY
    .PARAMETER Message
        The text to log.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('INFO','WARN','ERROR','DRY')]
        [string] $Level = 'INFO',

        [Parameter(Mandatory, Position = 0)]
        [string] $Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red'    }
        'DRY'   { 'Cyan'   }
        default { 'White'  }
    }
    Write-Host $line -ForegroundColor $color

    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

#endregion

#region ── Assert-Administrator ─────────────────────────────────────────────────

function Assert-Administrator {
    <#
    .SYNOPSIS
        Terminates the script if not running as an administrator.
    #>
    $id  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr  = [System.Security.Principal.WindowsPrincipal]$id
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator

    if (-not $pr.IsInRole($adm)) {
        Write-Log -Level ERROR -Message 'This script must be run as Administrator. Re-launch from an elevated PowerShell prompt.'
        exit 1
    }
    Write-Log -Level INFO -Message 'Administrator check passed.'
}

#endregion

#region ── Invoke-Action ────────────────────────────────────────────────────────

function Invoke-Action {
    <#
    .SYNOPSIS
        Wraps a mutating operation. Logs "WOULD" and skips execution when
        $script:DryRun is $true.
    .PARAMETER Description
        Human-readable description of the action (used in log lines).
    .PARAMETER ScriptBlock
        The code that performs the actual change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Description,

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )

    if ($script:DryRun) {
        Write-Log -Level DRY -Message "WOULD: $Description"
        return
    }

    Write-Log -Level INFO -Message $Description
    & $ScriptBlock
}

#endregion

#region ── Backup-RegistryKey ───────────────────────────────────────────────────

function Backup-RegistryKey {
    <#
    .SYNOPSIS
        Exports a registry key to backups/<timestamp>_<Name>.reg.
    .PARAMETER Path
        Full registry path (e.g. 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon').
    .PARAMETER Name
        Short label used in the filename (e.g. 'Winlogon').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($script:DryRun) {
        Write-Log -Level DRY -Message "WOULD: Back up registry key '$Path' → backups/<timestamp>_$Name.reg"
        return
    }

    $backupDir = Join-Path $script:RepoRoot 'backups'
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

    $timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile    = Join-Path $backupDir "${timestamp}_${Name}.reg"

    # Convert PowerShell HKLM:\ path to reg.exe-compatible HKLM\ path
    $regPath = $Path -replace '^HKLM:\\', 'HKLM\' `
                     -replace '^HKCU:\\', 'HKCU\' `
                     -replace '^HKCR:\\', 'HKCR\'

    # If the registry key doesn't exist, skip the reg export (reg.exe returns an error code when key missing)
    if (-not (Test-Path $Path)) {
        Write-Log -Level WARN -Message "Registry key '$Path' not found — skipping backup."
        return
    }

    Write-Log -Level INFO -Message "Backing up '$regPath' → $outFile"
    $result = reg export "$regPath" "$outFile" /y 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Level WARN -Message "Registry export returned exit code $LASTEXITCODE. Details: $result"
    }
}

#endregion

#region ── Request-Reboot ───────────────────────────────────────────────────────

function Request-Reboot {
    <#
    .SYNOPSIS
        Flags that a reboot is required. Displayed in the final summary.
    .PARAMETER Reason
        Short explanation shown in the log.
    #>
    param([string] $Reason = 'A module requires a reboot.')
    if (-not $script:DryRun) { $script:RebootRequired = $true }
    Write-Log -Level WARN -Message "Reboot required: $Reason"
}

#endregion

#region ── Test-Winget / Invoke-Winget ──────────────────────────────────────────

function Test-Winget {
    <#
    .SYNOPSIS
        Returns $true if winget is available on PATH, $false otherwise.
    #>
    [OutputType([bool])]
    param()

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Log -Level WARN -Message 'winget not found. Install the App Installer from the Microsoft Store or https://aka.ms/getwinget and re-run.'
        return $false
    }
    return $true
}

function Invoke-Winget {
    <#
    .SYNOPSIS
        Thin wrapper around winget that normalises exit codes and injects
        --accept-source-agreements / --accept-package-agreements automatically.
    .PARAMETER Arguments
        Array of arguments forwarded to winget (do NOT include the accept flags).
    .OUTPUTS
        $true on success (exit code 0 or -1978335189 which winget uses for
        "already installed"), $false on failure.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $fullArgs = $Arguments + @('--accept-source-agreements', '--accept-package-agreements')
    Write-Log -Level INFO -Message "winget $($fullArgs -join ' ')"
    winget @fullArgs
    $ec = $LASTEXITCODE

    # -1978335189 (0x8A15002B) = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
    if ($ec -eq 0 -or $ec -eq -1978335189) { return $true }

    Write-Log -Level WARN -Message "winget exited with code $ec"
    return $false
}

#endregion
