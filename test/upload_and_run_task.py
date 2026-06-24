import json
import logging
import os
import sys
import time
import urllib.error
import urllib.request

ROBLOX_API_KEY = os.environ["ROBLOX_API_KEY"]
ROBLOX_UNIVERSE_ID = os.environ["ROBLOX_UNIVERSE_ID"]
ROBLOX_PLACE_ID = os.environ["ROBLOX_PLACE_ID"]


def read_file(file_path):
    with open(file_path, "rb") as file:
        return file.read()


def make_request(url, headers, body=None):
    if body is not None and not isinstance(body, bytes):
        body = body.encode("utf8")
    request = urllib.request.Request(
        url, data=body, headers=headers, method="GET" if body is None else "POST"
    )
    max_attempts = 3
    for i in range(max_attempts):
        try:
            return urllib.request.urlopen(request)
        except Exception as e:
            if "certificate verify failed" in str(e):
                logging.error(
                    f"{str(e)} - you may need to install python certificates, see https://stackoverflow.com/questions/27835619/urllib-and-ssl-certificate-verify-failed-error"
                )
                sys.exit(1)
            if i == max_attempts - 1:
                raise e
            logging.info(f"Retrying error: {str(e)}")
            time.sleep(1)


def request_json(url, headers, body=None, error_label="Request"):
    try:
        response = make_request(url, headers=headers, body=body)
    except urllib.error.HTTPError as e:
        logging.error(f"{error_label} failed, response body:\n{e.fp.read()}")
        sys.exit(1)
    return json.loads(response.read())


def create_task(script, place_version):
    headers = {"Content-Type": "application/json", "x-api-key": ROBLOX_API_KEY}
    url = f"https://apis.roblox.com/cloud/v2/universes/{ROBLOX_UNIVERSE_ID}/places/{ROBLOX_PLACE_ID}/"
    if place_version:
        url += f"versions/{place_version}/"
    url += "luau-execution-session-tasks"

    body = json.dumps({"script": script})
    return request_json(url, headers, body=body, error_label="Create task request")


def poll_for_task_completion(path):
    headers = {"x-api-key": ROBLOX_API_KEY}
    url = f"https://apis.roblox.com/cloud/v2/{path}"

    logging.info("Waiting for task to finish...")

    while True:
        task = request_json(url, headers, error_label="Get task request")
        if task["state"] != "PROCESSING":
            sys.stderr.write("\n")
            sys.stderr.flush()
            return task
        sys.stderr.write(".")
        sys.stderr.flush()
        time.sleep(3)


def get_task_logs(task_path):
    headers = {"x-api-key": ROBLOX_API_KEY}
    url = f"https://apis.roblox.com/cloud/v2/{task_path}/logs"

    logs = request_json(url, headers, error_label="Get task logs request")
    messages = logs["luauExecutionSessionTaskLogs"][0]["messages"]
    return "".join(f"{m}\n" for m in messages)


def upload_place(binary_path, do_publish=False):
    print("Uploading place to Roblox")
    version_type = "Published" if do_publish else "Saved"
    headers = {
        "x-api-key": ROBLOX_API_KEY,
        "Content-Type": "application/xml",
        "Accept": "application/json",
    }
    url = f"https://apis.roblox.com/universes/v1/{ROBLOX_UNIVERSE_ID}/places/{ROBLOX_PLACE_ID}/versions?versionType={version_type}"

    body = read_file(binary_path)
    data = request_json(url, headers, body=body, error_label="Upload place request")
    return data.get("versionNumber")


def run_luau_task(place_version, script_file):
    print("Executing Luau task")
    source = read_file(script_file).decode("utf8")

    task = create_task(source, place_version)
    task = poll_for_task_completion(task["path"])
    print(get_task_logs(task["path"]))

    if task["state"] == "COMPLETE":
        print("Lua task completed successfully")
        sys.exit(0)
    else:
        print("Luau task failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    binary_file = sys.argv[1]
    script_file = sys.argv[2]

    place_version = upload_place(binary_file)
    run_luau_task(place_version, script_file)
