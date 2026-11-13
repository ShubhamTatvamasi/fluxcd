"""Seed Open WebUI tools from git into the Open WebUI database (runs as an init container).

Runs in the Open WebUI image against the same data volume before the app starts, so it needs no
API key or admin login and works on a brand-new (empty) database: importing open_webui runs the
DB migrations first. For every entry in tools.json it creates the tool (or updates its code when
the file changed), makes it readable by all users, and sets its admin valves. Valves from git
overwrite the same keys set in the UI; keys only set in the UI are kept.
"""

import asyncio
import json
import os
import sys

from open_webui.models.access_grants import AccessGrants
from open_webui.models.tools import ToolForm, ToolMeta, Tools
from open_webui.utils.plugin import load_tool_module_by_id
from open_webui.utils.tools import get_tool_specs

TOOLS_DIR = os.environ.get("TOOLS_DIR", "/tools")
# owner of seeded tools; not a real user, admins manage them and everyone can use them
OWNER = os.environ.get("TOOLS_OWNER", "system")
PUBLIC_READ = [{"principal_type": "user", "principal_id": "*", "permission": "read"}]


def read(name):
    with open(os.path.join(TOOLS_DIR, name), encoding="utf-8") as f:
        return f.read()


async def seed(t):
    tid = t["id"]
    content = read(t["file"])
    tool, frontmatter, _ = await load_tool_module_by_id(tid, content=content)
    specs = get_tool_specs(tool)
    form = ToolForm(
        id=tid,
        name=t["name"],
        content=content,
        meta=ToolMeta(
            description=t["description"],
            manifest=frontmatter,
            has_user_valves=hasattr(tool, "UserValves"),
        ),
        access_grants=PUBLIC_READ,
    )

    existing = await Tools.get_tool_by_id(tid)
    if existing is None:
        await Tools.insert_new_tool(OWNER, form, specs, module=tool)
        print(f"{tid}: created", flush=True)
    elif existing.content != content or existing.name != t["name"]:
        await Tools.update_tool_by_id(
            tid,
            {**form.model_dump(exclude={"id", "access_grants"}), "specs": specs,
             "commit_message": "seeded from git"},
            user_id=existing.user_id,
            module=tool,
        )
        print(f"{tid}: code updated", flush=True)
    else:
        print(f"{tid}: code unchanged", flush=True)

    await AccessGrants.set_access_grants("tool", tid, PUBLIC_READ)

    if t.get("valves"):
        wanted = tool.Valves(**json.loads(read(t["valves"]))).model_dump(exclude_unset=True)
        current = await Tools.get_tool_valves_by_id(tid) or {}
        await Tools.update_tool_valves_by_id(tid, {**current, **wanted})
        print(f"{tid}: valves {json.dumps(wanted)}", flush=True)


async def main():
    failed = 0
    for t in json.loads(read("tools.json")):
        try:
            await seed(t)
        except Exception as e:  # noqa: BLE001 - one broken tool must not keep Open WebUI down
            failed += 1
            print(f"{t.get('id')}: FAILED: {e!r}", file=sys.stderr, flush=True)
    return failed


if __name__ == "__main__":
    asyncio.run(main())
    # always exit 0: a seeding error is logged but never blocks the Open WebUI pod from starting
