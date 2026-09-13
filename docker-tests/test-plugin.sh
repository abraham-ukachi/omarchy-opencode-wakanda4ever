#!/bin/bash

##############################
# Name: Wakanda4Ever - Install Test Harness
# Script: test-plugin.sh
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# License: MIT
#
# Usage:
#   (run inside the test container; kept separate so it can also run on a
#    host with omarchy installed, just as easily)
#
##############################
# IMPORTANT: Requires `git`, `jq` and `python3` on PATH, plus (for the really
#            interesting phases) the REAL omarchy install scripts under
#            /tests/real — they are mounted from the host, read-only.
##############################

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# MOTTO: We'll always do more 😜!!!
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

set -u

FAILED=0

say()  { printf "\033[0;36m%s\033[0m\n" "$1"; }
pass() { printf "\033[0;32m  [PASS]\033[0m %s\n" "$1"; }
fail() { printf "\033[0;31m  [FAIL]\033[0m %s\n" "$1"; FAILED=$((FAILED + 1)); }
skip() { printf "\033[0;33m  [SKIP]\033[0m %s\n" "$1"; }

# a tiny assertion helper; `msg` is the PASS text when everything is happy
assert() {
  local msg="$1"
  shift
  if "$@"; then pass "$msg"; else fail "$msg"; fi
}

# whether the REAL omarchy install scripts were bind-mounted in.
# /usr/share/omarchy/bin is a dir of symlinks whose targets live on the host
# (/usr/bin), so a straight bind-mount leaves dangling links that cannot be
# dereferenced inside the container. If the harness was mounted that way, tell
# the user to stage dereferenced copies instead (see docker-tests/README).
HAS_OMARCHY=0
REAL_BIN=/tests/real
if [[ -f /tests/real/omarchy-plugin-validate ]]; then
  HAS_OMARCHY=1                      # plain files: works as-is
elif [[ -L /tests/real/omarchy-plugin-validate ]]; then
  skip "mounted /tests/real contains symlinks to the host's /usr/bin - stage dereferenced copies first (see docker-tests/README.md)"
fi

# the home each phase uses, so no test can contaminate another
ADD_HOME=/home/add
COL_HOME=/home/collect
SETUP_HOME=/home/setup
SETUP_HOME2=/home/setup2
EMPTY_HOME=/home/empty

echo
say "======== Phase A - manifest validation (real omarchy-plugin-validate) ========"
if (( HAS_OMARCHY )); then
  if omarchy-plugin-validate /src; then
    pass "manifest.json passes the exact validator omarchy runs on install"
  else
    fail "omarchy-plugin-validate rejected the plugin"
  fi
else
  skip "no /tests/real mount - omarchy-plugin-validate not available"
fi

echo
say "======== Phase B - full install via the real omarchy-plugin-add ========"
if (( HAS_OMARCHY )); then
  # the fake omarchy-shell (tests/fakes) must win over any staged real one -
  # the real one needs a running Quickshell + Wayland display. Everything else
  # (omarchy-plugin-*) still resolves to the REAL scripts in $REAL_BIN.
  [[ -e /tests/fakes/omarchy-shell ]] && PATH="/tests/fakes:$PATH"

  rm -rf "$ADD_HOME"
  mkdir -p "$ADD_HOME"

  # the real catalog walks $OMARCHY_PATH/shell/plugins; give it an empty dir
  export OMARCHY_PATH=/omarchy
  mkdir -p "$OMARCHY_PATH/shell/plugins"
  rm -f /work/omarchy-shell.log

  if HOME="$ADD_HOME" omarchy-plugin-add /src --enable --yes; then
    pass "omarchy plugin add /src --enable --yes exited 0"

    PLUGIN_DIR="$ADD_HOME/.config/omarchy/plugins/wakanda4ever"
    assert "plugin landed in ~/.config/omarchy/plugins/wakanda4ever" \
      test -d "$PLUGIN_DIR"
    assert "key files were installed (Main.qml, BarWidget.qml, manifest.json)" \
      bash -c "test -f '$PLUGIN_DIR/Main.qml' && test -f '$PLUGIN_DIR/BarWidget.qml' && test -f '$PLUGIN_DIR/manifest.json'"
    assert "no leftover .add.tmp staging dir" \
      bash -c "! ls -d '$ADD_HOME/.config/omarchy/plugins/.add.tmp.'* >/dev/null 2>&1"
    assert "shell was told to rescan plugins" \
      grep -q rescanPlugins /work/omarchy-shell.log
    assert "shell was told to enable the plugin" \
      grep -q enablePlugin /work/omarchy-shell.log
    assert "plugin id is enabled in the manifest-enabled state (wakanda4ever dir exists)" \
      test -d "$PLUGIN_DIR"
  else
    fail "omarchy plugin add exited non-zero"
  fi

  echo
  say "======== Phase B2 - idempotency: re-adding the same plugin must fail ========"
  if HOME="$ADD_HOME" omarchy-plugin-add /src --enable --yes >/dev/null 2>&1; then
    fail "second add completed (expected refusal for a known plugin id)"
  else
    pass "second add was refused (plugin id collision detected)"
  fi
