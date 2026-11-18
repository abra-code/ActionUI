#!/usr/bin/env python3
"""Windows build and test driver for ActionUI, used by .github/workflows/windows.yml and runnable
by hand on a Windows machine with the Swift toolchain installed.

Usage:
  python Scripts/ci-windows.py core [--results DIR]
      Builds the portable core (ACTIONUI_CORE_ONLY=1 selects that package) with its tests, then
      runs the tests, in its own build folder (.build/ci-windows-core) so a full build's folder is
      left alone. Writes each step's log, summary.md and summary.json into DIR (default:
      .build/ci-windows-results). On GitHub Actions the summary is also added to the job summary.

Exit status: 0 passed, 1 a build or test step failed or swift is missing, 2 bad arguments.
"""

import argparse
import datetime
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
STEP_TIMEOUT_SECONDS = 45 * 60
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")


def run_step(name, command, results, env):
    """Runs `command` in the repository, writing its combined output to results/<name>.log.
    Returns a dict with the step's name, exit status, duration and a note."""
    log_path = results / f"{name}.log"
    started = time.monotonic()
    status = None
    note = ""
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        log.write(f"$ {' '.join(command)}\n(cwd {REPO_DIR})\n\n")
        log.flush()
        try:
            completed = subprocess.run(command, cwd=REPO_DIR, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, timeout=STEP_TIMEOUT_SECONDS)
            status = completed.returncode
            if status > 255 or status < 0:
                # A Windows exception code such as 0xC0000409 (fail-fast) reads better in hex.
                note = f"exit 0x{status & 0xFFFFFFFF:08X}"
        except FileNotFoundError as error:
            note = f"command not found: {error}"
            log.write(f"\n{note}\n")
        except subprocess.TimeoutExpired:
            note = f"timed out after {STEP_TIMEOUT_SECONDS} s"
            log.write(f"\n{note}\n")
    seconds = round(time.monotonic() - started, 1)
    print(f"{name}: status {status} in {seconds} s {note}".rstrip(), flush=True)
    return {"step": name, "status": status, "seconds": seconds, "note": note, "log": log_path.name}


def capture(command):
    """The stripped output of a short informational command, or the error it raised."""
    try:
        completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, timeout=120)
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        return f"<{error}>"
    return completed.stdout.strip()


def environment_facts():
    return {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "swift_version": capture(["swift", "--version"]).replace("\n", " "),
        "commit": capture(["git", "-C", str(REPO_DIR), "rev-parse", "HEAD"]),
        "runner_image": (os.environ.get("ImageOS", "") + " " + os.environ.get("ImageVersion", "")).strip(),
    }


def xctest_counts(log_path):
    """The 'Executed N tests, with M failures' line under XCTest's 'All tests' suite, as numbers;
    None when the run printed no total (it crashed or ran nothing). A crashed run's last
    'Executed' line belongs to whichever suite finished last, not to the whole run."""
    text = log_path.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"Test Suite 'All tests' (?:passed|failed) at [^\n]*\n"
                         r"\s*Executed (\d+) tests?, with (\d+) failures?", text)
    if not matches:
        return None
    executed, failures = matches[-1]
    return {"executed": int(executed), "failures": int(failures)}


def first_errors(log_path, limit=40):
    """The distinct 'path:line:column: error:' lines of a log, without color codes, first `limit`
    of them; else the distinct lines containing 'error: ' (a failed link or a failed command)."""
    text = ANSI_ESCAPE.sub("", log_path.read_text(encoding="utf-8", errors="replace"))
    located = re.findall(r"^\S.*:\d+:\d+: error: .*$", text, flags=re.MULTILINE)
    if not located:
        located = [line for line in text.splitlines() if "error: " in line]
    seen = []
    for line in located:
        if line not in seen:
            seen.append(line)
        if len(seen) >= limit:
            break
    return seen


def write_summary(results, summary):
    (results / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    title = f"Windows {summary['environment']['machine']}: {summary['name']}"
    lines = [f"## {title}: {'passed' if summary['passed'] else 'FAILED'}", ""]
    for key, value in summary["environment"].items():
        lines.append(f"- {key}: {value}")
    lines += ["", "| Step | Status | Seconds | Note |", "|---|---|---|---|"]
    for step in summary["steps"]:
        lines.append(f"| {step['step']} | {step['status']} | {step['seconds']} | {step['note']} |")
    if summary.get("tests"):
        lines += ["", f"Tests: {summary['tests']['executed']} executed, "
                      f"{summary['tests']['failures']} failures"]
    if summary.get("errors"):
        lines += ["", "First errors:", "", "```"] + summary["errors"] + ["```"]
    text = "\n".join(lines) + "\n"
    (results / "summary.md").write_text(text, encoding="utf-8")
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as handle:
            handle.write(text)
    print(text, flush=True)


def check_core(results):
    env = dict(os.environ, ACTIONUI_CORE_ONLY="1")
    scratch = ["--scratch-path", str(REPO_DIR / ".build" / "ci-windows-core")]
    summary = {"name": "core builds and passes its tests", "environment": environment_facts(),
               "steps": [], "passed": False}
    build = run_step("core-build", ["swift", "build", "--build-tests"] + scratch, results, env)
    summary["steps"].append(build)
    if build["status"] != 0:
        summary["errors"] = first_errors(results / build["log"])
        write_summary(results, summary)
        return 1
    test = run_step("core-test", ["swift", "test", "--skip-build"] + scratch, results, env)
    summary["steps"].append(test)
    tests = xctest_counts(results / test["log"])
    summary["tests"] = tests
    if test["status"] != 0:
        summary["errors"] = first_errors(results / test["log"])
    # A zero exit with no XCTest total, or a total of none, ran nothing: not a pass.
    summary["passed"] = test["status"] == 0 and tests is not None and tests["executed"] > 0
    write_summary(results, summary)
    return 0 if summary["passed"] else 1


def main():
    parser = argparse.ArgumentParser(description="ActionUI Windows build and test driver")
    parser.add_argument("command", choices=["core"])
    parser.add_argument("--results", default=str(REPO_DIR / ".build" / "ci-windows-results"))
    arguments = parser.parse_args()
    # Piped stdout on Windows uses the ANSI code page; a log line it cannot encode (a test
    # fixture's text in an assertion message) must not end the run with a traceback.
    sys.stdout.reconfigure(errors="backslashreplace")
    if shutil.which("swift") is None:
        print("ci-windows: swift is not on PATH; install the Swift toolchain for Windows",
              file=sys.stderr)
        return 1
    results = Path(arguments.results).resolve()
    results.mkdir(parents=True, exist_ok=True)
    if arguments.command == "core":
        return check_core(results)
    return 2


if __name__ == "__main__":
    sys.exit(main())
