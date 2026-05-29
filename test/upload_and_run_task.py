import argparse
import base64
import hashlib
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


def makeRequest(url, headers, body=None):
    data = None
    if body is not None:
        data = body.encode("utf8")
    request = urllib.request.Request(
        url, data=data, headers=headers, method="GET" if body is None else "POST"
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
            else:
                logging.info(f"Retrying error: {str(e)}")
                time.sleep(1)


def createTask(api_key, script, universe_id, place_id, place_version):
    headers = {"Content-Type": "application/json", "x-api-key": api_key}
    data = {"script": script}
    url = f"https://apis.roblox.com/cloud/v2/universes/{universe_id}/places/{place_id}/"
    if place_version:
        url += f"versions/{place_version}/"
    url += "luau-execution-session-tasks"

    try:
        response = makeRequest(url, headers=headers, body=json.dumps(data))
    except urllib.error.HTTPError as e:
        logging.error(f"Create task request failed, response body:\n{e.fp.read()}")
        sys.exit(1)

    task = json.loads(response.read())
    return task


def pollForTaskCompletion(api_key, path):
    headers = {"x-api-key": api_key}
    url = f"https://apis.roblox.com/cloud/v2/{path}"

    logging.info("Waiting for task to finish...")

    while True:
        try:
            response = makeRequest(url, headers=headers)
        except urllib.error.HTTPError as e:
            logging.error(f"Get task request failed, response body:\n{e.fp.read()}")
            sys.exit(1)

        task = json.loads(response.read())
        if task["state"] != "PROCESSING":
            sys.stderr.write("\n")
            sys.stderr.flush()
            return task
        else:
            sys.stderr.write(".")
            sys.stderr.flush()
            time.sleep(3)


def getTaskLogs(api_key, task_path):
    headers = {"x-api-key": api_key}
    url = f"https://apis.roblox.com/cloud/v2/{task_path}/logs"

    try:
        response = makeRequest(url, headers=headers)
    except urllib.error.HTTPError as e:
        logging.error(f"Get task logs request failed, response body:\n{e.fp.read()}")
        sys.exit(1)

    logs = json.loads(response.read())
    messages = logs["luauExecutionSessionTaskLogs"][0]["messages"]
    return "".join([m + "\n" for m in messages])


def upload_place(binary_path, universe_id, place_id, do_publish=False):
    print("Uploading place to Roblox")
    version_type = "Published" if do_publish else "Saved"
    request_headers = {
        "x-api-key": ROBLOX_API_KEY,
        "Content-Type": "application/xml",
        "Accept": "application/json",
    }

    url = f"https://apis.roblox.com/universes/v1/{universe_id}/places/{place_id}/versions?versionType={version_type}"

    buffer = read_file(binary_path)
    req = urllib.request.Request(
        url, data=buffer, headers=request_headers, method="POST"
    )

    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode("utf-8"))
        place_version = data.get("versionNumber")

        return place_version


def run_luau_task(universe_id, place_id, place_version, script_file):
    print("Executing Luau task")
    source = read_file(script_file).decode("utf8")

    task = createTask(ROBLOX_API_KEY, source, universe_id, place_id, place_version)
    task = pollForTaskCompletion(ROBLOX_API_KEY, task["path"])
    logs = getTaskLogs(ROBLOX_API_KEY, task["path"])

    print(logs)

    if task["state"] == "COMPLETE":
        print("Lua task completed successfully")
        exit(0)
    else:
        print("Luau task failed", file=sys.stderr)
        exit(1)


if __name__ == "__main__":
    binary_file = sys.argv[1]
    script_file = sys.argv[2]

    place_version = upload_place(binary_file, ROBLOX_UNIVERSE_ID, ROBLOX_PLACE_ID)
    run_luau_task(ROBLOX_UNIVERSE_ID, ROBLOX_PLACE_ID, place_version, script_file)
