# Plan: SteamConsoleSetup PowerShell Refactor

## TL;DR
Refactor the reference monolithic script into a single entry-point PowerShell script (`Setup-SteamConsole.ps1`) that dot-sources feature `.ps1` files from a `modules/` folder. Add structured logging, `-DryRun`, `-Modules` selection, `-Revert`, registry backups, and a README. Initial scope: AutoLogin, SteamInstall, SteamStartup (Task Scheduler), NvidiaDriver, DesktopFriction (lock screen). PowerTweaks and Controller helpers go on the roadmap.

## Decisions (from interview)
- **Module format**: dot-sourced `.ps1` files in `modules/` (no .psm1/.psd1)
- **Entry point**: single `Setup-SteamConsole.ps1` with switches (`-Install` default, `-Revert`, `-DryRun`, `-Modules`, `-User`, `-LogPath`, `-Yes`)
- **AutoLogin password**: prompt securely, store in registry (standard `AutoAdminLogon` pattern); README must clearly warn it is stored in plaintext under `HKLM\...\Winlogon`
- **In scope**: AutoLogin, SteamStartup, NvidiaDriver, SteamInstall, LockScreen / desktop friction
- **Deferred (roadmap)**: PowerTweaks, Controller helpers (Steam Input, DualSense)
- **Hard limits** (per user): no shell replacement, no Default User Hive edits, no forced kiosk; everything user-consent driven and reversible

## Proposed Repo Structure
```
home-windeck/
├── Setup-SteamConsole.ps1        # entry point; handles -Install/-Revert/-DryRun/-Modules
├── modules/
│   ├── Common.ps1                # logging, admin check, DryRun wrapper, backup, winget helpers
│   ├── AutoLogin.ps1             # Enable-AutoLogin / Disable-AutoLogin
│   ├── SteamInstall.ps1          # Install-Steam (revert = no-op + advisory; document why)
│   ├── SteamStartup.ps1          # Register-SteamStartupTask / Unregister-SteamStartupTask
│   ├── NvidiaDriver.ps1          # Install-NvidiaDriver (revert = no-op + advisory)
│   └── DesktopFriction.ps1       # Disable-LockScreen / Enable-LockScreen
├── backups/                      # registry .reg exports (gitignored)
├── logs/                         # transcript + structured logs (gitignored)
├── .gitignore
└── README.md
```

## Phases & Steps

### Phase 1 — Foundations (must complete first)
1. Create `.gitignore` (ignore `logs/`, `backups/`, `*.log`).
2. Create `modules/Common.ps1` providing:
   - `Write-Log` (writes to console + log file with level + timestamp; respects `-LogPath`)
   - `Assert-Administrator` (replaces `Require-Admin`)
   - `Invoke-Action -Description -ScriptBlock` — wraps mutating ops; logs "WOULD" when `$script:DryRun`
   - `Backup-RegistryKey -Path -Name` → writes to `backups/<timestamp>_<Name>.reg`
   - `Test-Winget` (returns bool; logs guidance if missing)
   - `Invoke-Winget` wrapper that handles exit codes and `--accept-*` flags
   - Script-scope vars `$script:DryRun`, `$script:LogFile`, `$script:RepoRoot`
3. Define a tiny "module contract": each feature file exposes `Enable-<Feature>` and `Disable-<Feature>` (or `Install-*` / advisory revert). Document at top of `Common.ps1`.

### Phase 2 — Feature modules (parallel, all depend on Phase 1)
4. `modules/AutoLogin.ps1`: `Enable-AutoLogin -User` (secure prompt → registry under `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`, backs up key first; sets `AutoAdminLogon`, `DefaultUserName`, `DefaultPassword`, clears `AutoLogonCount`); `Disable-AutoLogin` removes those three values. Validate the local account exists via `Get-LocalUser` before writing.
5. `modules/SteamInstall.ps1`: `Install-Steam` uses `Invoke-Winget` with id `Valve.Steam`; idempotent (skip if `winget list` shows it). Revert function logs an advisory only (do not silently uninstall Steam libraries).
6. `modules/SteamStartup.ps1`: `Register-SteamStartupTask` builds a scheduled task via `Register-ScheduledTask` (preferred over raw `schtasks`) — trigger `New-ScheduledTaskTrigger -AtLogOn -User <User>`, action `steam.exe -bigpicture -silent`, principal `LIMITED`, name `SteamConsoleSetup-BigPictureAutostart`. `Unregister-SteamStartupTask` removes by name. Locate `steam.exe` via registry (`HKLM:\SOFTWARE\WOW6432Node\Valve\Steam` → `InstallPath`) with fallback to default path.
7. `modules/NvidiaDriver.ps1`: `Install-NvidiaDriver` — confirm before running (skip prompt if `-Yes` or unattended), uses winget id `Nvidia.GeForceExperience` or `Nvidia.GraphicsDriver` (verify which is current and document choice); revert = advisory.
8. `modules/DesktopFriction.ps1`: `Disable-LockScreen` / `Enable-LockScreen` — backs up + sets `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization\NoLockScreen` DWORD. Keep room to add more (notifications, first-sign-in animation) later.

