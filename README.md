# SteamConsoleSetup

Turn a Windows 11 PC into a couch-friendly Steam console experience — automatic logon, Steam Big Picture at boot, no lock screen — with a single PowerShell script that is fully reversible and leaves no surprises.

## What it does

| Module | What changes |
|---|---|
| **AutoLogin** | Sets `AutoAdminLogon` in the Winlogon registry key so your chosen local account logs in automatically on boot |
| **SteamInstall** | Installs Steam via `winget` (idempotent) |
| **SteamStartup** | Creates a Task Scheduler job that launches `steam.exe -bigpicture -silent` at logon |
| **DesktopFriction** | Sets the `NoLockScreen` Group Policy DWORD to bypass the lock screen on wake/boot |
| **NvidiaDriver** *(opt-in)* | Installs `Nvidia.GraphicsDriver` via `winget` |

Note: PowerTweaks is now included by default and will set a "never sleep / never turn off display" power profile suitable for a console-like, always-on experience. The Steam startup task is created using schtasks.exe for compatibility (Register-ScheduledTask can fail on some systems). NVIDIA driver installation remains opt-in and requires explicit confirmation via `-Yes`.

### Non-goals

- ❌ No shell replacement (no kiosk mode, no removing Explorer)
- ❌ No edits to the Default User Hive
- ❌ No forced auto-updates or telemetry changes
- ❌ Uninstalling Steam or the NVIDIA driver is **not** automated (advisory only — see [Rollback](#rollback))

Everything is user-consent driven, backed up before any registry change, and fully reversible with `-Revert`.

---

## Prerequisites

- Windows 11 (22H2 or later recommended)
- PowerShell 5.1 or PowerShell 7+ (`pwsh`)
- **Administrator** privileges (the script will refuse to run without them, except in `-DryRun` mode)
- **winget** (App Installer) present — install from the [Microsoft Store](https://apps.microsoft.com/detail/9NBLGGH4NNS1) or via `https://aka.ms/getwinget`
- A dedicated **local account** (not a Microsoft account) recommended for AutoLogin — see [Safety Notes](#safety-notes)

---

## Usage

```powershell
# 1. Open an elevated PowerShell prompt, cd to the repo, then:

# Full install with default modules (AutoLogin, SteamInstall, SteamStartup, DesktopFriction)
.\Setup-SteamConsole.ps1

# Specify the auto-login user explicitly
.\Setup-SteamConsole.ps1 -User gamer

# Dry-run — preview every action without making any changes (no elevation required)
.\Setup-SteamConsole.ps1 -DryRun

# Dry-run for a specific subset
.\Setup-SteamConsole.ps1 -DryRun -Modules AutoLogin,SteamStartup -User gamer

# Opt into NVIDIA driver (skipped by default)
.\Setup-SteamConsole.ps1 -Modules AutoLogin,SteamInstall,SteamStartup,DesktopFriction,NvidiaDriver -Yes

# Revert everything (default module set)
.\Setup-SteamConsole.ps1 -Revert

# Revert a single module
.\Setup-SteamConsole.ps1 -Revert -Modules SteamStartup

# Save log to a custom path
.\Setup-SteamConsole.ps1 -LogPath C:\Temp\setup.log
```

### All parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Install` | switch | ✅ default | Run `Enable-*` / `Install-*` for selected modules |
| `-Revert` | switch | — | Run `Disable-*` / `Uninstall-*` for selected modules (mutually exclusive with `-Install`) |
| `-DryRun` | switch | — | Log every action without making changes |
| `-Modules` | `string[]` | See below | Modules to act on |
| `-User` | `string` | `$env:USERNAME` | Local account for AutoLogin and SteamStartup |
| `-LogPath` | `string` | `logs\<timestamp>.log` | Override log file path |
| `-Yes` | switch | — | Skip confirmation prompts (e.g., NvidiaDriver) |

**Default modules** (when `-Modules` is not specified): `AutoLogin`, `SteamInstall`, `SteamStartup`, `DesktopFriction`, `PowerTweaks`

---

## Module reference

### AutoLogin

**What it changes**

Registry key: `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`

| Value | Set to |
|---|---|
| `AutoAdminLogon` | `1` |
| `DefaultUserName` | *your username* |
| `DefaultPassword` | *your password (see notes below — Autologon integration encrypts credentials when available)* |
| `AutoLogonCount` | removed (so the setting never expires) |

**What it backs up** → `backups/<timestamp>_Winlogon.reg`

**Revert**: sets `AutoAdminLogon=0` and removes `DefaultPassword` / `AutoLogonCount`.

**Autologon integration**

If `Autologon.exe` (Sysinternals) is present in `tools/` or on `PATH`, the script will prefer it and store credentials as an LSA secret instead of writing `DefaultPassword` in plaintext. To use Autologon:

- Download Autologon from https://learn.microsoft.com/en-us/sysinternals/downloads/autologon (or place `Autologon.exe` in `tools/`).
- The script will call Autologon.exe automatically when available; if it fails, it falls back to the legacy registry method.

Note: LSA-encrypted autologon credentials can still be retrieved by an administrator; this is more secure than plaintext but not foolproof.

---

### SteamInstall

**What it changes**: runs `winget install --id Valve.Steam --silent`. Idempotent.

**Revert**: advisory only — prints manual uninstall instructions without touching your game library.

---

### SteamStartup

**What it changes**: creates a Task Scheduler job named `SteamConsoleSetup-BigPictureAutostart`.

- Trigger: At logon for *User*
- Action: `steam.exe -bigpicture -silent`  
  *(more reliable on cold start than `steam://open/bigpicture`)*
- Principal: Interactive, Limited (standard user)
- Steam path: resolved from `HKLM\SOFTWARE\WOW6432Node\Valve\Steam → InstallPath`; falls back to `C:\Program Files (x86)\Steam\steam.exe`

**Revert**: removes the scheduled task by name.

---

### NvidiaDriver *(opt-in)*

**What it changes**: runs `winget install --id Nvidia.GraphicsDriver --silent`.

> **Package choice**: `Nvidia.GraphicsDriver` ships the full DCH display driver without GeForce Experience telemetry overhead. Switch to `Nvidia.GeForceExperience` in `modules\NvidiaDriver.ps1` if you want the GFE overlay.

**Revert**: advisory only — prints manual removal instructions (recommends DDU in Safe Mode for a clean uninstall).

---

### DesktopFriction

**What it changes**

Registry key: `HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization`

| Value | Set to |
|---|---|
| `NoLockScreen` | `1` (DWORD) |

**What it backs up** → `backups/<timestamp>_Personalization.reg`

**Revert**: removes `NoLockScreen`, restoring the default lock screen.

---

## Safety notes

### AutoLogin stores your password in plaintext

`DefaultPassword` is written to `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`. Any administrator on the machine can read it.

**Mitigations**:

1. **Use a dedicated local account** with no admin rights and a password you don't use anywhere else.  
   Create one: `net user gamer <password> /add`
2. Keep the machine physically secure — AutoLogin is only appropriate for a living-room console in a trusted home environment.
3. A future version may support the `Microsoft.PowerShell.SecretManagement` vault or a passwordless Microsoft account flow (see Roadmap).

---

## Rollback

### Automated revert

```powershell
# Revert all default modules
.\Setup-SteamConsole.ps1 -Revert

# Revert specific modules
.\Setup-SteamConsole.ps1 -Revert -Modules AutoLogin,DesktopFriction
```

### Manual fallback (using backup .reg files)

Every registry key is exported to `backups\` before being modified:

```powershell
# List backups
Get-ChildItem backups\

# Import a backup (restores registry to its pre-setup state)
reg import backups\20240101-120000_Winlogon.reg
reg import backups\20240101-120000_Personalization.reg
```

### Per-module manual rollback

| Module | Manual steps |
|---|---|
| **AutoLogin** | Open regedit → `HKLM\...\Winlogon` → set `AutoAdminLogon` to `0`, delete `DefaultPassword` |
| **SteamStartup** | `Unregister-ScheduledTask -TaskName SteamConsoleSetup-BigPictureAutostart -Confirm:$false` |
| **DesktopFriction** | Open regedit → `HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization` → delete `NoLockScreen` |
| **SteamInstall** | Add or Remove Programs → Steam → Uninstall |
| **NvidiaDriver** | Add or Remove Programs → NVIDIA → Uninstall (or use DDU in Safe Mode) |

---

## Troubleshooting

### winget is missing

Install the **App Installer** package:
- Microsoft Store: search for "App Installer"
- Or: `https://aka.ms/getwinget`

After installing, close and reopen your elevated PowerShell window.

### Steam path not found (SteamStartup)

If Steam was installed outside the default path, run `Install-Steam` (or install Steam manually) **before** running `SteamStartup`. The module reads the path from the registry key written by the Steam installer.

### Scheduled task fires but Steam doesn't open in Big Picture

1. Confirm Steam is installed and has been launched at least once (so it finishes its first-run setup).
2. Check Task Scheduler → `SteamConsoleSetup-BigPictureAutostart` → History tab for errors.
3. Verify the task's "Run As" user matches the AutoLogin user.

### NVIDIA: winget install fails

- Confirm you have an NVIDIA GPU: `Get-WmiObject Win32_VideoController | Select-Object Name`
- If behind a proxy or firewall, ensure `winget` can reach `winget.azureedge.net`.
- Try the alternative package: change `$_NvidiaPackageId` in `modules\NvidiaDriver.ps1` to `Nvidia.GeForceExperience` and retry.

### Script exits immediately with "must be run as Administrator"

Right-click PowerShell → **Run as Administrator**, `cd` to the repo folder, then run the script. Or use `-DryRun` to preview without elevation.


### Post-reboot verification

After a reboot, run these commands to verify AutoLogin, the scheduled task, and power state:

```powershell
Get-ScheduledTask -TaskName 'SteamConsoleSetup-BigPictureAutostart' | Format-List *
schtasks /Query /TN "SteamConsoleSetup-BigPictureAutostart" /XML
schtasks /Run /TN "SteamConsoleSetup-BigPictureAutostart"
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
powercfg /L
powercfg /query
```

---

## Roadmap

- **PowerTweaks module** — high-performance power plan, disable sleep/hibernation, USB selective suspend off
- **Controller helpers** — Steam Input service, DualSense Bluetooth pairing profile
- **Pester unit tests**
- **CI lint workflow** (PSScriptAnalyzer on push)
- **Signed script** + execution policy guidance
- **AutoLogin safety upgrade** — `Microsoft.PowerShell.SecretManagement` vault or passwordless Microsoft account flow

---

## License

No license file is included in this release. Refer to the repository owner for usage terms.
