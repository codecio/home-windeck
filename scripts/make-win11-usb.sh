#!/usr/bin/env bash
#
# Create a UEFI-bootable Windows 11 install USB on macOS.
#
# Approach:
#   1. Erase target disk as GPT + single FAT32 partition (Windows UEFI boots FAT32 fine).
#   2. Mount the ISO.
#   3. Copy everything EXCEPT sources/install.wim (which is >4GB and won't fit on FAT32).
#   4. Use wimlib-imagex to split install.wim into install.swm parts <4GB.
#      Windows Setup natively understands split .swm files.
#   5. Unmount ISO and eject USB.
#
# Requirements: wimlib (brew install wimlib), admin rights (sudo for diskutil eraseDisk).
#
# Usage: ./make-win11-usb.sh <iso-path> <disk-identifier>
#   e.g. ./make-win11-usb.sh ~/Downloads/Win11_25H2_English_x64_v2.iso /dev/disk4

set -euo pipefail

ISO="${1:-}"
DISK="${2:-}"
VOL_LABEL="WIN11"

if [[ -z "$ISO" || -z "$DISK" ]]; then
  echo "Usage: $0 <iso-path> <disk-identifier e.g. /dev/disk4>" >&2
  exit 1
fi

if [[ ! -f "$ISO" ]]; then
  echo "ERROR: ISO not found: $ISO" >&2
  exit 1
fi

if ! command -v wimlib-imagex >/dev/null 2>&1; then
  echo "ERROR: wimlib-imagex not found. Install with: brew install wimlib" >&2
  exit 1
fi

if ! diskutil info "$DISK" >/dev/null 2>&1; then
  echo "ERROR: disk not found: $DISK" >&2
  exit 1
fi

# Safety: refuse internal disks.
if diskutil info "$DISK" | grep -qE 'Device Location:\s+Internal'; then
  echo "ERROR: $DISK is an internal disk. Refusing." >&2
  exit 1
fi

echo "==> Target disk:"
diskutil list "$DISK"
echo
read -r -p "This will ERASE all data on $DISK. Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

echo "==> Unmounting $DISK"
diskutil unmountDisk "$DISK"

echo "==> Erasing as FAT32 / GPT, label=$VOL_LABEL"
# GPT + FAT32 is the most reliable combo for modern Windows UEFI install media on macOS.
diskutil eraseDisk MS-DOS "$VOL_LABEL" GPT "$DISK"

USB_MNT="/Volumes/$VOL_LABEL"
[[ -d "$USB_MNT" ]] || { echo "ERROR: USB did not mount at $USB_MNT" >&2; exit 1; }

echo "==> Mounting ISO: $ISO"
ATTACH_OUT="$(hdiutil attach -nobrowse -readonly "$ISO")"
echo "$ATTACH_OUT"
ISO_MNT="$(echo "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
[[ -n "$ISO_MNT" && -d "$ISO_MNT" ]] || { echo "ERROR: failed to detect ISO mountpoint" >&2; exit 1; }
echo "    ISO mounted at: $ISO_MNT"

cleanup() {
  echo "==> Cleanup: detaching ISO"
  hdiutil detach "$ISO_MNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Copying files (excluding sources/install.wim)"
# rsync preserves layout; exclude install.wim, we'll handle it via wimlib.
# macOS stock rsync (openrsync) lacks --info=progress2; use --progress instead.
rsync -ah --progress \
  --exclude='sources/install.wim' \
  "$ISO_MNT"/ "$USB_MNT"/

INSTALL_WIM="$ISO_MNT/sources/install.wim"
if [[ -f "$INSTALL_WIM" ]]; then
  echo "==> Splitting install.wim into install.swm (3800 MB parts) on USB"
  mkdir -p "$USB_MNT/sources"
  wimlib-imagex split "$INSTALL_WIM" "$USB_MNT/sources/install.swm" 3800
else
  echo "WARN: no sources/install.wim found in ISO; nothing to split."
fi

echo "==> Flushing writes (this can take a while)"
sync

echo "==> Ejecting $DISK"
diskutil eject "$DISK"

echo "==> Done. USB is ready for Windows 11 UEFI install."
