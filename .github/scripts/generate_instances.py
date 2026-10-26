import json
from pathlib import Path
import re
import urllib.request

JSON_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"
GLOBAL_TYPES_URL = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
LOCAL_GLOBAL_TYPES = Path(".sert/types/globalTypes.d.luau")
TARGET_FILE = "src/Type/Instances.luau"


def fields(names):
    return "".join(f"\t{name}: {name},\n" for name in names)


def load_declared_classes():
    if LOCAL_GLOBAL_TYPES.is_file():
        text = LOCAL_GLOBAL_TYPES.read_text(encoding="utf-8")
    else:
        print(f"Fetching globalTypes.d.luau from: {GLOBAL_TYPES_URL}")
        with urllib.request.urlopen(GLOBAL_TYPES_URL) as response:
            text = response.read().decode("utf-8")
    return set(re.findall(r"^declare class (\w+)", text, re.MULTILINE))


def main():
    print(f"Fetching API Dump from: {JSON_URL}")
    with urllib.request.urlopen(JSON_URL) as response:
        classes = json.load(response)["Classes"]

    declared = load_declared_classes()

    creatable, plugin_only, fallbacks = [], [], []
    for cls in sorted(classes, key=lambda c: c["Name"]):
        name = cls["Name"]
        bucket = (
            plugin_only
            if {"NotCreatable", "Service"}.intersection(cls.get("Tags", []))
            else creatable
        )
        bucket.append(name)
        if name not in declared:
            fallbacks.append(name)

    alias_block = "".join(f"type {name} = Instance\n" for name in fallbacks)
    if alias_block:
        alias_block += "\n"

    content = (
        f"--!strict\n\n"
        f"{alias_block}"
        f"export type Creatable = {{\n{fields(creatable)}}}\n\n"
        f"export type Editable = Creatable & {{\n{fields(plugin_only)}}}\n\n"
        "return nil\n"
    )

    with open(TARGET_FILE, "w", encoding="utf-8") as f:
        f.write(content)

    total = len(creatable) + len(plugin_only)
    print(
        f"Wrote {len(creatable)} creatable and {total} editable classes ({len(plugin_only)} plugin-only, {len(fallbacks)} fallback aliases) to {TARGET_FILE}"
    )


if __name__ == "__main__":
    main()
