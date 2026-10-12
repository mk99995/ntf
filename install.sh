#!/usr/bin/env bash
# =============================================================================
# install.sh — interactive, flake-based NixOS installer (archinstall style)
# =============================================================================
# Run it from the NixOS minimal ISO:    bash install.sh
# Run without touching any disk:   DRY_RUN=1 bash install.sh
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Not root - restarting with sudo..."
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/nixos-installer.log"
DRY_RUN="${DRY_RUN:-0}"

for module in ui state keyboard settings disk generate run_install; do
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/$module.sh"
done

trap 'err "Failed (exit code $?) in ${BASH_SOURCE[0]##*/} line $LINENO: $BASH_COMMAND"' ERR

# ----------------------------------------------------------------------------
# The main menu
# ----------------------------------------------------------------------------
print_main_menu() {
  local user_status="${CFG_USERNAME:-not set}"
  if [[ -n $CFG_USERNAME && -n $CFG_PASSWORD ]]; then
    user_status="$CFG_USERNAME (password set)"
  fi
  local enc_status="disabled"
  if [[ $CFG_ENCRYPT == yes ]]; then
    enc_status="enabled (LUKS2)"
  fi

  menu_line 1 "Keyboard layout" "$CFG_KEYMAP"
  menu_line 2 "Locale & timezone" "$CFG_LOCALE, $CFG_TIMEZONE"
  menu_line 3 "Hostname" "$CFG_HOSTNAME"
  menu_line 4 "User account" "$user_status"
  menu_line 5 "Disk" "${CFG_DISK:-not selected}"
  menu_line 6 "Disk encryption" "$enc_status"
  menu_line 7 "Profile" "$CFG_PROFILE"
  menu_line 8 "Extra packages" "${CFG_PACKAGES:-none}"
  menu_line 9 "Nixpkgs channel" "$CFG_CHANNEL"
  menu_line 10 "Flake folder" "~/$CFG_FLAKE_NAME"
  printf '\n'
  menu_line i "Install" "(boot mode: $BOOT_MODE)"
  menu_line q "Quit" ""
  printf '\n'
}

main_menu() {
  local choice
  while true; do
    header "NixOS installer"
    print_main_menu
    read -r -p "Select an option: " choice
    case "$choice" in
    1) menu_keyboard ;;
    2) menu_locale_timezone ;;
    3) menu_hostname ;;
    4) menu_user ;;
    5) menu_disk ;;
    6) menu_encryption ;;
    7) menu_profile ;;
    8) menu_packages ;;
    9) menu_channel ;;
    10) menu_flake_dir ;;
    i | I) run_install ;;
    q | Q)
      info "Bye - nothing was installed."
      exit 0
      ;;
    *)
      warn "Unknown option '$choice'."
      sleep 1
      ;;
    esac
  done
}

# ----------------------------------------------------------------------------
# Program start
# ----------------------------------------------------------------------------
main() {
  check_dependencies
  detect_environment

  header "Welcome"
  info "This will install NixOS ${NIX_RELEASE} with a flake-based configuration."
  info "Boot mode: $BOOT_MODE    Virtualisation: $VIRT"
  printf '\n'
  info "First, choose your keyboard layout. It is used for everything that follows."
  pause

  menu_keyboard
  main_menu
}

main "$@"
