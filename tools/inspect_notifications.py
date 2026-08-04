#!/usr/bin/env python3
"""Diagnostic: show what the Notifications API returns for your notifications,
so we can see whether each one carries a comment URL to scroll to.

Usage:
    GITHUB_TOKEN=ghp_xxxx python3 tools/inspect_notifications.py
"""
import json
import os
import sys
import urllib.request

token = os.environ.get("GITHUB_TOKEN")
if not token:
    sys.exit("Set GITHUB_TOKEN=... first (a PAT with notifications+repo scopes).")

req = urllib.request.Request(
    "https://api.github.com/notifications?all=true&per_page=30",
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "GitHubNotifier-Diagnostic",
    },
)
with urllib.request.urlopen(req) as resp:
    items = json.load(resp)


def github_get(url):
    request = urllib.request.Request(url, headers=req.headers)
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except Exception as error:
        return {"_diagnostic_error": str(error)}

if not items:
    print("No notifications returned. Try triggering one (mention yourself), then rerun.")
    sys.exit(0)

print(f"{'reason':<18} {'type':<12} {'has_comment_url':<16} title")
print("-" * 80)
for n in items:
    subj = n.get("subject", {})
    reason = n.get("reason", "")
    stype = subj.get("type", "")
    has_comment = "YES" if subj.get("latest_comment_url") else "no (can't scroll)"
    title = (subj.get("title") or "")[:40]
    print(f"{reason:<18} {stype:<12} {has_comment:<16} {title}")

# Show the raw comment URLs so we can see their shape.
print("\nlatest_comment_url values:")
for n in items:
    subj = n.get("subject", {})
    if subj.get("latest_comment_url"):
        api_url = subj["latest_comment_url"]
        resolved = github_get(api_url)
        print(" ", api_url)
        print("    ->", resolved.get("html_url") or resolved.get("_diagnostic_error") or "no html_url")
