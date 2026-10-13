#!/usr/bin/env python3
"""Drive a real simulator Face ID match through documented devicectl commands.

Run from any directory with --device, --derived-data and a new --output-dir.
The isolated AX3/light UI test emits its checkpoint only after native auth has
covered the scene. No app authentication seam or production setting is changed.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    # Owner decision 2026-10-13: M0-T09 is frozen and enlarged-text (AX) tests were removed,
    # so the UI test this script drove no longer exists. Kept for when M0-T09 is unfrozen.
    raise SystemExit("M0-T09 is frozen; its AX3 Face ID UI test was removed on 2026-10-13. See docs/DECISIONS.md.")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
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
        command = ["xcodebuild", "test", "-project", "Madar.xcodeproj", "-scheme", "Madar",
                   "-destination", f"id={args.device}", "-derivedDataPath", str(args.derived_data.resolve()),
                   "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                   "-only-testing:MadarUITests/FoundationUITests/test_M0T09_AX3NativeShareAfterSimulatorFaceIDMatch",
                   "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES"]
        (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        environment = dict(os.environ, TEST_RUNNER_MADAR_TEST_NATIVE_BIOMETRICS="1")
        matched = False
        with log.open("w") as build_log:
            process = subprocess.Popen(command, cwd=root, env=environment, stdout=build_log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 240
            try:
                while process.poll() is None:
                    if not matched and "MADAR_NATIVE_FACEID_REQUEST_READY" in log.read_text():
                        match_json = output / "match.json"
                        match = ["xcrun", "devicectl", "device", "simulate", "biometrics", "--device", args.device,
                                 "--success", "--timeout", "15", "--json-output", str(match_json)]
                        subprocess.run(match, stdout=biometric_log, stderr=subprocess.STDOUT, check=True)
                        if json.loads(match_json.read_text())["info"]["outcome"] != "success":
                            raise RuntimeError("The simulator biometric match command failed.")
                        matched = True
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
    print(f"Native AX3 Face ID/share/dismissal passed: {result}")


if __name__ == "__main__":
    main()
