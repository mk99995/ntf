#!/usr/bin/env bash
# =============================================================================
# lib/settings.sh — the small menus: locale/timezone, hostname, user, profile,
#                   packages, nixpkgs channel, flake folder
# =============================================================================
# Every menu_* function follows the same pattern:
#   1. print a header,
#   2. ask something (ask / pick),
#   3. validate the answer,
#   4. store it in a CFG_* variable.

# ----------------------------------------------------------------------------
# list_timezones — one name per line, e.g. Europe/Helsinki
# ----------------------------------------------------------------------------
list_timezones() {
  local out dir
  if command -v timedatectl >/dev/null 2>&1 &&
    out="$(timedatectl list-timezones 2>/dev/null)" && [[ -n $out ]]; then
    printf '%s\n' "$out"
    return 0
  fi
  for dir in /etc/zoneinfo /usr/share/zoneinfo /run/current-system/sw/share/zoneinfo; do
    if [[ -d $dir ]]; then
      find -L "$dir" -type f -printf '%P\n' |
        grep -E '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/' |
        sort -u
      printf 'UTC\n'
      return 0
    fi
  done
  printf '%s\n' UTC Europe/London Europe/Helsinki Europe/Berlin America/New_York Asia/Tokyo
}

# ----------------------------------------------------------------------------
# menu_locale_timezone
# ----------------------------------------------------------------------------
menu_locale_timezone() {
  header "Locale and timezone"

  # --- locale (language and formats) ---
  local re='^[a-z]{2,3}_[A-Z]{2}(\.UTF-8)?$' # e.g. fi_FI.UTF-8
  if pick "System language (locale)" \
    "en_US.UTF-8" "en_GB.UTF-8" "fi_FI.UTF-8" "de_DE.UTF-8" \
    "sv_SE.UTF-8" "fr_FR.UTF-8" "es_ES.UTF-8" "Other..."; then
    if [[ $ANSWER == "Other..." ]]; then
      ask "Locale (format xx_YY.UTF-8, e.g. nl_NL.UTF-8)" "$CFG_LOCALE"
      if [[ $ANSWER =~ $re ]]; then
        CFG_LOCALE="$ANSWER"
      else
        warn "'$ANSWER' does not look like a locale; keeping $CFG_LOCALE."
        pause
      fi
    else
      CFG_LOCALE="$ANSWER"
    fi
  fi

  # --- timezone ---
  local zones=()
  mapfile -t zones < <(list_timezones)
  if pick_filtered "Timezone (try typing your city, e.g. 'helsinki')" "${zones[@]}"; then
    CFG_TIMEZONE="$ANSWER"
  fi
}

# ----------------------------------------------------------------------------
# menu_hostname
# ----------------------------------------------------------------------------
menu_hostname() {
  header "Hostname"
  local re='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
  while true; do
    ask "Hostname" "$CFG_HOSTNAME"
    if [[ $ANSWER =~ $re ]]; then
      CFG_HOSTNAME="$ANSWER"
      return 0
    fi
    warn "Use lower-case letters, digits and '-' only (e.g. my-laptop)."
  done
}

# ----------------------------------------------------------------------------
# menu_user
# ----------------------------------------------------------------------------
menu_user() {
  header "User account"
  info "The new user gets administrator rights (sudo). The root account stays locked."
  info "Keyboard layout in use for typing: $CFG_KEYMAP"
  local re='^[a-z_][a-z0-9_-]{0,30}$'
  local name
  while true; do
    ask "User name" "$CFG_USERNAME"
    name="$ANSWER"
    if [[ $name == root ]]; then
      warn "Pick a normal user name, not root."
    elif [[ $name =~ $re ]]; then
      break # leave the loop
    else
      warn "Use lower-case letters, digits, '_' and '-' (must start with a letter)."
    fi
  done
  CFG_USERNAME="$name"

  ask_secret "Password for $CFG_USERNAME"
  CFG_PASSWORD="$ANSWER"
  ok "User '$CFG_USERNAME' configured."
  sleep 1
}

# ----------------------------------------------------------------------------
# menu_profile
# ----------------------------------------------------------------------------
menu_profile() {
  header "Profile"
  if pick "What should be installed?" \
    "minimal  - command line only" \
    "gnome    - GNOME desktop" \
    "plasma   - KDE Plasma desktop"; then
    # ${ANSWER%% *} = "remove everything from the first space onwards",
    # which leaves just the first word: minimal / gnome / plasma.
    CFG_PROFILE="${ANSWER%% *}"
  fi
}

# ----------------------------------------------------------------------------
# menu_packages
# ----------------------------------------------------------------------------
menu_packages() {
  header "Extra packages"
  info "Package names from https://search.nixos.org/packages, separated by spaces."
  info "Type 'none' for no extra packages. A wrong name makes the install fail,"
  info "so when in doubt keep this small; you can add more later in the flake."
  local re='^[A-Za-z0-9._+-]+$' pkg
  local pkgs=()
  ask "Packages" "${CFG_PACKAGES:-none}"
  if [[ $ANSWER == none ]]; then
    CFG_PACKAGES=""
    return 0
  fi
  # `read -ra pkgs <<<"$ANSWER"` splits the text on spaces into the array.
  # (<<< is a "here-string": it feeds the text to the command's input.)
  read -ra pkgs <<<"$ANSWER"
  for pkg in "${pkgs[@]}"; do
    if [[ ! $pkg =~ $re ]]; then
      warn "'$pkg' is not a valid package name; nothing changed."
      pause
      return 0
    fi
  done
  CFG_PACKAGES="${pkgs[*]}" # "${arr[*]}" joins elements with spaces
}

# ----------------------------------------------------------------------------
# menu_channel
# ----------------------------------------------------------------------------
menu_channel() {
  header "Nixpkgs channel"
  info "stable   = a release branch, only bug and security fixes"
  info "unstable = rolling, newest packages, occasional breakage"
  if pick "Which nixpkgs should the flake follow?" \
    "stable   - nixos-$NIX_RELEASE" \
    "unstable - nixos-unstable"; then
    CFG_CHANNEL="${ANSWER%% *}"
  fi
}

# ----------------------------------------------------------------------------
# menu_flake_dir
# ----------------------------------------------------------------------------
menu_flake_dir() {
  header "System flake folder"
  info "Your system configuration (flake.nix) is stored in your home directory."
  local user="${CFG_USERNAME:-<user>}"
  local re='^[A-Za-z0-9._-]+$'
  while true; do
    ask "Folder name inside /home/$user" "$CFG_FLAKE_NAME"
    if [[ $ANSWER =~ $re && $ANSWER != . && $ANSWER != .. ]]; then
      CFG_FLAKE_NAME="$ANSWER"
      return 0
    fi
    warn "Use letters, digits, '.', '_' and '-' only."
  done
}
