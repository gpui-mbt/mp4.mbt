#!/usr/bin/env python3
"""Deterministic upstream drift audit.

Usage:
  python3 tools/upstream-drift/audit.py OLD_DIR NEW_DIR [--json OUT]

Produces a JSON report with:
  - source_diff: changed/added/removed source files
  - contract_delta: added/removed public items (lines starting with `pub `)
and the two input directories. It never rewrites goldens; golden updates require
a review record (see docs/upstream-drift.md).
"""
import argparse
import hashlib
import json
import os
import sys


def walk(root):
    out = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith((".rs", ".mbt")):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            with open(path, "rb") as f:
                out[rel] = hashlib.sha256(f.read()).hexdigest()
    return out


def public_items(root):
    items = set()
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith((".rs", ".mbt")):
                continue
            with open(os.path.join(dirpath, name), "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    stripped = line.strip()
                    if stripped.startswith("pub "):
                        items.add(stripped)
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--json")
    args = ap.parse_args()
    if not os.path.isdir(args.old) or not os.path.isdir(args.new):
        print("audit: both arguments must be directories", file=sys.stderr)
        return 2
    old = walk(args.old)
    new = walk(args.new)
    changed = sorted(k for k in old.keys() & new.keys() if old[k] != new[k])
    added = sorted(new.keys() - old.keys())
    removed = sorted(old.keys() - new.keys())
    old_pub = public_items(args.old)
    new_pub = public_items(args.new)
    report = {
        "old": os.path.abspath(args.old),
        "new": os.path.abspath(args.new),
        "source_diff": {
            "changed": changed,
            "added": added,
            "removed": removed,
        },
        "contract_delta": {
            "added": sorted(new_pub - old_pub),
            "removed": sorted(old_pub - new_pub),
        },
    }
    text = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
