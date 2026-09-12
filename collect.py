#!/usr/bin/env python3

##############################
# Name: Wakanda4Ever - Collector
# Script: collect.py
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# Version: 0.1.0
#
# Usage:
#   1-|> python3 collect.py
#    -|> (prints a JSON payload to stdout for the dashboard to consume)
#
#   2-|> python3 collect.py --data
#    -|> (re-runs the collection & writes the topic store, same as above)
#
##############################
# IMPORTANT: This code is a work in progress and subject to major changes until version 1.0
##############################

#========== Wakanda4Ever ===========
#     >>> DESCRIPTION <<<
#~~~~~~~~~ (English) ~~~~~~~~~~
#
# - Reads the OpenCode local database & memory files to build a "conversation
#   dashboard" payload: total prompt counts, top-3 session topics (with a
#   representative quote and a timestamp), and the memory footprint of the
#   persistent OpenCode files (conversation log, user memory & database).
# - Prints a single JSON object to stdout, ready for `Main.qml` to consume.
#
#=============================


#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# MOTTO: We'll always do more 😜!!!
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


# Let's import some modules, shall we? ;)
import json
import os
import re
import sqlite3
import sys
import time
from datetime import datetime, timedelta
import calendar
import pathlib
import collections


# ======== CONSTANTS

# - Opencode config/data paths (relative to the user's home)
HOME = os.path.expanduser("~")
CONV_LOG = os.path.join(HOME, ".config/opencode/conversation-log.md")
USER_MEM = os.path.join(HOME, ".config/opencode/user-memory.md")
DB_FILE = os.path.join(HOME, ".local/share/opencode/opencode.db")

# - Wakanda4Ever paths
PLUGIN_DIR = os.path.join(HOME, ".config/omarchy/plugins/Wakanda4Ever")
TOPICS_STORE = os.path.join(
    HOME, ".local/state/omarchy/plugins/Wakanda4Ever/topics.json")

# - Stop words & `year` words ignored while ranking conversation topics
# (so the top-3 topics actually mean something ;))
STOPWORDS = set("""
the a an and or but if then else for of in on at to from with without about
into over under by as is are was were be been being do does did will would
should could can may might must not no yes so very just really like should
could have has had having use used using one two there their they them this
that these those it its we you your our my me us his her she he what which
who whom how why when where while after before more most some any all both
each few many much such only own same too also back now want need make get
going still even though think know see way time stuff things thing work
it's thats he's she's you're we're i've don't doesn't didn't what's
""".split())

# regex that matches a standalone 4-digit year (e.g. 2026)
YEAR_RE = re.compile(r"^(19|20)[0-9]{2}$")


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


def _display_label(label):
    """Capitalizes (only!) the first letter of a topic `label`.

    :param { str } label: the raw topic label
    :returns: the pretty-printed label
    :type: { str }
    """
    return label[0].upper() + label[1:] if label else label


def _user_messages():
    """Fetches the user messages from the (read-only) OpenCode database.

    Only `text` parts of the last 90 days are kept, sorted newest-first.
    This is what powers both the topic quotes and the topic dates.

    :returns: a list of { text, ts } message dicts
    :type: { list[dict] }
    """
    msgs = []
    try:
        # open the database in **read-only** mode (never lock/poison it)
        conn = sqlite3.connect("file:" + DB_FILE + "?mode=ro", uri=True)
        cur = conn.cursor()
        # only keep messages from the last 90 days
        cutoff = int(calendar.timegm(
            (datetime.now() - timedelta(days=90)).timetuple()) * 1000)
        rows = cur.execute(
            "SELECT p.data, p.time_created FROM part p "
            "JOIN message m ON p.message_id = m.id "
            "WHERE json_extract(p.data, '$.type') = 'text' "
            "AND json_extract(m.data, '$.role') = 'user' "
            "AND p.time_created >= ?",
            (cutoff,)).fetchall()
        for data, ts in rows:
            try:
                # extract the actual text content from the JSON blob
                t = json.loads(data).get("text", "")
            except (ValueError, TypeError):
                continue
            if t:
                msgs.append({"text": str(t), "ts": int(ts)})
        conn.close()
    except (sqlite3.Error, OSError):
        # NOTE: no opencode database yet? -> stay empty & graceful
        pass
    # sort the messages newest-first
    msgs.sort(key=lambda m: -m["ts"])
    return msgs


