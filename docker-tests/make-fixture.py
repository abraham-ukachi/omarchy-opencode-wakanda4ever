#!/usr/bin/env python3

##############################
# Name: Wakanda4Ever - Test Fixture
# Script: make-fixture.py
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# License: MIT
#
# Usage:
#   1-|> python3 make-fixture.py
#    -|> (builds a synthetic OpenCode workspace under $HOME)
#
##############################
# IMPORTANT: Writes test data ONLY; designed to mirror the real OpenCode
#            SQLite schema (see `opencode.db` on the host) so the plugin's
#            collect.py runs against something it recognizes.
##############################

import json
import os
import sqlite3
import time
import pathlib

# where OpenCode expects its persistent files (inside the test HOME)
OPENDCODE_DIR = os.path.join(os.path.expanduser("~"), ".config/opencode")
OPENDCODE_STATE = os.path.join(
    os.path.expanduser("~"), ".local/share/opencode")
DB_FILE = os.path.join(OPENDCODE_STATE, "opencode.db")

# keep the exact columns OpenCode uses (so collect.py's SQL stays untouched)
MESSAGE_SCHEMA = """
CREATE TABLE `message` (
  `id` text PRIMARY KEY,
  `session_id` text NOT NULL,
  `time_created` integer NOT NULL,
  `time_updated` integer NOT NULL,
  `data` text NOT NULL,
  CONSTRAINT `fk_message_session_id_session_id_fk`
    FOREIGN KEY (`session_id`) REFERENCES `session`(`id`) ON DELETE CASCADE
);
"""

PART_SCHEMA = """
CREATE TABLE `part` (
  `id` text PRIMARY KEY,
  `message_id` text NOT NULL,
  `session_id` text NOT NULL,
  `time_created` integer NOT NULL,
  `time_updated` integer NOT NULL,
  `data` text NOT NULL,
  CONSTRAINT `fk_part_message_id_message_id_fk`
    FOREIGN KEY (`message_id`) REFERENCES `message`(`id`) ON DELETE CASCADE
);
"""

# a session table just so the foreign keys above never complain
SESSION_SCHEMA = """
CREATE TABLE `session` (
  `id` text PRIMARY KEY,
  `directory` text NOT NULL,
  `time_created` integer NOT NULL,
  `time_updated` integer NOT NULL,
  `parent_id` text,
  `data` text NOT NULL
);
"""

# (text, days_ago) — recent enough to be counted by the 90-day windows,
# spammy enough that the topic ranking finds the expected themes.
USER_MESSAGES = [
    ("Let's set up the Wakanda4Ever omarchy plugin and run it in a docker container",
     1),
    ("Can the omarchy shell load a custom dashboard widget?",
     2),
    ("I think we should add a prompt count graph to the Wakanda dashboard",
     3),
    ("Docker makes testing the omarchy plugin install so much easier",
     4),
    ("How does collect.py read the opencode database?",
     5),
    ("Let me check the memory footprint of conversation log and user memory",
     8),
]

OLD_MESSAGES = [
    ("An older archived session about lighthouse beacons", 200),
    ("Yet another archived conversation from last year", 201),
]

ASSISTANT_MESSAGES = [
    ("Sure! Let's clone the plugin and inspect the manifest for you.",
     1),
]


def _ts(days_ago):
    """Returns a millisecond epoch timestamp `days_ago` days in the past."""
    return int((time.time() - days_ago * 86400.0) * 1000)


def _write_memory_files():
    """Creates the two persistent memory files (with a little content)."""
    os.makedirs(OPENDCODE_DIR, exist_ok=True)
    (pathlib.Path(OPENDCODE_DIR) / "conversation-log.md").write_text(
        "- 2026-09-10 Started the Wakanda4Ever docker plugin test\n",
        encoding="utf-8")
    (pathlib.Path(OPENDCODE_DIR) / "user-memory.md").write_text(
        "# User Memory\n\n- Name: Abraham\n- Likes: docker plugin testing\n",
        encoding="utf-8")


def _seed_database():
    """Creates the OpenCode DB with the real schema + synthetic rows."""
    os.makedirs(OPENDCODE_STATE, exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    cur.execute(SESSION_SCHEMA)
    cur.execute(MESSAGE_SCHEMA)
    cur.execute(PART_SCHEMA)

    cur.execute(
        "INSERT INTO session (id, directory, time_created, time_updated, data) "
        "VALUES ('s1', '/tmp/demo', 0, 0, '{}')")

    n_user, n_assistant = 0, 0

    def add_message(role, text, days_ago):
        """Inserts one message + one text part row, returns the message id."""
        nonlocal n_user, n_assistant
        mid = f"m-{role}-{n_user + n_assistant}"
        ts = _ts(days_ago)
        data = json.dumps({"sessionID": "s1", "role": role})
        cur.execute(
            "INSERT INTO message (id, session_id, time_created, time_updated, data) "
            "VALUES (?, 's1', ?, ?, ?)", (mid, ts, ts, data))
        pid = f"p-{mid}"
        part_data = json.dumps({"type": "text", "text": text})
        cur.execute(
            "INSERT INTO part (id, message_id, session_id, time_created, time_updated, data) "
            "VALUES (?, ?, 's1', ?, ?, ?)", (pid, mid, ts, ts, part_data))
        if role == "user":
            n_user += 1
        else:
            n_assistant += 1
        return mid

    # a non-text part must never show up in the topic quotes
    cur.execute(
        "INSERT INTO part (id, message_id, session_id, time_created, time_updated, data) "
        "VALUES ('p-notext', 'm-notext', 's1', 0, 0, '{\"type\": \"step-start\"}')")

    for text, days in USER_MESSAGES:
        add_message("user", text, days)
    for text, days in OLD_MESSAGES:
        add_message("user", text, days)
    for text, days in ASSISTANT_MESSAGES:
        add_message("assistant", text, days)

    conn.commit()
    conn.close()
    return n_user


def main():
    """Builds the workspace & reports how many user messages were seeded."""
    n_user = _seed_database()
    _write_memory_files()
    print(f"fixture ready: {n_user} user messages + memory files under {os.path.expanduser('~')}")


if __name__ == "__main__":
    main()