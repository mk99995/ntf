#!/usr/bin/env bash
# =============================================================================
# lib/ui.sh — helpers for printing messages, asking questions and drawing menus
# =============================================================================

ANSWER=""

# ----------------------------------------------------------------------------
# Colours
# ----------------------------------------------------------------------------
# `[[ -t 1 ]]` is true when file descriptor 1 (standard output) is a real
# terminal. If the output goes to a file or pipe we skip the colour codes.
# $'\e[1m' is "ANSI-C quoting": inside $'...' the text \e becomes the ESC
# character, which terminals understand as the start of a colour/style code.
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'
  C_BOLD=$'\e[1m'
  C_DIM=$'\e[2m'
  C_RED=$'\e[31m'
  C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'
  C_BLUE=$'\e[34m'
  C_CYAN=$'\e[36m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi

# ----------------------------------------------------------------------------
# Messages
# ----------------------------------------------------------------------------
info() { printf '%s[info]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf '%s[ ok ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err() { printf '%s[fail]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die() {
  err "$*"
  exit 1
}

step() { printf '\n%s%s==> %s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }

header() {
  if [[ -t 1 ]]; then printf '\033[H\033[2J'; fi
  printf '%s%s== %s ==%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"
  if [[ ${DRY_RUN:-0} == 1 ]]; then
    printf '%s(DRY RUN: destructive commands are only printed, not executed)%s\n' "$C_YELLOW" "$C_RESET"
  fi
  printf '\n'
}

pause() {
  read -r -p "Press Enter to continue..." _
}

# ----------------------------------------------------------------------------
# run — execute a command, but show it first (and skip it in dry-run mode)
# ----------------------------------------------------------------------------
# Every command that changes the system goes through `run`.
# "$@" expands to ALL arguments, each one kept as a separate word, even if it
# contains spaces. That is what makes `run mkfs.ext4 -L "my disk" /dev/vda1`
# pass "my disk" as one argument. (Always write "$@" with the quotes!)
run() {
  printf '%s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
  printf '%s\n' "$*" >>"${LOG_FILE:-/dev/null}"
  if [[ ${DRY_RUN:-0} == 1 ]]; then
    return 0
  fi
  "$@"
}

# ----------------------------------------------------------------------------
# Asking questions
# ----------------------------------------------------------------------------

ask() {
  local prompt="$1" default="${2:-}" reply
  if [[ -n $default ]]; then
    read -r -p "$prompt [$default]: " reply
    ANSWER="${reply:-$default}"
  else
    read -r -p "$prompt: " reply
    ANSWER="$reply"
  fi
}

# ask_secret "Prompt"   -> ANSWER   (typing is hidden, asked twice)
#   read -s  = silent (do not echo what is typed)
#   `while true; do ... done` repeats until we `return`.
ask_secret() {
  local prompt="$1" first second
  while true; do
    read -r -s -p "$prompt: " first
    printf '\n'
    read -r -s -p "Repeat it: " second
    printf '\n'
    if [[ $first != "$second" ]]; then
      warn "The two entries do not match, try again."
      continue
    fi
    if [[ -z $first ]]; then
      warn "It must not be empty."
      continue
    fi
    ANSWER="$first"
    return 0
  done
}

confirm() {
  local question="$1" default="${2:-n}" reply hint="[y/N]"
  if [[ $default == y ]]; then hint="[Y/n]"; fi
  read -r -p "$question $hint: " reply
  reply="${reply,,}"
  if [[ -z $reply ]]; then reply="$default"; fi
  # The function's exit status is the status of its last command, so this
  # line "returns" true/false to the caller: `if confirm "..."; then`
  [[ $reply == y || $reply == yes ]]
}

# ----------------------------------------------------------------------------
# Menus
# ----------------------------------------------------------------------------

pick() {
  local title="$1"
  shift
  local items=("$@") i choice
  while true; do
    printf '\n%s%s%s\n' "$C_BOLD" "$title" "$C_RESET"
    for i in "${!items[@]}"; do
      printf '  %2d) %s\n' $((i + 1)) "${items[i]}" # $(( )) = arithmetic
    done
    printf '   0) Back\n'
    read -r -p "Select: " choice
    if [[ $choice == 0 ]]; then
      return 1
    fi
    if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#items[@]})); then
      ANSWER="${items[choice - 1]}"
      return 0
    fi
    warn "Invalid choice."
  done
}

pick_filtered() {
  local title="$1"
  shift
  local all=("$@") matches=() item filter
  while true; do
    printf '\n%s%s%s  (%d choices)\n' "$C_BOLD" "$title" "$C_RESET" "${#all[@]}"
    read -r -p "Search (part of a name, Enter = show all, 0 = back): " filter
    if [[ $filter == 0 ]]; then
      return 1
    fi
    matches=()
    for item in "${all[@]}"; do
      if [[ ${item,,} == *"${filter,,}"* ]]; then
        matches+=("$item")
      fi
    done
    if ((${#matches[@]} == 0)); then
      warn "Nothing matches '$filter'."
    elif ((${#matches[@]} > 40)); then
      warn "${#matches[@]} matches - type a few more letters to narrow it down."
    elif pick "Matches for '$filter'" "${matches[@]}"; then
      return 0
    fi
  done
}

menu_line() {
  printf '  %s%3s%s) %-24s %s%s%s\n' "$C_BOLD" "$1" "$C_RESET" "$2" "$C_GREEN" "$3" "$C_RESET"
}
