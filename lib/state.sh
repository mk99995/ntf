#!/usr/bin/env bash
# =============================================================================
# lib/state.sh — everything the installer "remembers"
# =============================================================================

# --- values chosen by the user in the menus ----------------------------------
CFG_KEYMAP="us"          # console keymap, e.g. us, fi, de-latin1, uk
CFG_LOCALE="en_US.UTF-8" # system language
CFG_TIMEZONE="UTC"
CFG_HOSTNAME="nixos"
CFG_USERNAME=""
CFG_PASSWORD=""       # only kept in memory, never written to a file
CFG_DISK=""           # e.g. /dev/vda
CFG_ENCRYPT="no"      # "yes" or "no"
CFG_LUKS_PASS=""      # only kept in memory
CFG_PROFILE="minimal" # minimal | gnome | plasma
CFG_PACKAGES="git vim htop curl"
CFG_CHANNEL="stable"          # stable | unstable
CFG_FLAKE_NAME="nixos-config" # folder inside the user's home directory

# --- facts discovered while the script runs ----------------------------------
KEYMAP_APPLIED=0    # 1 once `loadkeys` really worked
BOOT_MODE="bios"    # uefi | bios (detected)
NIX_RELEASE="26.05" # release of the ISO we are running from (detected)
VIRT="none"         # kvm, qemu, ... (detected)

# --- where the new system is mounted -----------------------------------------
# Normally /mnt. In dry-run mode we use a scratch folder so that the generated
# flake files can still be written somewhere harmless and inspected.
TARGET_ROOT="/mnt"
if [[ ${DRY_RUN:-0} == 1 ]]; then
  TARGET_ROOT="${DRY_RUN_DIR:-/tmp/nixos-installer-dryrun}"
fi

# --- partition names, filled in by lib/disk.sh --------------------------------
PART_BOOT=""
PART_ROOT=""
ROOT_DEV=""

# ----------------------------------------------------------------------------
# detect_environment — look at the machine we are running on
# ----------------------------------------------------------------------------
detect_environment() {
  # A UEFI machine exposes this directory; a legacy BIOS machine does not.
  if [[ -d /sys/firmware/efi/efivars ]]; then
    BOOT_MODE="uefi"
  else
    BOOT_MODE="bios"
  fi

  # `nixos-version` prints something like "26.05.1234.abcdef (Yarara)".
  # `|| true` means "if the command fails, carry on anyway" (needed because the
  # script runs with `set -e`, which would otherwise stop on any failure).
  local version
  version="$(nixos-version 2>/dev/null || true)"
  # After a successful =~ match, the text matched by the (...) group is in
  # the array BASH_REMATCH, element 1.
  if [[ $version =~ ^([0-9]+\.[0-9]+) ]]; then
    NIX_RELEASE="${BASH_REMATCH[1]}"
  fi
  # An ISO built from unstable has "pre" in its version; no stable branch with
  # that number exists yet, so default to unstable in that case.
  if [[ $version == *pre* ]]; then
    CFG_CHANNEL="unstable"
  fi

  VIRT="$(systemd-detect-virt 2>/dev/null || true)"
  if [[ -z $VIRT ]]; then VIRT="none"; fi
}
