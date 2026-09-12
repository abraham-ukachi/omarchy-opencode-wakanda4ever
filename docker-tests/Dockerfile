# Wakanda4Ever — plugin test harness (Tier 1)
#
# A headless container that tests the plugin's *install pipeline* without a
# desktop:
#
#   - the REAL omarchy install scripts (bind-mounted in at /tests/real from
#     /usr/share/omarchy/bin) run against our plugin,
#   - only `omarchy-shell` is faked (it needs a running Quickshell + Wayland
#     display), see fakes/omarchy-shell,
#   - collect.py & setup.sh are exercised against a synthetic OpenCode
#     workspace built by make-fixture.py.
#
# Build & run (from the repo root):
#
#   docker build -t wakanda4ever-test -f docker-tests/Dockerfile .
#   docker run --rm \
#     -v /usr/share/omarchy/bin:/tests/real:ro \
#     wakanda4ever-test
#
# To skip the omarchy install-flow checks (no omarchy host available):
#
#   OMARCHY_BIN="" docker run --rm wakanda4ever-test
#
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 git jq bash coreutils ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /src /tests /work

# the plugin repo lives here inside the container
COPY . /src
# the test harness (harness script + fakes + python helpers)
COPY docker-tests/check-payload.py docker-tests/make-fixture.py /tests/
COPY docker-tests/fakes /tests/fakes
COPY docker-tests/test-plugin.sh /tests/test-plugin.sh

RUN chmod +x /tests/test-plugin.sh /tests/fakes/omarchy-shell

# /tests/real (omarchy bins) is optionally bind-mounted by the caller; the
# fake shell is always available as the very last fallback in PATH.
ENV PATH="/tests/real:/tests/fakes:/src:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /work
ENTRYPOINT ["/tests/test-plugin.sh"]