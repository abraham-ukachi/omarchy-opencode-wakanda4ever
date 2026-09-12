#!/usr/bin/env python3

##############################
# Name: Wakanda4Ever - Payload Checker
# Script: check-payload.py
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# License: MIT
#
# Usage:
#   1-|> python3 check-payload.py <payload.json>
#    -|> (asserts the dashboard JSON schema; exits 0 when all checks pass)
#
##############################

import json
import sys

FAILED = []


def check(name, ok, detail=""):
    """Records one assertion result and prints a colored-ish line."""
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {name}" + (f"  ({detail})" if detail and ok else ""))
    if not ok:
        FAILED.append(name)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "payload.json"
    with open(path, encoding="utf-8") as fh:
        payload = json.load(fh)

    check("payload is an object", isinstance(payload, dict))

    # ---- required top-level keys ----
    for key in ("stats", "topics", "files", "disk", "collectedAt", "error"):
        check(f"has top-level key '{key}'", key in payload)

    # ---- stats ----
    stats = payload.get("stats", {})
    for key in ("daily", "weekly", "monthly", "total"):
        check(f"stats has '{key}'", isinstance(stats.get(key), int))
    check("stats.total counts every user message (>= 8)",
          (stats.get("total") or 0) >= 8, f"total={stats.get('total')}")

    # ---- topics ----
    topics = payload.get("topics", [])
    check("topics is a list", isinstance(topics, list))
    check("topics has exactly 3 entries", len(topics) == 3, f"len={len(topics)}")
    if topics:
        t = topics[0]
        for key in ("label", "count", "date", "quote", "quoteTrunc"):
            check(f"topic[0] has '{key}'", key in t)
        check("topic[0].count > 0", (t.get("count") or 0) > 0)
        check("topic[0].label is capitalized", t.get("label", "")[:1].isupper(),
              str(t.get("label")))

    # ---- files ----
    files = payload.get("files", [])
    check("files is a list", isinstance(files, list))
    check("files has exactly 3 entries", len(files) == 3, f"len={len(files)}")
    labels = [f.get("label") for f in files]
    for want in ("conversation log", "user memory", "opencode database"):
        check(f"files includes '{want}'", want in labels)
    check("files limits are positive",
          all((f.get("limit") or 0) > 0 for f in files))

    # ---- disk ----
    disk = payload.get("disk", {})
    check("disk.total > 0", (disk.get("total") or 0) > 0,
          f"total={disk.get('total')}")
    check("disk.free > 0", (disk.get("free") or 0) > 0)

    # ---- no errors ----
    check("error is empty", payload.get("error", "") == "")

    print()
    if FAILED:
        print(f"{len(FAILED)} check(s) FAILED: {', '.join(FAILED)}")
        sys.exit(1)
    print("all payload checks passed")


if __name__ == "__main__":
    main()