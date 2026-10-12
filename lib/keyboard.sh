#!/usr/bin/env bash
# =============================================================================
# lib/keyboard.sh — menu 1: keyboard layout
# =============================================================================
# Why this comes first: everything you type afterwards (user name, passwords,
# the disk-encryption passphrase) is interpreted through the layout. We activate
# it immediately with `loadkeys`, and later write the same layout into the
# installed system so that the *boot-time* passphrase prompt uses it too.

# ----------------------------------------------------------------------------
# list_keymaps — print every console keymap name, one per line
# ----------------------------------------------------------------------------
list_keymaps() {
  local out kbd_dir

  if out="$(localectl list-keymaps 2>/dev/null)" && [[ -n $out ]]; then
    printf '%s\n' "$out"
    return 0
  fi

  if command -v loadkeys >/dev/null 2>&1; then
    kbd_dir="$(dirname "$(dirname "$(readlink -f "$(command -v loadkeys)")")")/share/keymaps"
    if [[ -d $kbd_dir ]]; then
      # find ... -printf '%f\n' prints just the file name.
      # sed -E 's/\.map(\.gz)?$//' strips ".map" or ".map.gz" from the end.
      # Pipes (|) feed the output of one command into the next one.
      find "$kbd_dir" -type f -name '*.map*' -printf '%f\n' |
        sed -E 's/\.map(\.gz)?$//' | sort -u
      return 0
    fi
  fi

  printf '%s\n' us uk de de-latin1 fr es it pt-latin1 "fi" se no dk nl pl cz ru dvorak colemak
}

# ----------------------------------------------------------------------------
# apply_keymap — activate a layout in the live environment
# ----------------------------------------------------------------------------
apply_keymap() {
  local map="$1"
  if loadkeys "$map" 2>/dev/null; then
    KEYMAP_APPLIED=1
    ok "Keyboard layout '$map' is active now."
  else
    KEYMAP_APPLIED=0
    warn "Could not activate '$map' here. Are you connected over SSH?"
    warn "Over SSH your keys are interpreted by your own computer, not the VM."
    warn "The layout will still be written to the installed system."
  fi
}

# ----------------------------------------------------------------------------
# xkb_from_keymap — best-effort translation to a graphical (XKB) layout
# ----------------------------------------------------------------------------
# Console keymaps and XKB layouts (used by GNOME/Plasma) have different names:
# the console calls Swedish "sv", XKB calls it "se". This translates the common
# cases; the result lands in the generated desktop.nix where you can fix it.
# Sets the globals XKB_LAYOUT and XKB_VARIANT.
xkb_from_keymap() {
  local km="$1"
  XKB_VARIANT=""
  # `case` compares $km against patterns, top to bottom; the first match wins.
  # `a|b)` means "a or b", `*` is a wildcard, `;;` ends each branch.
  case "$km" in
  uk) XKB_LAYOUT="gb" ;;
  dvorak)
    XKB_LAYOUT="us"
    XKB_VARIANT="dvorak"
    ;;
  colemak)
    XKB_LAYOUT="us"
    XKB_VARIANT="colemak"
    ;;
  sv | sv-*) XKB_LAYOUT="se" ;;
  jp*) XKB_LAYOUT="jp" ;;
  cz*) XKB_LAYOUT="cz" ;;
  *-nodeadkeys)
    XKB_LAYOUT="${km%%-*}"
    XKB_VARIANT="nodeadkeys"
    ;;
  # ${km%%-*} = "remove the longest tail that starts with a dash",
  # so de-latin1 becomes de and fr-latin9 becomes fr.
  *-*) XKB_LAYOUT="${km%%-*}" ;;
  *) XKB_LAYOUT="$km" ;;
  esac
}

# ----------------------------------------------------------------------------
# menu_keyboard — the menu itself
# ----------------------------------------------------------------------------
menu_keyboard() {
  local keymaps=() previous="$CFG_KEYMAP"
  # mapfile -t reads lines into an array. `< <(command)` is "process
  # substitution": it makes the command's output look like a file.
  mapfile -t keymaps < <(list_keymaps)

  while true; do
    header "Keyboard layout"
    info "Current layout: $CFG_KEYMAP"
    info "It is used for the rest of this installation, for the disk"
    info "encryption passphrase, and on the installed system (also at boot)."
    if ((KEYMAP_APPLIED == 0)); then
      warn "Not active in this session (see messages after you choose one)."
    fi

    if ! pick_filtered "Console keymaps (examples: us, uk, de, fi, fr, se, es)" "${keymaps[@]}"; then
      # The user backed out: restore what we had before.
      if [[ $CFG_KEYMAP != "$previous" ]]; then
        CFG_KEYMAP="$previous"
        apply_keymap "$CFG_KEYMAP"
      fi
      return 0
    fi

    CFG_KEYMAP="$ANSWER"
    apply_keymap "$CFG_KEYMAP"

    # Let the user check the layout with visible text before going on.
    printf '\nTest it: type some characters that are special on your layout\n'
    printf '(for example  @ $ | \\ ~ { [  and letters like å ä ö) and press Enter.\n'
    read -r -p "test> " _
    if confirm "Does it look right? Keep this layout?" y; then
      return 0
    fi
  done
}
