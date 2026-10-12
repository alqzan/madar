#!/usr/bin/env python3
"""Drive a real simulator Face ID match through documented devicectl commands.

Run from any directory with --device, --derived-data and a new --output-dir.
The selected UI test emits its checkpoint only after native auth has
covered the scene. No app authentication seam or production setting is changed.
Use --test background-retirement for the share-revocation/reentry slice; its
launchctl snapshots require the same app PID and service label across reentry.
Its bounded --variant selects ax3-light (default), default-light or default-dark.
Use --test lease-expiry for a real 61-second background interval and a second
native Face ID match. This separate path is fixed to default-light.
Use --test switcher-snapshot to capture an identified real OS switcher card at
default-light. Its output requires a separate visual privacy judgment.
Use --test biometric-refusal for a documented failed match, native user Cancel,
empty fixture Backups before/after refusal, then an explicit successful retry.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid


def fixture_backup_snapshot(device, fixture, path):
    """Read metadata only below the exact new test fixture's Backups directory."""
    fixture = str(uuid.UUID(fixture)).upper()
    group = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", device, "com.alqzan.madar2", "group.com.alqzan.madar2"],
        text=True, timeout=15
    ).strip()).resolve(strict=True)
    fixture_root = group / "UITestStores" / fixture
    if not fixture_root.is_dir() or fixture_root.is_symlink() or fixture_root.resolve() != fixture_root:
        raise RuntimeError("The exact dedicated UI fixture must exist without symbolic-link redirection.")
    backups = fixture_root / "Backups"
    files = []
    if backups.exists():
        if backups.is_symlink() or not backups.is_dir():
            raise RuntimeError("Fixture Backups must be a real directory.")
        for item in sorted(backups.rglob("*")):
            if item.is_symlink() or not item.resolve().is_relative_to(backups):
                raise RuntimeError("Fixture Backups must not contain symbolic-link redirection.")
            if item.is_file():
                files.append({"path": str(item.relative_to(backups)), "bytes": item.stat().st_size})
    snapshot = {"fixture": fixture, "directory": str(backups), "files": files}
    path.write_text(json.dumps(snapshot, indent=2) + "\n")
    return snapshot


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
    parser.add_argument("--test", choices=["share-dismissal", "background-retirement", "lease-expiry", "switcher-snapshot", "biometric-refusal"], default="share-dismissal")
    parser.add_argument("--variant", choices=["ax3-light", "default-light", "default-dark"])
    args = parser.parse_args()
    if args.variant is None:
        args.variant = "default-light" if args.test in ["lease-expiry", "switcher-snapshot", "biometric-refusal"] else "ax3-light"
    if args.test == "share-dismissal" and args.variant != "ax3-light":
        parser.error("--variant default-light/default-dark requires --test background-retirement")
    if args.test in ["lease-expiry", "switcher-snapshot", "biometric-refusal"] and args.variant != "default-light":
        parser.error(f"--test {args.test} is fixed to --variant default-light")
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
            "lease-expiry": "test_M0T09_DefaultBackgroundLeaseExpiryRequiresFreshNativeFaceID",
            "switcher-snapshot": "test_M0T09_DefaultNativeShareSwitcherCaptureIdentifiesMadarCard",
            "biometric-refusal": "test_M0T09_DefaultNativeFaceIDNonmatchThenCancelRequiresExplicitRetry",
        }[args.test]
        command = ["xcodebuild", "test", "-project", "Madar.xcodeproj", "-scheme", "Madar",
                   "-destination", f"id={args.device}", "-derivedDataPath", str(args.derived_data.resolve()),
                   "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                   f"-only-testing:MadarUITests/FoundationUITests/{test_name}",
                   "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES"]
        (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        environment = dict(os.environ, TEST_RUNNER_MADAR_TEST_NATIVE_BIOMETRICS="1")
        fixture = None
        if args.test == "biometric-refusal":
            fixture = str(uuid.uuid4()).upper()
            environment["TEST_RUNNER_MADAR_TEST_NATIVE_REFUSAL_STORE_ID"] = fixture
            (output / "fixture.json").write_text(json.dumps({"fixture": fixture}, indent=2) + "\n")
        if args.test == "background-retirement":
            environment["TEST_RUNNER_MADAR_TEST_NATIVE_SHARE_VARIANT"] = args.variant
        matched = False
        reauth_matched = False
        tracks_reentry = args.test in ["background-retirement", "lease-expiry"]
        before_identity = None
        reentry_identity = None
        nonmatched = False
        refusal_snapshot = None
        retry_snapshot = None
        with log.open("w") as build_log:
            process = subprocess.Popen(command, cwd=root, env=environment, stdout=build_log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 240
            try:
                while process.poll() is None:
                    current_log = log.read_text()
                    if args.test == "biometric-refusal":
                        if not nonmatched and f"MADAR_NATIVE_FACEID_NONMATCH_REQUEST_READY fixture={fixture}" in current_log:
                            initial = fixture_backup_snapshot(args.device, fixture, output / "backups-before-nonmatch.json")
                            if initial["files"]:
                                raise RuntimeError("The fresh refusal fixture already contains backup/export output.")
                            nonmatch_json = output / "nonmatch.json"
                            nonmatch = ["xcrun", "devicectl", "device", "simulate", "biometrics", "--device", args.device,
                                        "--failure", "--timeout", "15", "--json-output", str(nonmatch_json)]
                            subprocess.run(nonmatch, stdout=biometric_log, stderr=subprocess.STDOUT, check=True)
                            if json.loads(nonmatch_json.read_text())["info"]["outcome"] != "success":
                                raise RuntimeError("The documented simulator biometric nonmatch command failed.")
                            nonmatched = True
                        if refusal_snapshot is None and f"MADAR_NATIVE_FACEID_REFUSAL_RECOVERED fixture={fixture}" in current_log:
                            if not nonmatched:
                                raise RuntimeError("Refusal recovery was reported before a documented failed match.")
                            refusal_snapshot = fixture_backup_snapshot(args.device, fixture, output / "backups-after-refusal.json")
                            if refusal_snapshot["files"]:
                                raise RuntimeError("Native nonmatch/cancellation created backup/export output.")
                        if not matched and f"MADAR_NATIVE_FACEID_REFUSAL_RETRY_REQUEST_READY fixture={fixture}" in current_log:
                            if refusal_snapshot is None:
                                raise RuntimeError("A retry match cannot precede verified empty post-refusal Backups.")
                            retry_json = output / "retry-match.json"
                            retry = ["xcrun", "devicectl", "device", "simulate", "biometrics", "--device", args.device,
                                     "--success", "--timeout", "15", "--json-output", str(retry_json)]
                            subprocess.run(retry, stdout=biometric_log, stderr=subprocess.STDOUT, check=True)
                            if json.loads(retry_json.read_text())["info"]["outcome"] != "success":
                                raise RuntimeError("The explicit retry's fresh simulator match failed.")
                            matched = True
                        if retry_snapshot is None and f"MADAR_NATIVE_FACEID_REFUSAL_RETRY_EXPORT_READY fixture={fixture}" in current_log:
                            if not matched:
                                raise RuntimeError("Retry export readiness was reported before a fresh match.")
                            retry_snapshot = fixture_backup_snapshot(args.device, fixture, output / "backups-after-retry.json")
                            plain = [item for item in retry_snapshot["files"] if item["path"].startswith("PlainExports/")
                                     and item["path"].endswith("-plain.zip") and item["bytes"] > 0]
                            if len(plain) != 1 or len(retry_snapshot["files"]) != 1:
                                raise RuntimeError("Explicit authenticated retry must create exactly one nonempty plain ZIP.")
                    if not matched and "MADAR_NATIVE_FACEID_REQUEST_READY" in current_log:
                        if tracks_reentry or args.test == "switcher-snapshot":
                            before_identity = app_process_snapshot(args.device, output / "process-before-auth-match.txt")
                        match_json = output / ("match-1.json" if args.test == "lease-expiry" else "match.json")
                        match = ["xcrun", "devicectl", "device", "simulate", "biometrics", "--device", args.device,
                                 "--success", "--timeout", "15", "--json-output", str(match_json)]
                        subprocess.run(match, stdout=biometric_log, stderr=subprocess.STDOUT, check=True)
                        if json.loads(match_json.read_text())["info"]["outcome"] != "success":
                            raise RuntimeError("The simulator biometric match command failed.")
                        matched = True
                    if tracks_reentry and reentry_identity is None and "MADAR_NATIVE_SHARE_REENTRY_READY" in current_log:
                        if "MADAR_NATIVE_SHARE_BEFORE_HOME" not in current_log:
                            raise RuntimeError("Native share reentry was reported without its before-Home checkpoint.")
                        reentry_identity = app_process_snapshot(args.device, output / "process-after-reentry.txt")
                        (output / "process-identity.json").write_text(json.dumps(
                            {"before": before_identity, "reentry": reentry_identity}, indent=2
                        ) + "\n")
                        if before_identity != reentry_identity:
                            raise RuntimeError("Madar did not return as the same app process; inspect process-identity.json")
                    if args.test == "lease-expiry" and not reauth_matched and "MADAR_NATIVE_FACEID_REAUTH_REQUEST_READY" in current_log:
                        if not matched or reentry_identity is None:
                            raise RuntimeError("Fresh authentication was requested before the first match and verified reentry.")
                        reauth_json = output / "match-2.json"
                        reauth = ["xcrun", "devicectl", "device", "simulate", "biometrics", "--device", args.device,
                                  "--success", "--timeout", "15", "--json-output", str(reauth_json)]
                        subprocess.run(reauth, stdout=biometric_log, stderr=subprocess.STDOUT, check=True)
                        if json.loads(reauth_json.read_text())["info"]["outcome"] != "success":
                            raise RuntimeError("The fresh simulator biometric match command failed.")
                        reauth_matched = True
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
        if tracks_reentry and reentry_identity is None:
            raise RuntimeError(f"Native share retirement never reached its process-continuity checkpoint; inspect {log}")
        if args.test == "lease-expiry" and not reauth_matched:
            raise RuntimeError(f"Native lease expiry never reached its second authentication checkpoint/match; inspect {log}")
        if args.test == "switcher-snapshot" and "MADAR_NATIVE_SWITCHER_CAPTURED" not in log.read_text():
            raise RuntimeError(f"A real Madar switcher card was not identified; inspect retained XCTest attachments in {result}")
        if args.test == "biometric-refusal" and (not nonmatched or refusal_snapshot is None or retry_snapshot is None):
            raise RuntimeError(f"Native nonmatch/cancellation/retry did not complete its fixture evidence; inspect {log}")
    if args.test == "switcher-snapshot":
        print(f"Native default-light switcher card captured; visual privacy acceptance pending: {result}")
    else:
        print(f"Native {args.variant} Face ID/{args.test} passed: {result}")


if __name__ == "__main__":
    main()
