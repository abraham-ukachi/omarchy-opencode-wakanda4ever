#!/usr/bin/env python3

##############################
# Name: Wakanda4Ever - Collector
# Script: collect.py
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# Version: 0.3.0
#
# Usage:
#   1-|> python3 collect.py
#    -|> (prints a JSON payload to stdout for the dashboard to consume)
#   2-|> python3 collect.py --status
#    -|> (prints a tiny AgentMemory health payload for the bar widget)
#
##############################
# IMPORTANT: This code is a work in progress and subject to major changes until version 1.0
##############################

#========== Wakanda4Ever ===========
#     >>> DESCRIPTION <<<
#~~~~~~~~~ (English) ~~~~~~~~~~
#
# - Talks to the local AgentMemory daemon (`http://127.0.0.1:3111`) over its
#   read-only REST API to build the conversation dashboard payload: store
#   counts (memories, observations, sessions, lessons, crystals), daemon
#   health/version, and the latest sessions.
# - Falls back to the OpenCode SQLite database when AgentMemory is offline, so
#   the panel always has something honest to show.
# - Also measures the memory footprint (AgentMemory store, OpenCode database &
#   memory files) and the home filesystem disk usage.
# - Prints a single JSON object to stdout, ready for `Main.qml` to consume.
#
#=============================


#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# MOTTO: We'll always do more 😜!!!
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


# Let's import some modules, shall we? ;)
import http.client
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
import calendar


# ======== CONSTANTS

# - Opencode config/data paths (relative to the user's home)
HOME = os.path.expanduser("~")
CONV_LOG = os.path.join(HOME, ".config/opencode/conversation-log.md")
USER_MEM = os.path.join(HOME, ".config/opencode/user-memory.md")
DB_FILE = os.path.join(HOME, ".local/share/opencode/opencode.db")

# - AgentMemory paths & REST endpoint (read-only usage only)
AM_SECRET_FILE = os.path.join(HOME, ".agentmemory/secret")
AM_STORE_DIR = os.path.join(HOME, ".local/share/agentmemory")
AM_URL = os.environ.get("AGENTMEMORY_URL", "http://127.0.0.1:3111").rstrip("/")
# - how long any single daemon request may take (keeps the panel snappy)
AM_TIMEOUT = 2.0
# - hard ceiling for a daemon response body (a runaway answer never wins)
AM_MAX_BODY = 2 * 1024 * 1024

# - how long a single session title may be (bounds the final JSON payload)
MAX_TITLE_LEN = 200  # <- cap any single title so it can never bloat the output
# - how long the AgentMemory headline may be
MAX_HEADLINE_LEN = 160


# ======== PUBLIC FUNCTIONS


def path_size(*paths):
    """Returns the total size (in bytes) of the given `paths`, ignoring errors.

    :param { *str } paths: one or more file paths to measure
    :returns: the summed byte size of all existing files
    :type: { int }
    """
    total = 0
    for p in paths:
        try:
            total += os.path.getsize(p)
        except OSError:
            pass  # <- skip missing/unreadable files silently
    return total


def dir_size(root):
    """Returns the total size (in bytes) of every file under `root`.

    :param { str } root: directory to walk
    :returns: the summed byte size of all readable files
    :type: { int }
    """
    total = 0
    for base, _dirs, names in os.walk(root, onerror=lambda _e: None):
        for name in names:
            try:
                total += os.path.getsize(os.path.join(base, name))
            except OSError:
                pass  # <- a file disappeared mid-walk? stay calm
    return total


def disk_usage():
    """Returns the total & free space (in bytes) of the user's home filesystem.

    :returns: (total, free) byte counts
    :type: { tuple }
    """
    try:
        st = os.statvfs(HOME)
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        return total, free
    except OSError:
        # NOTE: something weird is going on with the filesystem ;)
        #       fall back to zeros so the dashboard stays calm
        return 0, 0


def clamp_text(value, limit):
    """Returns `value` as a trimmed string, bounded to `limit` characters."""
    text = str(value or "").strip()
    if len(text) > limit:
        text = text[:max(0, limit - 1)].rstrip() + "…"
    return text


