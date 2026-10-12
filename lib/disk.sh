#!/usr/bin/env bash
# =============================================================================
# lib/disk.sh — disk selection, encryption menu, partitioning, LUKS, mounting
# =============================================================================
# Resulting layout (the disk is wiped completely):
#
#   UEFI machine                          BIOS machine
#   ------------------------------        ------------------------------------
#   part 1  1 GiB  FAT32  ESP -> /boot    part 1  1 MiB  bios_boot (for GRUB)
#   part 2  rest   ext4   -> /            part 2  1 GiB  ext4 -> /boot
#                                         part 3  rest   ext4 -> /
#
# With encryption, the big "rest" partition becomes a LUKS2 container and the
# ext4 filesystem lives inside it. /boot stays unencrypted on purpose: the boot
# loader has to read the kernel from somewhere before it can ask for the
# passphrase. The passphrase prompt then happens in the initrd, using the
# keyboard layout we write into the config (see lib/generate.sh).

list_disks() {
  local dev type size model
  while read -r dev type; do
    if [[ $type != disk ]]; then continue; fi # skip to the next line
    # Do not offer the USB stick / virtual disk we booted the installer from.
    if lsblk -nr -o MOUNTPOINT "$dev" | grep -qx '/iso'; then continue; fi
    size="$(lsblk -dno SIZE "$dev" | tr -d ' ')"
    model="$(lsblk -dno MODEL "$dev" | sed 's/ *$//')"
    printf '%s  %s  %s\n' "$dev" "$size" "$model"
  done < <(lsblk -dpno NAME,TYPE -e 7,11)
}

