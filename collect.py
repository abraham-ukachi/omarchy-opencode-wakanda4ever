#!/usr/bin/env python3

##############################
# Name: Wakanda4Ever - Collector
# Script: collect.py
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# Version: 0.1.2
#
# Usage:
#   1-|> python3 collect.py
#    -|> (prints a JSON payload to stdout for the dashboard to consume)
#
##############################
# IMPORTANT: This code is a work in progress and subject to major changes until version 1.0
##############################

#========== Wakanda4Ever ===========
#     >>> DESCRIPTION <<<
#~~~~~~~~~ (English) ~~~~~~~~~~
#
# - Reads the OpenCode local database & memory files to build a "conversation
#   dashboard" payload: total prompt counts, the latest 3 session titles (with
#   their date/time stamp), and the memory footprint of the persistent OpenCode
#   files (conversation log, user memory & database).
# - Prints a single JSON object to stdout, ready for `Main.qml` to consume.
#
#=============================


#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# MOTTO: We'll always do more 😜!!!
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


# Let's import some modules, shall we? ;)
import json
import os
import sqlite3
import sys
import time
from datetime import datetime
import calendar


# ======== CONSTANTS

# - Opencode config/data paths (relative to the user's home)
HOME = os.path.expanduser("~")
CONV_LOG = os.path.join(HOME, ".config/opencode/conversation-log.md")
USER_MEM = os.path.join(HOME, ".config/opencode/user-memory.md")
DB_FILE = os.path.join(HOME, ".local/share/opencode/opencode.db")


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
                "title": str(title).strip(),
                "date": datetime.fromtimestamp(
                    ts / 1000.0).strftime("%Y-%m-%d %H:%M"),
            })
        conn.close()
    except (sqlite3.Error, OSError):
        # NOTE: no opencode database yet? -> stay empty & graceful
        pass
    return sessions


def prompt_counts():
    """Counts all user prompts (total + daily/weekly/monthly averages).

    :returns: a { daily, weekly, monthly, total } dict
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
        # daily/weekly/monthly averages (simple rolling windows)
        daily = round(since(now_ms - 7 * 86400000) / 7)
        weekly = round(since(now_ms - 56 * 86400000) / 8)
        monthly = round(since(now_ms - 180 * 86400000) / 6)
        conn.close()
        return {"daily": daily, "weekly": weekly, "monthly": monthly,
                "total": total}
    except (sqlite3.Error, OSError):
        # NOTE: no opencode database yet (or it's locked) -> stay calm
        return {"daily": 0, "weekly": 0, "monthly": 0, "total": 0}


def build():
    """Builds & prints the complete dashboard JSON payload.

    The payload contains: `stats`, `sessions`, `files`, `disk`, `collectedAt`
    and an empty `error` field. It is written to stdout as a single line.
    """
    # ---- disk space & the (bounded) memory budget ----
    disk_total, disk_free = disk_usage()
    budget = disk_free * 0.005  # <- never let the logs eat more than 0.5% of free space

    # ---- measure the persistent OpenCode memory footprint ----
    conv_bytes = path_size(CONV_LOG)
    mem_bytes = path_size(USER_MEM)
    db_bytes = path_size(DB_FILE, DB_FILE + "-wal", DB_FILE + "-shm")
    files = [
        {
            "label": "conversation log",
            "bytes": conv_bytes,
            "limit": int(max(5 * 1024 ** 2, budget * 0.05)),
        },
        {
            "label": "user memory",
            "bytes": mem_bytes,
            "limit": int(max(256 * 1024, budget * 0.02)),
        },
        {
            "label": "opencode database",
            "bytes": db_bytes,
            "limit": int(max(50 * 1024 ** 2, budget * 0.93)),
        },
    ]
    # ---- assemble & print the final payload ----
    payload = {
        "stats": prompt_counts(),
        "sessions": recent_sessions(),
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


# ======== RUN - Wakanda4Ever Collector
if __name__ == "__main__":
    build()