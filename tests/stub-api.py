#!/usr/bin/env python3
"""Stub X API for tests/contract.sh.

Answers the endpoints the bundle's documented invocations reach with
minimal bodies that deserialize into xr's typed responses, and appends one
JSON line per request (method, path, body) to the log file so the harness
can assert on what xr sent. Standard library only.

Usage: python3 -B tests/stub-api.py <port> <log-file>
"""

import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
LOG = sys.argv[2]

USER = {"id": "42", "username": "alice", "name": "Alice"}
LIST_RECORDS = [{"id": "1", "text": "hi", "username": "u", "name": "U"}]
MODERATORS = {"moderator_user_ids": ["7"]}
# X still answers some endpoints in its pre-rename post vocabulary.
LEGACY_POST_KEYS = {"edit_history_tweet_ids": ["777"], "public_metrics": {"retweet_count": 3}}
SINGLE_POST = re.compile(r"^/2/tweets/(\d+)(\?|$)")
BY_USERNAME = re.compile(r"^/2/users/by/username/([^/?]+)")
PAGINATION_TOKEN = re.compile(r"pagination_token=T(\d+)")

STATUS_BY_SEGMENT = {
    "ratelimit": (429, "Too Many Requests"),
    "missing": (404, "Not Found"),
    "unauthorized": (401, "Unauthorized"),
    "notenrolled": (403, "client-not-enrolled"),
    "forbidden": (403, "Forbidden"),
    "badrequest": (400, "Bad Request"),
    "unprocessable": (422, "Unprocessable Entity"),
    "servererror": (500, "Internal Server Error"),
    "teapot": (418, "I'm a teapot"),
}


class Handler(BaseHTTPRequestHandler):
    def _record(self, body):
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(json.dumps({"method": self.command, "path": self.path}) + "\n")
            if body:
                log.write("body: " + body.replace("\n", " ") + "\n")

    def _reply(self, obj, status=200):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _refusal(self):
        for segment, (status, title) in STATUS_BY_SEGMENT.items():
            if segment in self.path:
                self._reply({"title": title, "status": status, "detail": segment}, status)
                return True
        return False

    def do_GET(self):
        self._record(None)
        path = self.path
        if self._refusal():
            return None
        if path.startswith(("/2/tweets/search/stream", "/2/tweets/sample/stream", "/2/likes/firehose/stream")):
            body = b'{"data":{"id":"s1","text":"one"}}\n{"data":{"id":"s2","text":"two"}}\n'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return None
        if path.startswith("/2/users/me"):
            return self._reply({"data": USER})
        match = BY_USERNAME.match(path)
        if match:
            return self._reply({"data": {"id": "7", "username": match.group(1), "name": "U"}})
        match = SINGLE_POST.match(path)
        if match:
            return self._reply({"data": {"id": match.group(1), "text": "hi", **LEGACY_POST_KEYS}})
        return self._reply(self._list_page())

    def _list_page(self):
        # The token advances per page the way X's does, so a verb that
        # ignores --cursor is the only one that sees the same token twice.
        match = PAGINATION_TOKEN.search(self.path)
        nxt = "T%d" % (int(match.group(1)) + 1) if match else "T2"
        return {"data": LIST_RECORDS, "meta": {"result_count": 1, "next_token": nxt}}

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode(errors="replace") if length else ""
        self._record(body)
        if self._refusal():
            return None
        if self.path.startswith("/2/media/upload"):
            return self._reply({"data": {"id": "m1", "media_key": "3_m1", "expires_after_secs": 3600}})
        if self.path.startswith("/2/tweets"):
            return self._reply({"data": {"id": "777", "text": "posted", **LEGACY_POST_KEYS}}, 201)
        return self._reply(
            {
                "data": {
                    "blocking": True,
                    "muting": True,
                    "following": True,
                    "liked": True,
                    "retweeted": True,
                    "bookmarked": True,
                    "dm_conversation_id": "c1",
                    "dm_event_id": "e1",
                    **MODERATORS,
                }
            }
        )

    def do_DELETE(self):
        self._record(None)
        if self._refusal():
            return None
        return self._reply(
            {
                "data": {
                    "deleted": True,
                    "blocking": False,
                    "muting": False,
                    "following": False,
                    "liked": False,
                    "retweeted": False,
                    "bookmarked": False,
                    **MODERATORS,
                }
            }
        )

    def log_message(self, *_args):
        return


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