# ----------------------------------------------------------------------------
# menu_disk
# ----------------------------------------------------------------------------
menu_disk() {
  header "Disk selection"
  local labels=()
  mapfile -t labels < <(list_disks)
  if ((${#labels[@]} == 0)); then
    warn "No suitable disk found."
    pause
    return 0
  fi
  warn "The selected disk will be COMPLETELY ERASED when you start the install."
  if pick "Available disks" "${labels[@]}"; then
    CFG_DISK="${ANSWER%% *}"
  fi
}

# ----------------------------------------------------------------------------
# menu_encryption
# ----------------------------------------------------------------------------
menu_encryption() {
  header "Disk encryption (LUKS2)"
  info "Keyboard layout used for the passphrase: $CFG_KEYMAP"
  info "The installed system loads this same layout in the initrd, so the"
  info "passphrase prompt at boot understands the keys exactly like now."
  if ((KEYMAP_APPLIED == 0)); then
    printf '\n'
    warn "Your layout is NOT active in this session (e.g. you are on SSH)."
    warn "Use only characters that are in the same place on both keyboards,"
    warn "or go to the VM window and re-select the layout in menu 1."
  fi
  printf '\n'

  if ! confirm "Encrypt the system disk?" "$([[ $CFG_ENCRYPT == yes ]] && echo y || echo n)"; then
    CFG_ENCRYPT="no"
    CFG_LUKS_PASS=""
    ok "Encryption disabled."
    sleep 1
    return 0
  fi

  local pass
  while true; do
    ask_secret "Encryption passphrase"
    pass="$ANSWER"
    if printf '%s' "$pass" | LC_ALL=C grep -q '[^ -~]'; then
      warn "The passphrase contains non-ASCII characters (like å ä ö)."
      warn "It works with our setup, but plain ASCII is the safest choice."
      if ! confirm "Use it anyway?" n; then continue; fi
    fi
    if ((${#pass} < 8)); then
      warn "That is short for an encryption passphrase (${#pass} characters)."
      if ! confirm "Use it anyway?" n; then continue; fi
    fi
    break
  done
  CFG_ENCRYPT="yes"
  CFG_LUKS_PASS="$pass"
  ok "Encryption enabled."
  sleep 1
}

# ----------------------------------------------------------------------------
# disk_part — build a partition name:  /dev/vda + 2 -> /dev/vda2
#                                      /dev/nvme0n1 + 2 -> /dev/nvme0n1p2
# ----------------------------------------------------------------------------
# Disks whose name ends in a digit (nvme0n1, mmcblk0) get a "p" before the number.
disk_part() {
  local disk="$1" number="$2"
  if [[ $disk =~ [0-9]$ ]]; then
    printf '%sp%s' "$disk" "$number"
  else
    printf '%s%s' "$disk" "$number"
  fi
}

# ----------------------------------------------------------------------------
# release_target — undo leftovers of an earlier attempt so we can start clean
# ----------------------------------------------------------------------------
release_target() {
  if mountpoint -q "$TARGET_ROOT"; then
    run umount -R "$TARGET_ROOT"
  fi
  if [[ -e /dev/mapper/cryptroot ]]; then
    run cryptsetup close cryptroot
  fi
  return 0
}

# ----------------------------------------------------------------------------
# partition_disk
# ----------------------------------------------------------------------------
partition_disk() {
  local d="$CFG_DISK"
  step "Partitioning $d ($BOOT_MODE mode)"
  release_target

  run wipefs --all --force "$d"
  run parted --script "$d" -- mklabel gpt

  if [[ $BOOT_MODE == uefi ]]; then
    run parted --script "$d" -- mkpart ESP fat32 1MiB 1025MiB
    run parted --script "$d" -- set 1 esp on
    run parted --script "$d" -- mkpart root 1025MiB 100%
    PART_BOOT="$(disk_part "$d" 1)"
    PART_ROOT="$(disk_part "$d" 2)"
  else
    run parted --script "$d" -- mkpart biosboot 1MiB 2MiB
    run parted --script "$d" -- set 1 bios_grub on
    run parted --script "$d" -- mkpart boot ext4 2MiB 1026MiB
    run parted --script "$d" -- mkpart root 1026MiB 100%
    PART_BOOT="$(disk_part "$d" 2)"
    PART_ROOT="$(disk_part "$d" 3)"
  fi

  run partprobe "$d"
  run udevadm settle
}

# ----------------------------------------------------------------------------
# format_disks — filesystems, and the LUKS container if encryption is on
# ----------------------------------------------------------------------------
format_disks() {
  step "Creating filesystems"

  if [[ $BOOT_MODE == uefi ]]; then
    run mkfs.fat -F 32 -n BOOT "$PART_BOOT"
  else
    run mkfs.ext4 -F -L boot "$PART_BOOT"
  fi

  if [[ $CFG_ENCRYPT == yes ]]; then
    info "Creating the encrypted LUKS2 container on $PART_ROOT"
    run cryptsetup luksFormat --batch-mode --type luks2 "$PART_ROOT" <<<"$CFG_LUKS_PASS"
    run cryptsetup open "$PART_ROOT" cryptroot <<<"$CFG_LUKS_PASS"
    ROOT_DEV="/dev/mapper/cryptroot"
  else
    ROOT_DEV="$PART_ROOT"
  fi

  run mkfs.ext4 -F -L nixos "$ROOT_DEV"
}

# ----------------------------------------------------------------------------
# mount_disks — mount the new system under $TARGET_ROOT (normally /mnt)
# ----------------------------------------------------------------------------
mount_disks() {
  step "Mounting filesystems"
  run mkdir -p "$TARGET_ROOT"
  run mount "$ROOT_DEV" "$TARGET_ROOT"
  run mkdir -p "$TARGET_ROOT/boot"
  if [[ $BOOT_MODE == uefi ]]; then
    run mount -o umask=077 "$PART_BOOT" "$TARGET_ROOT/boot"
  else
    run mount "$PART_BOOT" "$TARGET_ROOT/boot"
  fi
}

# ----------------------------------------------------------------------------
# uuid_of — the UUID of a device (used to reference the LUKS partition)
# ----------------------------------------------------------------------------
uuid_of() {
  if [[ ${DRY_RUN:-0} == 1 ]]; then
    printf 'DRY-RUN-UUID'
  else
    blkid -s UUID -o value "$1"
  fi
}