def recent_sessions(limit=3):
    """Returns the latest `limit` OpenCode session titles & timestamps.

    Only real conversations are shown: sub-agent (child) sessions and archived
    sessions are skipped, sorted by most recent activity.

    :param { int } limit: how many sessions to return (default: 3)
    :returns: a list of { title, date } session dicts, newest first
    :type: { list[dict] }
    """
    sessions = []
    try:
        # open the database in **read-only** mode (never lock/poison it)
        conn = sqlite3.connect("file:" + DB_FILE + "?mode=ro", uri=True)
        cur = conn.cursor()
        rows = cur.execute(
            "SELECT title, time_created FROM session "
            "WHERE parent_id IS NULL AND time_archived IS NULL "
            "AND TRIM(title) != '' "
            "ORDER BY time_updated DESC LIMIT ?",
            (limit,)).fetchall()
        for title, ts in rows:
            sessions.append({
                "title": clamp_text(title, MAX_TITLE_LEN),
                "date": datetime.fromtimestamp(
                    ts / 1000.0).strftime("%Y-%m-%d %H:%M"),
                "project": "",
                "observations": 0,
                "status": "",
            })
        conn.close()
    except (sqlite3.Error, OSError):
        # NOTE: no opencode database yet? -> stay empty & graceful
        pass
    return sessions


def prompt_counts():
    """Counts all user prompts (today + daily/weekly/monthly averages + total).

    :returns: a { today, daily, weekly, monthly, total } dict
    :type: { dict }
    """
    try:
        conn = sqlite3.connect("file:" + DB_FILE + "?mode=ro", uri=True)
        cur = conn.cursor()
        now_ms = int(calendar.timegm(datetime.now().timetuple()) * 1000)

        def since(min_ms):
            # count `user` messages newer than `min_ms`
            return int(cur.execute(
                "SELECT COUNT(*) FROM message "
                "WHERE json_extract(data, '$.role') = 'user' AND time_created >= ?",
                (min_ms,)).fetchone()[0] or 0)

        # total prompts ever recorded
        total = int(cur.execute(
            "SELECT COUNT(*) FROM message "
            "WHERE json_extract(data, '$.role') = 'user'").fetchone()[0] or 0)

        # prompts today (since midnight today)
        today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        today_start_ms = int(calendar.timegm(today_start.timetuple()) * 1000)
        today_count = since(today_start_ms)

        # daily/weekly/monthly averages (simple rolling windows)
        daily = round(since(now_ms - 7 * 86400000) / 7)
        weekly = round(since(now_ms - 56 * 86400000) / 8)
        monthly = round(since(now_ms - 180 * 86400000) / 6)
        conn.close()
        return {"today": today_count, "daily": daily, "weekly": weekly, "monthly": monthly,
                "total": total}
    except (sqlite3.Error, OSError):
        # NOTE: no opencode database yet (or it's locked) -> stay calm
        return {"today": 0, "daily": 0, "weekly": 0, "monthly": 0, "total": 0}


# ======== AGENTMEMORY (read-only REST client)


