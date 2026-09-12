#!/usr/bin/env bash

##############################
# Name: Wakanda4Ever - OpenCode Persistence Setup
# Script: setup.sh
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# Version: 0.1.0
#
# Usage:
#   1-|> bash setup.sh
#    -|> (configures OpenCode's persistent memory for the dashboard)
#
##############################
# IMPORTANT: This script is idempotent & safe to re-run: it never overwrites
#            any existing file or config setting.
##############################

#========== Wakanda4Ever ===========
#     >>> DESCRIPTION <<<
#~~~~~~~~~ (English) ~~~~~~~~~~
#
# - Creates the persistent OpenCode memory files (`user-memory.md` &
#   `conversation-log.md`) that power the Wakanda4Ever dashboard.
# - Patches `~/.config/opencode/opencode.json` so OpenCode auto-loads
#   `user-memory.md` as long-term instructions every session.
# - Runs entirely on your existing shell & `jq` — nothing else needed.
#
#=============================


#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# MOTTO: We'll always do more 😜!!!
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


# Fail fast on any error (like a good citizen 😎)
set -euo pipefail

# Reference the folder this script lives in (templates included)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The target OpenCode config folder inside the user's HOME
OPENCODE_DIR="$HOME/.config/opencode"
# The (absolute) path to the long-term memory file we want OpenCode to load
USER_MEM_FILE="$OPENCODE_DIR/user-memory.md"
CONV_LOG_FILE="$OPENCODE_DIR/conversation-log.md"
CONFIG_FILE="$OPENCODE_DIR/opencode.json"


# ======== HELPER FUNCTIONS

# pretty-print a `[ok]` status line
ok() {
  printf "\033[0;32m[ok]\033[0m %s\n" "$1"
}

# pretty-print a `[skip]` status line
skip() {
  printf "\033[0;33m[skip]\033[0m %s\n" "$1"
}

# pretty-print a `[warn]` status line
warn() {
  printf "\033[0;31m[warn]\033[0m %s\n" "$1"
}


# ======== STEP 1 - CREATE the OpenCode config folder (if needed)
mkdir -p "$OPENCODE_DIR"

# ======== STEP 2 - CREATE `user-memory.md` (only when missing)
if [[ ! -f "$USER_MEM_FILE" ]]; then
  cp "$SCRIPT_DIR/templates/user-memory.md" "$USER_MEM_FILE"
  ok "created $USER_MEM_FILE"
else
  skip "$USER_MEM_FILE already exists (leaving it untouched)"
fi

# ======== STEP 3 - CREATE `conversation-log.md` (only when missing)
if [[ ! -f "$CONV_LOG_FILE" ]]; then
  cp "$SCRIPT_DIR/templates/conversation-log.md" "$CONV_LOG_FILE"
  ok "created $CONV_LOG_FILE"
else
  skip "$CONV_LOG_FILE already exists (leaving it untouched)"
fi


# ======== STEP 4 - PATCH `opencode.json` with the user-memory instructions
# checkout to make sure `jq` is available (Omarchy ships with it already)
if ! command -v jq >/dev/null 2>&1; then
  warn "'jq' is required to patch opencode.json — please install it & re-run"
else
  # normalize `instructions` to an array (accepting string or array) and
  # append our user-memory path (removing any duplicates along the way)
  PATCHED="$(jq --arg um "$USER_MEM_FILE" '\
    (.instructions // null) as $cur | .instructions |= \
      ((if . == null then [] else (if type == "string" then [.] else . end) end) \
       + [$um] | unique)' "$CONFIG_FILE" 2>/dev/null || \
    jq -n --arg um "$USER_MEM_FILE" '{
      "$schema": "https://opencode.ai/config.json",
      "instructions": [$um]
    }')"

  # write the patched config atomically (no half-written config, ever)
  printf '%s\n' "$PATCHED" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  ok "patched $CONFIG_FILE with user-memory instructions"
fi


# ======== STEP 5 - FINAL WORD (with a little Wakanda flair ;))
printf "\n─────────  Wakanda4Ever — OpenCode is now persistent 🫶🏼\n"
printf "   · every session, OpenCode loads your \033[1muser-memory.md\033[0m\n"
printf "   · every exchange is silently appended to \033[1mconversation-log.md\033[0m\n"
printf "   · the dashboard reads both files + the opencode database\n"
printf "\nRestart \033[1mopencode\033[0m (and the \033[1momarchy shell\033[0m) to apply the changes.\n"
printf "   · shell: \033[1momarchy restart shell\033[0m\n"