#!/usr/bin/env bash
# =============================================================================
# lib/run_install.sh — validation, review screen and the install sequence
# =============================================================================

# ----------------------------------------------------------------------------
# check_dependencies — make sure we are on the NixOS installer image
# ----------------------------------------------------------------------------
check_dependencies() {
  local missing=() cmd
  for cmd in lsblk blkid parted wipefs partprobe udevadm cryptsetup mkfs.fat mkfs.ext4 \
    mountpoint curl loadkeys nixos-version nixos-generate-config \
    nixos-install nixos-enter; do
    # `command -v X` succeeds when X is an installed program.
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if ((${#missing[@]} > 0)); then
    if [[ ${DRY_RUN:-0} == 1 ]]; then
      warn "Missing tools (ignored in dry run): ${missing[*]}"
    else
      die "Missing tools: ${missing[*]}. Run this from the NixOS installer ISO."
    fi
  fi
}

# ----------------------------------------------------------------------------
# check_network — nixos-install downloads nixpkgs, so we need internet
# ----------------------------------------------------------------------------
check_network() {
  step "Checking the internet connection"
  if curl --silent --fail --max-time 10 --output /dev/null \
    https://cache.nixos.org/nix-cache-info; then
    ok "Online."
  else
    die "Cannot reach cache.nixos.org. Check the VM's network and try again."
  fi
}

# ----------------------------------------------------------------------------
# validate_config — returns 1 (and explains) if something is still missing
# ----------------------------------------------------------------------------
validate_config() {
  local problems=()
  # `A || B` runs B only when A failed: "either the value is set, or note a problem".
  [[ -n $CFG_USERNAME ]] || problems+=("No user configured (menu 4)")
  [[ -n $CFG_PASSWORD ]] || problems+=("No user password set (menu 4)")
  [[ -n $CFG_DISK ]] || problems+=("No disk selected (menu 5)")
  if [[ -n $CFG_DISK && ! -b $CFG_DISK ]]; then # -b = is a block device
    problems+=("$CFG_DISK is not a block device")
  fi
  if [[ $CFG_ENCRYPT == yes && -z $CFG_LUKS_PASS ]]; then
    problems+=("Encryption is on but no passphrase is set (menu 6)")
  fi

  if ((${#problems[@]} > 0)); then
    warn "Cannot install yet:"
    # printf repeats its format once per argument: one bullet per problem.
    printf '  - %s\n' "${problems[@]}"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------------
# show_summary — everything that is about to happen
# ----------------------------------------------------------------------------
show_summary() {
  local enc="no"
  if [[ $CFG_ENCRYPT == yes ]]; then enc="yes (LUKS2)"; fi
  printf '  %-18s %s\n' "Keyboard layout:" "$CFG_KEYMAP"
  printf '  %-18s %s\n' "Locale:" "$CFG_LOCALE"
  printf '  %-18s %s\n' "Timezone:" "$CFG_TIMEZONE"
  printf '  %-18s %s\n' "Hostname:" "$CFG_HOSTNAME"
  printf '  %-18s %s\n' "User:" "$CFG_USERNAME (sudo)"
  printf '  %-18s %s\n' "Disk:" "$CFG_DISK  [$BOOT_MODE boot]"
  printf '  %-18s %s\n' "Encryption:" "$enc"
  printf '  %-18s %s\n' "Profile:" "$CFG_PROFILE"
  printf '  %-18s %s\n' "Extra packages:" "${CFG_PACKAGES:-none}"
  printf '  %-18s %s\n' "Channel:" "$CFG_CHANNEL"
  printf '  %-18s %s\n' "Flake folder:" "/home/$CFG_USERNAME/$CFG_FLAKE_NAME"
}

# ----------------------------------------------------------------------------
# post_install — password, git repository, file ownership
# ----------------------------------------------------------------------------
post_install() {
  step "Final touches"
  local user="$CFG_USERNAME"

  if [[ ${DRY_RUN:-0} == 1 ]]; then
    info "(dry run) would set the password for $user, create a git repo, fix ownership"
    return 0
  fi

  info "Setting the password for $user"
  printf '%s:%s\n' "$user" "$CFG_PASSWORD" | nixos-enter --root "$TARGET_ROOT" -c 'chpasswd'

  if command -v git >/dev/null 2>&1; then
    info "Creating a git repository in the flake folder"
    git -C "$FLAKE_LIVE_DIR" init --quiet
    git -C "$FLAKE_LIVE_DIR" add --all
    git -C "$FLAKE_LIVE_DIR" -c user.name="NixOS installer" -c user.email="installer@localhost" \
      commit --quiet -m "Initial system configuration"
  fi

  info "Giving $user ownership of /home/$user"
  nixos-enter --root "$TARGET_ROOT" -c "chown -R '$user:users' '/home/$user' && chmod 700 '/home/$user'"
}

# ----------------------------------------------------------------------------
# run_install — the whole sequence
# ----------------------------------------------------------------------------
run_install() {
  if ! validate_config; then
    pause
    return 0
  fi

  header "Review"
  show_summary
  printf '\n'
  warn "ALL DATA ON $CFG_DISK WILL BE DESTROYED."
  local reply
  read -r -p "Type the disk name ($CFG_DISK) to confirm, anything else cancels: " reply
  if [[ $reply != "$CFG_DISK" ]]; then
    info "Cancelled; nothing was changed."
    pause
    return 0
  fi

  : >"${LOG_FILE:-/dev/null}"
  check_network
  partition_disk
  format_disks
  mount_disks
  generate_flake

  step "Installing NixOS (this downloads a lot and takes a while)"
  export NIX_CONFIG="experimental-features = nix-command flakes"
  run nixos-install --root "$TARGET_ROOT" --no-root-passwd \
    --flake "path:$FLAKE_LIVE_DIR#$CFG_HOSTNAME"

  post_install

  step "Done"
  ok "NixOS is installed. Your flake lives in /home/$CFG_USERNAME/$CFG_FLAKE_NAME"
  if [[ $CFG_ENCRYPT == yes ]]; then
    info "At boot you will be asked for the disk passphrase (layout: $CFG_KEYMAP)."
  fi
  info "Command log: $LOG_FILE"
  if confirm "Unmount and reboot now?" y; then
    run umount -R "$TARGET_ROOT"
    if [[ ${DRY_RUN:-0} != 1 ]]; then
      info "If the VM boots the installer again, remove the iso= line from your quickemu .conf."
    fi
    run reboot
  fi
  exit 0
}