def _corpus_text(msgs):
    """Builds one big searchable corpus out of messages & memory files.

    The corpus mixes recent user messages with the persistent memory files so
    that older (but important) topics can still surface.

    :param { list[dict] } msgs: the current user messages
    :returns: the combined plain-text corpus
    :type: { str }
    """
    texts = [m["text"] for m in msgs]
    for path in (CONV_LOG, USER_MEM):
        try:
            texts.append(pathlib.Path(path).read_text(
                encoding="utf-8", errors="replace"))
        except OSError:
            pass  # <- the memory files might not exist (yet)
    return "\n".join(texts)


def _rank_topics(corpus, limit=8):
    """Ranks the most representative topics found in a `corpus`.

    Uses a lightweight (unigrams + bigrams) TF-style heuristic with stop-word
    filtering: bigrams are heavily preferred, then single words, and finally
    the best `limit` topics are picked (never overlapping in words).

    :param { str } corpus: the text to analyze
    :param { int } limit: how many topics to return (default: 8)
    :returns: a list of (topic, score) tuples
    :type: { list[tuple] }
    """
    # tokenize the corpus into lowercase words (keeping `'` and `_`)
    tokens = re.findall(r"[a-zA-Z0-9][a-zA-Z0-9'_-]{1,}", corpus.lower())
    # drop stop-words, tiny tokens & plain years
    content = [
        w for w in tokens
        if w not in STOPWORDS and len(w) >= 3 and not YEAR_RE.match(w)
    ]
    # count unigrams (single words)
    uni = collections.Counter(content)
    # count bigrams (word pairs)
    bi = collections.Counter()
    for i in range(len(content) - 1):
        a, b = content[i], content[i + 1]
        if a in STOPWORDS or b in STOPWORDS or YEAR_RE.match(a) or YEAR_RE.match(b):
            continue
        bi[a + " " + b] += 1

    # combine the candidates (bigrams get a 1.2x boost)
    ranked = []
    for phrase, n in bi.items():
        if len(phrase) < 5 or any(c.isdigit() for c in phrase if c in "0123456789"):
            continue
        ranked.append((phrase, n * 1.2, 2))
    for word, n in uni.items():
        if len(word) < 4:
            continue
        ranked.append((word, float(n), 1))
    # sort by score (desc), then alphabetically for a stable order
    ranked.sort(key=lambda x: (-x[1], x[0]))

    # pick the best topics without word overlap
    picked = []
    joined = set()
    for phrase, score, _n in ranked:
        norm = phrase.strip().lower()
        if not norm:
            continue
        words = norm.split()
        # skip phrases that reuse an already-picked word (keeps topics distinct)
        if any(w in joined for w in words):
            continue
        if norm in joined or len(picked) >= limit:
            break
        joined.update(words)
        picked.append((norm, int(score)))
    return picked


def _quote_excerpt(text, maxlen=64):
    """Truncates a message into a short, ellipsized quote.

    Tries to cut on a word boundary (before `maxlen` characters) and appends
    `...` when the message had to be shortened.

    :param { str } text: the original message
    :param { int } maxlen: the maximum quote length (default: 64)
    :returns: (quote, truncated) where `truncated` is True when shortened
    :type: { tuple }
    """
    # collapse all whitespace into single spaces & trim
    t = re.sub(r"\s+", " ", text).strip()
    if not t:
        return "", False
    if len(t) <= maxlen:
        return t, False
    # cut on a word boundary (dropping trailing punctuation)
    tail = t[:maxlen].rstrip(" .,;:!?-")
    if not tail:
        return t[:maxlen], True
    return tail + "...", True