def am_secret():
    """Returns the AgentMemory bearer secret (or an empty string when absent)."""
    try:
        with open(AM_SECRET_FILE, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def am_get(path):
    """GETs `path` from the AgentMemory daemon & returns parsed JSON or None.

    Everything here is **read-only**: no memory is ever written, edited or
    deleted. Any network/HTTP/JSON failure simply returns `None` so the caller
    can fall back gracefully.

    :param { str } path: absolute daemon path (e.g. `/agentmemory/counts`)
    :returns: the decoded JSON body, or None on any failure
    :type: { dict | list | None }
    """
    secret = am_secret()
    if not secret:
        return None  # <- no secret yet: treat the daemon as unavailable
    req = urllib.request.Request(
        AM_URL + path,
        headers={
            "Authorization": "Bearer " + secret,
            "Accept": "application/json",
        })
    try:
        with urllib.request.urlopen(req, timeout=AM_TIMEOUT) as resp:
            body = resp.read(AM_MAX_BODY)
            return json.loads(body.decode("utf-8", "replace"))
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
        return None


def memory_counts():
    """Returns the AgentMemory store counts as a flat, integer-only dict."""
    data = am_get("/agentmemory/counts")
    counts = (data or {}).get("counts") if isinstance(data, dict) else None
    if not isinstance(counts, dict):
        return {}
    keys = ("memories", "observations", "sessions", "lessons", "crystals", "actions")
    return {k: int(counts.get(k) or 0) for k in keys}


def memory_status():
    """Returns the AgentMemory daemon status & version, or None when offline."""
    data = am_get("/agentmemory/status")
    if not isinstance(data, dict):
        return None
    service = data.get("service") if isinstance(data.get("service"), dict) else {}
    health = data.get("health") if isinstance(data.get("health"), dict) else {}
    problems = data.get("problems") if isinstance(data.get("problems"), list) else []
    version = service.get("version") or ""
    return {
        "status": str(data.get("status") or health.get("status") or "healthy"),
        "health": str(health.get("status") or ""),
        "version": str(version),
        "uptime": int(service.get("uptimeSeconds") or 0),
        "problems": len(problems),
        "headline": clamp_text(data.get("headline"), MAX_HEADLINE_LEN),
        "problem": clamp_text((problems[0] or {}).get("message") if problems else "",
                              MAX_HEADLINE_LEN),
    }


def memory_sessions(limit=3):
    """Returns the latest AgentMemory sessions, or an empty list.

    :param { int } limit: how many sessions to return (default: 3)
    :type: { list[dict] }
    """
    # ask for a few extra so blank/degenerate sessions can be skipped
    data = am_get("/agentmemory/sessions?limit=" + str(max(1, limit * 2)))
    rows = data.get("sessions") if isinstance(data, dict) else None
    if not isinstance(rows, list):
        return []

    sessions = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        title = clamp_text(row.get("summary") or row.get("firstPrompt"), MAX_TITLE_LEN)
        if not title:
            continue  # <- nothing worth showing
        sessions.append({
            "title": title,
            "date": iso_local(row.get("startedAt") or row.get("updatedAt")),
            "project": clamp_text(row.get("project"), 40),
            "observations": int(row.get("observationCount") or 0),
            "status": clamp_text(row.get("status"), 20),
        })
        if len(sessions) >= limit:
            break
    return sessions


def iso_local(value):
    """Converts an ISO-8601 UTC stamp into a local `YYYY-MM-DD HH:MM` string."""
    text = str(value or "").strip()
    if not text:
        return ""
    try:
        stamp = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return stamp.astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return text[:16].replace("T", " ")


def memory_snapshot():
    """Builds the `memory` block for the dashboard payload."""
    counts = memory_counts()
    status = memory_status()
    online = status is not None or bool(counts)

    if not online:
        return {
            "online": False,
            "status": "offline",
            "health": "offline",
            "version": "",
            "uptime": 0,
            "counts": {},
            "problems": 0,
            "headline": "",
            "problem": "",
            "storeBytes": dir_size(AM_STORE_DIR),
            "checkedAt": int(time.time()),
        }

    status = status or {}
    return {
        "online": True,
        "status": status.get("status") or "healthy",
        "health": status.get("health") or "",
        "version": status.get("version") or "",
        "uptime": int(status.get("uptime") or 0),
        "counts": counts,
        "problems": int(status.get("problems") or 0),
        "headline": status.get("headline") or "",
        "problem": status.get("problem") or "",
        "storeBytes": dir_size(AM_STORE_DIR),
        "checkedAt": int(time.time()),
    }


def collect_sessions(limit=3):
    """Returns AgentMemory sessions when online, else OpenCode's own history."""
    sessions = memory_sessions(limit)
    return sessions if sessions else recent_sessions(limit)


def build():
    """Builds & prints the complete dashboard JSON payload.

    The payload contains: `memory`, `stats`, `sessions`, `files`, `disk`,
    `collectedAt` and an empty `error` field. It is written to stdout as a
    single line.
    """
    # ---- disk space & the (bounded) memory budget ----
    disk_total, disk_free = disk_usage()
    budget = disk_free * 0.005  # <- never let the logs eat more than 0.5% of free space

    # ---- measure the persistent memory footprint ----
    store_bytes = dir_size(AM_STORE_DIR)
    db_bytes = path_size(DB_FILE, DB_FILE + "-wal", DB_FILE + "-shm")
    mem_bytes = path_size(CONV_LOG) + path_size(USER_MEM)
    files = [
        {
            "label": "agentmemory store",
            "bytes": store_bytes,
            "limit": int(max(200 * 1024 ** 2, budget * 0.55)),
        },
        {
            "label": "opencode database",
            "bytes": db_bytes,
            "limit": int(max(50 * 1024 ** 2, budget * 0.35)),
        },
        {
            "label": "opencode memory",
            "bytes": mem_bytes,
            "limit": int(max(5 * 1024 ** 2, budget * 0.10)),
        },
    ]
    # ---- assemble & print the final payload ----
    payload = {
        "memory": memory_snapshot(),
        "stats": prompt_counts(),
        "sessions": collect_sessions(),
        "files": files,
        "disk": {
            "total": disk_total,
            "free": disk_free,
            "used": max(0, disk_total - disk_free),
        },
        "collectedAt": int(time.time()),
        "error": "",
    }
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))


def status_only():
    """Prints the tiny health payload the bar widget polls."""
    status = memory_status()
    payload = {
        "online": status is not None,
        "status": (status or {}).get("status") or "offline",
        "version": (status or {}).get("version") or "",
        "problems": (status or {}).get("problems") or 0,
        "checkedAt": int(time.time()),
    }
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))


# ======== RUN - Wakanda4Ever Collector
if __name__ == "__main__":
    if "--status" in sys.argv[1:]:
        status_only()
    else:
        build()
