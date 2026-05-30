import json
import os
import urllib.request

JSON_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"
TARGET_FILE = "src/Type/Instances.luau"


def main():
    print(f"Fetching API Dump from: {JSON_URL}")

    try:
        with urllib.request.urlopen(JSON_URL) as response:
            json_content = response.read()
            api_dump = json.loads(json_content)
    except Exception as e:
        print(f"Failed to download or parse JSON: {e}")
        exit(1)

    class_names = set()

    for class_data in api_dump.get("Classes", []):
        name = class_data.get("Name")
        tags = class_data.get("Tags", [])

        if "NotCreatable" not in tags and "Service" not in tags:
            class_names.add(name)

    if not class_names:
        print("No creatable classes found.")
        exit(1)

    sorted_classes = sorted(class_names)

    file_content = "export type Creatable = {\n"
    for name in sorted_classes:
        file_content += f"\t{name}: {name},\n"
    file_content += "}\n\nreturn nil\n"

    os.makedirs(os.path.dirname(TARGET_FILE), exist_ok=True)

    with open(TARGET_FILE, "w", encoding="utf-8") as f:
        f.write(file_content)

    print(f"Successfully wrote {len(class_names)} creatable classes to {TARGET_FILE}")


if __name__ == "__main__":
    main()
