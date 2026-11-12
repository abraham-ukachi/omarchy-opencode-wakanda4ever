#!/usr/bin/env python3

##############################
# Name: Wakanda4Ever - Fake AgentMemory daemon
# Script: fake-agentmemory.py
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
# License: MIT
#
# Usage:
#   1-|> python3 fake-agentmemory.py
#    -|> (serves the read-only REST endpoints collect.py talks to)
#
##############################
# IMPORTANT: Test-only stub. It mirrors just enough of the real daemon
#            (`/agentmemory/counts`, `/status` & `/sessions`) to prove the
#            dashboard's REST path works, with the same bearer auth check.
##############################

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("FAKE_AM_PORT", "3199"))
SECRET = os.environ.get("FAKE_AM_SECRET", "wakanda-test-secret")

COUNTS = {
    "counts": {
        "memories": 12,
        "observations": 345,
        "sessions": 7,
        "lessons": 9,
        "crystals": 4,
        "actions": 0,
    },
}

STATUS = {
    "status": "healthy",
    "headline": "All systems operational.",
    "problems": [],
    "health": {"status": "healthy"},
    "service": {"version": "9.9.9", "uptimeSeconds": 7322},
}

SESSIONS = {
    "sessions": [
        {
            "summary": "Fake session one",
            "project": "demo",
            "startedAt": "2026-09-12T10:00:00.000Z",
            "observationCount": 21,
            "status": "active",
        },
        {
            "summary": "Fake session two",
            "project": "demo",
            "startedAt": "2026-09-11T09:00:00.000Z",
            "observationCount": 8,
            "status": "completed",
        },
        {
            "summary": "Fake session three",
            "project": "demo",
            "startedAt": "2026-09-10T08:00:00.000Z",
            "observationCount": 3,
            "status": "completed",
        },
    ],
}

ROUTES = {
    "/agentmemory/counts": COUNTS,
    "/agentmemory/status": STATUS,
    "/agentmemory/sessions": SESSIONS,
}


class Handler(BaseHTTPRequestHandler):
    """Answers the three read-only endpoints, behind a bearer-token check."""

    def log_message(self, *_args):
        pass  # <- keep the test output quiet

    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer " + SECRET:
            self.send_response(401)
            self.end_headers()
            return

        path = self.path.split("?", 1)[0]
        payload = ROUTES.get(path)
        if payload is None:
            self.send_response(404)
            self.end_headers()
            return

        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"fake agentmemory listening on http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
