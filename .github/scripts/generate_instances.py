import json
import urllib.request

JSON_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"
TARGET_FILE = "src/Type/Instances.luau"


def fields(names):
    return "".join(f"\t{name}: {name},\n" for name in names)


def main():
    print(f"Fetching API Dump from: {JSON_URL}")
    with urllib.request.urlopen(JSON_URL) as response:
        classes = json.load(response)["Classes"]

    creatable, plugin_only = [], []
    for cls in sorted(classes, key=lambda c: c["Name"]):
        bucket = (
            plugin_only
            if {"NotCreatable", "Service"}.intersection(cls.get("Tags", []))
            else creatable
        )
        bucket.append(cls["Name"])

    content = (
        f"--!nocheck\n\n"
        f"export type Creatable = {{\n{fields(creatable)}}}\n\n"
        f"export type Editable = Creatable & {{\n{fields(plugin_only)}}}\n\n"
        "return nil\n"
    )

    with open(TARGET_FILE, "w", encoding="utf-8") as f:
        f.write(content)

    total = len(creatable) + len(plugin_only)
    print(
        f"Wrote {len(creatable)} creatable and {total} editable classes ({len(plugin_only)} plugin-only) to {TARGET_FILE}"
    )


if __name__ == "__main__":
    main()
