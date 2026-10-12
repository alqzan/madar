#!/usr/bin/env python3
"""Drive a real simulator Face ID match through documented devicectl commands.

Run from any directory with --device, --derived-data and a new --output-dir.
The isolated AX3/light UI test emits its checkpoint only after native auth has
covered the scene. No app authentication seam or production setting is changed.
Use --test background-retirement for the share-revocation/reentry slice; its
launchctl snapshots require the same app PID and service label across reentry.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time


def app_process_snapshot(device, path):
    """Identify the app's launch service without confusing it with its UI runner."""
    listing = subprocess.check_output(
        ["xcrun", "simctl", "spawn", device, "launchctl", "list"], text=True, timeout=15
    )
    path.write_text(listing)
    matches = []
    for line in listing.splitlines():
        columns = line.split("\t", 2)
        if len(columns) != 3:
            continue
        pid, _, label = columns
        if pid.isdigit() and int(pid) > 0 and re.search(r"(?:^|:)com\.alqzan\.madar2(?:\[|$)", label):
            matches.append({"pid": int(pid), "label": label})
    if len(matches) != 1:
        raise RuntimeError(f"Expected one running Madar app service, found {len(matches)}; inspect {path}")
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--test", choices=["share-dismissal", "background-retirement"], default="share-dismissal")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)

    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"], text=True))
    simulator = next((item for group in devices["devices"].values() for item in group
                      if item["udid"] == args.device), None)
    if simulator is None or simulator["state"] != "Booted":
        raise RuntimeError("--device must identify an already booted simulator.")

    enrollment_json = output / "enrollment.json"
    enrollment = ["xcrun", "devicectl", "device", "settings", "biometrics",
                  "--device", args.device, "--timeout", "15", "--json-output", str(enrollment_json)]
    with (output / "biometric-command.log").open("w") as biometric_log:
        subprocess.run(enrollment, stdout=biometric_log, stderr=subprocess.STDOUT, check=True)
        enrolled = json.loads(enrollment_json.read_text())
        if enrolled["info"]["outcome"] != "success" or not any(
                item["type"] == "Face ID" and item["enabled"] for item in enrolled["result"]["biometrics"]):
            raise RuntimeError("Face ID must already be enabled; this driver does not change enrollment.")

        log = output / "xcodebuild.log"
        result = output / "native-share.xcresult"
        test_name = {
            "share-dismissal": "test_M0T09_AX3NativeShareAfterSimulatorFaceIDMatch",
            "background-retirement": "test_M0T09_AX3BackgroundRetiresAuthorizedNativeShareWithoutReopening",
        }[args.test]
        command = ["xcodebuild", "test", "-project", "Madar.xcodeproj", "-scheme", "Madar",
                   "-destination", f"id={args.device}", "-derivedDataPath", str(args.derived_data.resolve()),
                   "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                   f"-only-testing:MadarUITests/FoundationUITests/{test_name}",
                   "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES"]
        (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        environment = dict(os.environ, TEST_RUNNER_MADAR_TEST_NATIVE_BIOMETRICS="1")
        matched = False
        before_identity = None
        reentry_identity = None
        with log.open("w") as build_log:
            process = subprocess.Popen(command, cwd=root, env=environment, stdout=build_log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 240
            try:
                while process.poll() is None:
                    current_log = log.read_text()
                    if not matched and "MADAR_NATIVE_FACEID_REQUEST_READY" in current_log:
                        if args.test == "background-retirement":
                            before_identity = app_process_snapshot(args.device, output / "process-before-auth-match.txt")
                        match_json = output / "match.json"
                        match = ["xcrun", "devicectl", "device", "simulate", "biometrics", "--device", args.device,
                                 "--success", "--timeout", "15", "--json-output", str(match_json)]
                        subprocess.run(match, stdout=biometric_log, stderr=subprocess.STDOUT, check=True)
                        if json.loads(match_json.read_text())["info"]["outcome"] != "success":
                            raise RuntimeError("The simulator biometric match command failed.")
                        matched = True
                    if args.test == "background-retirement" and reentry_identity is None and "MADAR_NATIVE_SHARE_REENTRY_READY" in current_log:
                        if "MADAR_NATIVE_SHARE_BEFORE_HOME" not in current_log:
                            raise RuntimeError("Native share reentry was reported without its before-Home checkpoint.")
                        reentry_identity = app_process_snapshot(args.device, output / "process-after-reentry.txt")
                        (output / "process-identity.json").write_text(json.dumps(
                            {"before": before_identity, "reentry": reentry_identity}, indent=2
                        ) + "\n")
                        if before_identity != reentry_identity:
                            raise RuntimeError("Madar did not return as the same app process; inspect process-identity.json")
                    if time.monotonic() > deadline:
                        raise TimeoutError(f"Native biometric UI test exceeded deadline; inspect {log}")
                    time.sleep(0.1)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
        if not matched or process.returncode != 0:
            raise RuntimeError(f"Native biometric test failed or never reached its checkpoint; inspect {log}")
        if args.test == "background-retirement" and reentry_identity is None:
            raise RuntimeError(f"Native share retirement never reached its process-continuity checkpoint; inspect {log}")
    print(f"Native AX3 Face ID/{args.test} passed: {result}")


if __name__ == "__main__":
    main()