### Phase 3 — Entry script
9. `Setup-SteamConsole.ps1`:
   - Params: `[switch]$Install`, `[switch]$Revert`, `[switch]$DryRun`, `[string[]]$Modules`, `[string]$User`, `[string]$LogPath`, `[switch]$Yes`
   - Dot-source `modules/Common.ps1` then every `modules/*.ps1`
   - Initialize logging (transcript to `logs/<timestamp>.log` unless `-LogPath` given)
   - `Assert-Administrator`
   - Default `-Modules` = `AutoLogin,SteamInstall,SteamStartup,DesktopFriction` (Nvidia opt-in)
   - Validate combinations (e.g., `-Install` and `-Revert` mutually exclusive; default to `-Install`)
   - Dispatch table mapping module name → enable/disable function
   - Iterate selected modules, wrap each in try/catch so one failure does not abort the run; collect failures and exit non-zero if any
   - Print final summary (succeeded / skipped / failed / dry-run)

### Phase 4 — Documentation
10. `README.md` sections:
    - What it does + non-goals (no kiosk, no shell replace)
    - Prerequisites (Win 11, admin, winget present)
    - Usage examples: full install, module-subset, dry run, revert
    - Module-by-module reference (what it changes, what it backs up)
    - Safety notes: AutoLogin stores password in registry plaintext — recommend dedicated low-privilege local account
    - Rollback instructions (run with `-Revert`; manual fallback per module using exported `.reg` files in `backups/`)
    - Troubleshooting (winget missing, Steam path not found, task fails to trigger, NVIDIA non-NVIDIA system)
    - Roadmap (PowerTweaks, Controller helpers, optional notifications/animations tweaks)
11. Add `LICENSE` placeholder note in README (out of scope for this plan unless requested).

## Relevant Files
- `Setup-SteamConsole.ps1` — new entry point, replaces the monolithic script (reference: provided sample's `MAIN` block + `param($Revert)` flow)
- `modules/Common.ps1` — extracts and replaces `Require-Admin`, `Backup-Key`, and adds `Write-Log` + `Invoke-Action` (DryRun)
- `modules/AutoLogin.ps1` — port of `Set-AutoLogin` / `Clear-AutoLogin`
- `modules/SteamInstall.ps1` — port of `Install-Steam`
- `modules/SteamStartup.ps1` — port of `Create-SteamTask` / `Remove-SteamTask`, switched to `Register-ScheduledTask`
- `modules/NvidiaDriver.ps1` — port of `Install-Nvidia`, gated by `-Yes`
- `modules/DesktopFriction.ps1` — port of `Disable-LockScreen` / `Enable-LockScreen`
- `README.md` — new
- `.gitignore` — new

## Verification
1. **Syntax**: `Get-Command -Syntax` and `Invoke-ScriptAnalyzer` (PSScriptAnalyzer) on the entry script and every module — zero errors.
2. **Dry-run smoke test** (no admin, no changes): `pwsh -File Setup-SteamConsole.ps1 -DryRun -Modules AutoLogin,SteamStartup -User test` should log "WOULD" lines for every mutating op and make no registry/scheduler changes.
3. **DryRun + Revert**: `-Revert -DryRun` enumerates exactly the disable operations for each selected module.
4. **Module isolation**: running with `-Modules SteamStartup` only must not touch `Winlogon` or `Personalization` keys (verify via dry-run log).
5. **Manual VM test** (Windows 11 sandbox / Hyper-V): full install run, reboot, confirm autologin + Steam Big Picture launches; then `-Revert`, reboot, confirm login prompt returns and scheduled task is gone. Capture transcript from `logs/`.
6. **Idempotency**: running `-Install` twice in a row produces only "already configured / already installed" log lines on the second run, no errors.
7. **Backup artifacts**: after a real install, `backups/` contains timestamped `.reg` exports for every registry key touched; importing them by hand restores the prior state.

## Out of Scope (Roadmap)
- PowerTweaks module (high-perf power plan, disable sleep/hibernation, USB selective suspend off)
- Controller helpers (Steam Input service, DualSense pairing/profile)
- Pester unit tests
- CI (lint workflow)
- Signed script / execution policy guidance beyond a README note
- Uninstalling Steam or NVIDIA driver as part of `-Revert` (advisory only — too destructive)

## Further Considerations
1. **NVIDIA winget id**: `Nvidia.GeForceExperience` vs `Nvidia.GraphicsDriver` vs a community manifest — recommend defaulting to `Nvidia.GraphicsDriver` and documenting the alternative. Confirm during implementation.
2. **Scheduled-task action**: `steam.exe -bigpicture -silent` vs `-start steam://open/bigpicture`. Recommend the former (more reliable on cold start). OK to switch later.
3. **AutoLogin safety upgrade path**: future option to use LSA `DefaultPassword` via `Microsoft.PowerShell.Secrets` or a passwordless Microsoft account fallback — note in roadmap, not in v1.
