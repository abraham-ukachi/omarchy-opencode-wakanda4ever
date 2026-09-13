# Wakanda4Ever — Containerized plugin tests

A headless **Tier 1** test harness that exercises the plugin's *install
pipeline* — the exact scripts Omarchy runs — inside a disposable Docker
container, no desktop (or GPU) required.

![Wakanda4Ever dashboard](../.github/wakanda4ever-dashboard.png)

## Why a container?

- your system stays 100% untouched (no omarchy config, no opencode memory
  files, no plugins modified),
- every run starts from a clean slate — the definition of reproducible,
- it teaches the real install flow *without* needing a Wayland compositor.

## What gets tested

| Phase | What | Uses |
|-------|------|------|
| **A** | `manifest.json` passes the real `omarchy-plugin-validate` | REAL omarchy script |
| **B** | full `omarchy plugin add /src --enable --yes` flow (clone → validate → install → enable) | REAL `omarchy-plugin-add` etc. |
| **B2** | re-adding the plugin is refused (id collision) | REAL scripts |
| **C** | `collect.py` over a synthetic opencode database + memory files → schema-valid JSON | fixture + assertions |
| **D** | `setup.sh` idempotency + "never wipes your memory files" guard | bash assertions |
| **E** | `collect.py` tolerates a completely empty workspace | assert graceful payload |

Only `omarchy-shell` is faked (`docker-tests/fakes/`): in production it talks
to the running Quickshell over Wayland, which doesn't exist inside this
container. Everything else is the genuine Omarchy code from your
`/usr/share/omarchy/bin`.

## Prerequisites (host)

```sh
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # then log out/in (or newgrp docker)
```

## Build & run

```sh
cd <the-plugin-repo-root>

# 1. build the image
docker build -t wakanda4ever-test -f docker-tests/Dockerfile .

# 2. stage the REAL omarchy scripts (dereferenced - /usr/share/omarchy/bin is
#    just symlinks into /usr/bin, which don't resolve inside the container)
stage="${TMPDIR:-/tmp}/omarchy-real"
rm -rf "$stage" && mkdir -p "$stage"
cp -L /usr/share/omarchy/bin/* "$stage/"

# 3. run it, mounting the staged real scripts (read-only)
docker run --rm \
  -v "$stage:/tests/real:ro" \
  wakanda4ever-test
```

Watch the console: each phase prints `[PASS]` / `[FAIL]` and the container
exits non-zero if anything broke.

### Only the logic tests (no omarchy on the host)

Don't mount `/tests/real` — phases A, B and B2 get `[SKIP]`, everything else
still runs. (Mounting the raw `/usr/share/omarchy/bin` symlink dir also skips
them, with a hint that the dereferenced stage step is missing.)

## Under the hood

- `Dockerfile` — Debian bookworm-slim + `git jq bash python3`; copies the repo
  to `/src` and the harness to `/tests`.
- `fakes/omarchy-shell` — stub that answers `rescanPlugins`, `enablePlugin` and
  `listPlugins` (the last one backed by the real `omarchy-plugin-catalog`),
  logging every call to `/work/omarchy-shell.log`.
- `make-fixture.py` — creates a fake-but-real-schema `opencode.db`, plus
  `conversation-log.md` / `user-memory.md`, under a throwaway HOME.
- `check-payload.py` — asserts the `collect.py` JSON matches the dashboard
  schema (stats / sessions / files / disk / error).
- `test-plugin.sh` — the phase runner + PASS/FAIL report.

## Next steps (future)

- **Tier 2 — real GUI test:** a full dockerized Omarchy (QEMU/noVNC or a
  ~20GB prefab image) to visually verify the panel renders. Heavy; needs
  KVM/GPU passthrough on the host.
- Hook this harness into GitHub Actions so every push to this repo runs the
  whole suite automatically.