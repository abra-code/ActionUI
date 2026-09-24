#!/usr/bin/env python3
"""Compare the Swift verifier (actionui-verify) with the Python verifier (validate_actionui.py).

Both read ActionUIVerifier/Schemas; this checks that they also apply the same rules. Both tools
are run over the same files, cross-platform and deployed to macos, ios and android, and their
output is compared line by line, summary line included. Two parts of a line are ignored:
  - "(value: ...)" in a "does not match any allowed form" message, a language-specific
    rendering of the offending value;
  - the parser's explanation after "invalid JSON".

    /usr/bin/python3 ActionUIVerifierTests/Parity/validator_parity.py [--binary <actionui-verify>] [files or dirs...]

Without --binary, Apps/ActionUIVerifier is built first and its actionui-verify is used. Without
paths, every .json document under the usual sample folders and the fixtures next to this script
is checked (fixtures/ holds documents that break every rule on purpose). Exit 1 on any difference.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PYTHON_VERIFIER = REPO / "Tools" / "verifier" / "validate_actionui.py"
TOOL_PACKAGE = REPO / "Apps" / "ActionUIVerifier"

SAMPLE_DIRS = ["ActionUISwiftTestApp/Resources", "Documentation/Elements", "Examples", "Add-ons", "Skill/master"]
PLATFORMS = [None, "macos", "ios", "android"]
VALUE_PART = re.compile(r" \(value: .*?\) does not match")
INVALID_JSON = re.compile(r": invalid JSON .*$")


def normalize(line):
    return INVALID_JSON.sub(": invalid JSON", VALUE_PART.sub(" does not match", line))


def run(command):
    # The two streams are read apart and each stderr line is marked, so the streams are compared
    # too. They are not merged into one pipe: Python's stdout is block-buffered there and a
    # buffer flush can land in the middle of a line, gluing an error line onto a warning.
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=REPO, env=env)
    lines = [normalize(line) for line in result.stdout.splitlines() if line.strip()]
    lines += ["(stderr) " + normalize(line) for line in result.stderr.splitlines() if line.strip()]
    return result.returncode, sorted(lines)


def build_tool():
    build = ["swift", "build", "--package-path", str(TOOL_PACKAGE)]
    status = subprocess.run(build).returncode
    if status != 0:
        sys.exit("error: building %s failed" % TOOL_PACKAGE)
    bin_path = subprocess.run(build + ["--show-bin-path"], stdout=subprocess.PIPE, text=True).stdout.strip()
    return str(Path(bin_path) / "actionui-verify")


def document_files(targets):
    files = []
    for target in targets:
        if target.is_dir():
            files += sorted(p for p in target.rglob("*.json")
                            if ".build" not in p.parts and "schemas" not in p.parts and "Schemas" not in p.parts
                            and not p.name.startswith("Package"))
        elif target.is_file():
            files.append(target)
    # Relative to the repository, so both tools print the same paths.
    return [str(p.relative_to(REPO)) if REPO in p.parents else str(p) for p in files]


def main():
    args = sys.argv[1:]
    binary = None
    if args[:1] == ["--binary"]:
        if len(args) < 2:
            sys.exit("error: --binary requires a path")
        binary = args[1]
        args = args[2:]
    binary = binary or build_tool()

    targets = [Path(a).resolve() for a in args] or [REPO / d for d in SAMPLE_DIRS] + [HERE / "fixtures"]
    files = document_files(targets)
    if not files:
        sys.exit("error: no .json files found")

    differing = 0
    for platform in PLATFORMS:
        options = ["--platform", platform] if platform else []
        mode = platform or "cross-platform"
        python_status, expected = run([sys.executable, str(PYTHON_VERIFIER)] + options + files)
        swift_status, actual = run([binary] + options + files)
        if expected == actual and python_status == swift_status:
            print("%s: %d files, same output" % (mode, len(files)))
            continue
        differing += 1
        print("%s: DIFFERENT (exit status python %d, swift %d)" % (mode, python_status, swift_status))
        for line in sorted(set(expected) - set(actual)):
            print("  python only: " + line)
        for line in sorted(set(actual) - set(expected)):
            print("  swift only:  " + line)
        if set(expected) == set(actual) and expected != actual:
            print("  (same lines, different repeat counts)")
    sys.exit(1 if differing else 0)


if __name__ == "__main__":
    main()