def _quote_for(phrase, msgs):
    """Finds the most recent user message matching a topic `phrase`.

    The matched message becomes the topic's representative quote & date.

    :param { str } phrase: the topic phrase to look for
    :param { list[dict] } msgs: the (newest-first) user messages
    :returns: (quote, date, truncated); `date` is a `YYYY-MM-DD HH:MM` string
    :type: { tuple }
    """
    p = phrase.strip().lower()
    if not p:
        return "", "", False
    words = p.split()
    # for a single word, match it as a whole word (word-boundary aware)
    pat = re.compile(
        r"(?<![a-z0-9])" + re.escape(p) + r"(?![a-z0-9])"
        if len(words) == 1 else re.escape(p))
    for m in msgs:
        if not pat.search(m["text"].lower()):
            continue
        quote, truncated = _quote_excerpt(m["text"])
        # timestamp the quote's conversation (date + 24h time)
        date = datetime.fromtimestamp(m["ts"] / 1000.0).strftime("%Y-%m-%d %H:%M")
        return quote, date, truncated
    return "", "", False


def read_topics():
    """Ranks & persists the day's topics, returning the top-3.

    Each topic stores its daily mention counts (kept for 60 days), a
    representative quote + its conversation timestamp. The final ranking is
    date-first (newest conversation) and then by mention count.

    :returns: the top-3 topics (label, count, date, quote, quoteTrunc)
    :type: { list[dict] }
    """
    today = datetime.now().strftime("%Y-%m-%d")
    # load the persistent topic store (or start fresh)
    store = {}
    try:
        store = json.loads(pathlib.Path(TOPICS_STORE).read_text(
            encoding="utf-8", errors="replace"))
        if not isinstance(store, dict):
            store = {}
    except (OSError, ValueError):
        store = {}

    # fetch the user messages for quote/timestamp matching
    msgs = _user_messages()

    # update each ranked topic's daily count + quote
    for label, score in _rank_topics(_corpus_text(msgs)):
        key = label.lower()
        entry = store.setdefault(key, {"label": _display_label(
            re.sub(r"\s{2,}", " ", label)), "days": {}})
        entry["days"][today] = max(int(entry["days"].get(today, 0)), score)
        quote, qdate, truncated = _quote_for(key, msgs)
        if quote:
            entry["quote"] = quote
            entry["quoteTrunc"] = truncated
            entry["date"] = qdate

    # drop topics that haven't been mentioned in the last 60 days
    cutoff = today
    for key in list(store.keys()):
        days = store[key].get("days", {})
        recent = {d: c for d, c in days.items()
                  if d >= (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")}
        if not recent:
            del store[key]
        else:
            store[key]["days"] = recent
            store[key]["count"] = sum(recent.values())

    # persist the updated store (best-effort, silently)
    try:
        os.makedirs(os.path.dirname(TOPICS_STORE), exist_ok=True)
        pathlib.Path(TOPICS_STORE).write_text(
            json.dumps(store, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError:
        pass  # <- never crash the dashboard over a cache hiccup

    # sort: newest conversation (date) first, then highest mention count
    ranked = sorted(
        (e for e in store.values() if e.get("count", 0) > 0),
        key=lambda e: (e.get("date") or today, e.get("count", 0)),
        reverse=True)
    return [
        {"label": e["label"], "count": e["count"],
         "date": e.get("date") or max((e.get("days") or {}).keys() or [today]),
         "quote": e.get("quote", ""),
         "quoteTrunc": bool(e.get("quoteTrunc"))}
        for e in ranked[:3]
    ]


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

    The payload contains: `stats`, `topics`, `files`, `disk`, `collectedAt`
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
        "topics": read_topics(),
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