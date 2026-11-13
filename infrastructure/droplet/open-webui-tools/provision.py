"""Upsert Open WebUI tools from this ConfigMap through the Open WebUI API (idempotent).

For every TOOLS entry: create the tool (or update its code if the id exists), make it readable by
all users, and set its admin valves. Retries until Open WebUI answers and the API key is accepted,
so the Job can be applied before Open WebUI is up or before API keys are enabled.
"""

import json
import os
import sys
import time

import requests

BASE = os.environ.get("OPEN_WEBUI_URL", "http://open-webui.open-webui.svc.cluster.local").rstrip("/")
KEY = os.environ["OPEN_WEBUI_API_KEY"].strip()
CONF = "/config"

TOOLS = [
    {
        "id": "web_search",
        "name": "Web Search",
        "description": "Web Search using SearXNG and Scrap first N Pages",
        "file": "web_search.py",
        "valves": "valves.json",
    },
]

# public: every user can read (use) the tool; only admins/the owner can edit it
PUBLIC_READ = [{"principal_type": "user", "principal_id": "*", "permission": "read"}]

s = requests.Session()
s.headers["Authorization"] = f"Bearer {KEY}"


def call(method, path, **kw):
    r = s.request(method, BASE + path, timeout=60, **kw)
    if r.status_code >= 400:
        raise RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:500]}")
    return r.json() if r.content else None


def wait_ready():
    while True:
        try:
            if requests.get(BASE + "/health", timeout=10).ok:
                # an authenticated call fails while API keys are disabled or the key is wrong
                call("GET", "/api/v1/tools/")
                return
        except Exception as e:  # noqa: BLE001
            print(f"waiting for Open WebUI / API key: {e}", flush=True)
        time.sleep(30)


def upsert(t):
    with open(os.path.join(CONF, t["file"])) as f:
        content = f.read()
    form = {
        "id": t["id"],
        "name": t["name"],
        "content": content,
        "meta": {"description": t["description"], "manifest": {}},
        "access_grants": PUBLIC_READ,
    }
    existing = s.get(f"{BASE}/api/v1/tools/id/{t['id']}", timeout=60)
    if existing.ok and existing.json():
        if existing.json().get("content") != content:
            call("POST", f"/api/v1/tools/id/{t['id']}/update",
                 json={**form, "commit_message": "flux: open-webui-tools"})
            print(f"{t['id']}: code updated", flush=True)
        else:
            print(f"{t['id']}: code unchanged", flush=True)
    else:
        call("POST", "/api/v1/tools/create", json=form)
        print(f"{t['id']}: created", flush=True)

    call("POST", f"/api/v1/tools/id/{t['id']}/access/update", json={"access_grants": PUBLIC_READ})

    with open(os.path.join(CONF, t["valves"])) as f:
        valves = json.load(f)
    applied = call("POST", f"/api/v1/tools/id/{t['id']}/valves/update", json=valves)
    print(f"{t['id']}: valves {json.dumps(applied)}", flush=True)


def main():
    wait_ready()
    for attempt in range(1, 6):
        try:
            for t in TOOLS:
                upsert(t)
            return 0
        except Exception as e:  # noqa: BLE001
            print(f"attempt {attempt} failed: {e}", flush=True)
            time.sleep(20)
    return 1


if __name__ == "__main__":
    sys.exit(main())
