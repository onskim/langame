#!/usr/bin/env python3
"""Thin PixelLab v2 REST client for this project's asset pipeline.

Why REST and not the MCP server: the MCP server is registered for the design
bucket, so a Claude Code session started in the CODE repo cannot see its tools.
Same account, same token, same generation budget — this just removes the
dependency on which directory the session happens to be running in.

The token is NEVER stored in this repo. It is read from $PIXELLAB_TOKEN, or
lifted from the MCP server registration in ~/.claude.json.

Subcommands:
  balance                       remaining generations
  post PATH JSONFILE            POST a request body, print the response
  get PATH                      GET, print the response
  poll-character ID             wait until a character's rotations are ready
  download URL DEST             fetch a result image
"""

import argparse
import json
import os
import sys
import time
import urllib.request

BASE = "https://api.pixellab.ai/v2"


def token():
    env = os.environ.get("PIXELLAB_TOKEN")
    if env:
        return env
    config = os.path.expanduser("~/.claude.json")
    if os.path.exists(config):
        with open(config, encoding="utf-8") as f:
            data = json.load(f)
        for project in data.get("projects", {}).values():
            server = project.get("mcpServers", {}).get("pixellab")
            if server:
                auth = server.get("headers", {}).get("Authorization", "")
                if auth.startswith("Bearer "):
                    return auth[len("Bearer "):]
    raise SystemExit("no PixelLab token: set $PIXELLAB_TOKEN")


def call(method, path, body=None, timeout=300):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", "Bearer " + token())
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        raise SystemExit("HTTP %d %s\n%s" % (error.code, url, detail[:4000]))


def download(url, dest):
    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    request = urllib.request.Request(url)
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = response.read()
    with open(dest, "wb") as f:
        f.write(payload)
    return len(payload)


def wait_for(check, label, timeout=1200, interval=10):
    """Poll until `check()` returns a truthy value. Generation runs 2-5 minutes."""
    started = time.time()
    while True:
        result = check()
        if result:
            return result
        waited = time.time() - started
        if waited > timeout:
            raise SystemExit("timed out after %.0fs waiting for %s" % (waited, label))
        print("  ... %s (%.0fs)" % (label, waited), flush=True)
        time.sleep(interval)


def character_ready(character_id):
    detail = call("GET", "/characters/%s" % character_id)
    status = str(detail.get("status", "")).lower()
    if status in ("failed", "error"):
        raise SystemExit("character %s failed: %s" % (character_id, json.dumps(detail)[:800]))
    return detail if status in ("completed", "complete", "done", "ready") else None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance")
    p = sub.add_parser("post")
    p.add_argument("path")
    p.add_argument("body")
    p = sub.add_parser("get")
    p.add_argument("path")
    p = sub.add_parser("poll-character")
    p.add_argument("character_id")
    p = sub.add_parser("download")
    p.add_argument("url")
    p.add_argument("dest")
    args = ap.parse_args()

    if args.cmd == "balance":
        print(json.dumps(call("GET", "/balance"), indent=1))
    elif args.cmd == "post":
        with open(args.body, encoding="utf-8") as f:
            body = json.load(f)
        print(json.dumps(call("POST", args.path, body), indent=1)[:4000])
    elif args.cmd == "get":
        print(json.dumps(call("GET", args.path), indent=1)[:8000])
    elif args.cmd == "poll-character":
        detail = wait_for(lambda: character_ready(args.character_id), "character")
        print(json.dumps(detail, indent=1)[:8000])
    elif args.cmd == "download":
        print("%d bytes -> %s" % (download(args.url, args.dest), args.dest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