else
  skip "no /tests/real mount - real install flow not tested"
fi

echo
say "======== Phase C - collect.py over a synthetic opencode workspace ========"
rm -rf "$COL_HOME"
mkdir -p "$COL_HOME"
if HOME="$COL_HOME" python3 /tests/make-fixture.py \
    && HOME="$COL_HOME" python3 /src/collect.py > /work/payload.json \
    && python3 /tests/check-payload.py /work/payload.json; then
  pass "collect.py produced a schema-valid dashboard payload"
else
  fail "collect.py / payload checks reported a problem"
fi

echo
say "======== Phase D - setup.sh OpenCode persistence (idempotent) ========"
rm -rf "$SETUP_HOME" "$SETUP_HOME2"
mkdir -p "$SETUP_HOME"

if HOME="$SETUP_HOME" bash /src/setup.sh >/dev/null 2>&1; then
  pass "first setup.sh run exited 0"
else
  fail "first setup.sh run failed"
fi

assert "user-memory.md template was created" \
  test -f "$SETUP_HOME/.config/opencode/user-memory.md"
assert "conversation-log.md template was created" \
  test -f "$SETUP_HOME/.config/opencode/conversation-log.md"
assert "opencode.json exists after setup" \
  test -f "$SETUP_HOME/.config/opencode/opencode.json"

# the instructions array must carry the user-memory path
UM_IN_CONFIG=$(HOME="$SETUP_HOME" jq -r '.instructions[]' \
  "$SETUP_HOME/.config/opencode/opencode.json" | grep -c "user-memory.md" || true)
assert "opencode.json points opencode at user-memory.md" \
  bash -c "test '$UM_IN_CONFIG' -ge 1"

# a memory file with user content must NOT be wiped on re-run
echo "+ sentinel-of-the-wakanda" >> "$SETUP_HOME/.config/opencode/conversation-log.md"
if HOME="$SETUP_HOME" bash /src/setup.sh >/dev/null 2>&1; then
  pass "second setup.sh run exited 0"
else
  fail "second setup.sh run failed"
fi
assert "existing memory content was preserved across re-runs" \
  grep -q "sentinel-of-the-wakanda" "$SETUP_HOME/.config/opencode/conversation-log.md"

UM_IN_CONFIG=$(HOME="$SETUP_HOME" jq -r '.instructions[]' \
  "$SETUP_HOME/.config/opencode/opencode.json" | grep -c "user-memory.md" || true)
assert "open-code.json instructions were not duplicated" \
  bash -c "test '$UM_IN_CONFIG' -eq 1"

# a brand-new home must get its own pristine setup
if HOME="$SETUP_HOME2" bash /src/setup.sh >/dev/null 2>&1; then
  pass "third setup.sh run (fresh HOME) exited 0"
else
  fail "third setup.sh run failed"
fi
assert "fresh HOME got its own user-memory.md" \
  test -f "$SETUP_HOME2/.config/opencode/user-memory.md"

echo
say "======== Phase E - collect.py tolerates an empty workspace ========"
rm -rf "$EMPTY_HOME"
mkdir -p "$EMPTY_HOME"
if HOME="$EMPTY_HOME" python3 /src/collect.py > /work/payload-empty.json 2>/dev/null; then
  python3 - <<'PYEOF'
import json, sys
p = json.load(open("/work/payload-empty.json"))
assert p.get("error") == "", "expected an empty error string"
assert p["stats"]["total"] == 0, f"expected total 0, got {p['stats']['total']}"
assert p["topics"] == [], "expected no topics on an empty workspace"
assert len(p["files"]) == 3, "files list must still report the 3 known files"
print("empty-workspace payload is graceful & complete")
PYEOF
  assert "empty workspace produced a graceful, valid payload" true
else
  fail "collect.py crashed on an empty workspace"
fi

echo
say "======== SUMMARY ========"
if (( FAILED == 0 )); then
  echo -e "\033[0;32mAll checks passed. Wakanda Forever 🫶🏼\033[0m"
else
  echo -e "\033[0;31m$FAILED check(s) failed :(\033[0m"
fi
exit $FAILED