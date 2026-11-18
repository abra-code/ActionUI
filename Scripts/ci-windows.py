#!/usr/bin/env python3
"""Windows build and test driver for ActionUI, used by .github/workflows/windows.yml and runnable
by hand on a Windows machine with the Swift toolchain installed.

Usage:
  python Scripts/ci-windows.py core [--results DIR]
      Builds the portable core (ACTIONUI_CORE_ONLY=1 selects that package) with its tests, then
      runs the tests, in its own build folder (.build/ci-windows-core) so a full build's folder is
      left alone. Writes each step's log, summary.md and summary.json into DIR (default:
      .build/ci-windows-results). On GitHub Actions the summary is also added to the job summary.
  python Scripts/ci-windows.py shim [--results DIR] [--install-runtime]
      Builds the WinUI shim (ActionUIWinUI/Shim) for this machine's architecture: downloads the
      pinned Windows App SDK and C++/WinRT NuGet packages, generates the C++/WinRT projection,
      compiles ActionUIWinUIShim.dll with MSVC, then builds and runs the C smoke test, which
      renders a window's content into DIR/shim-smoke.png. Everything goes to .build/winui-shim.
      --install-runtime first installs the Windows App SDK runtime from the package's MSIX files
      for the current user (the smoke test needs it; CI machines do not have it).
  python Scripts/ci-windows.py winui [--results DIR] [--install-runtime]
      What shim does, then builds the Swift package for Windows (windowsPackage in Package.swift)
      with the shim's import library on the linker path, in .build/ci-windows-winui, and runs its
      smoke test ActionUIWinUISmoke, which renders DIR/swift-smoke.png.

Exit status: 0 passed, 1 a step failed or a tool is missing, 2 bad arguments.
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
import urllib.request
import zipfile
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
STEP_TIMEOUT_SECONDS = 45 * 60
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")

SHIM_DIR = REPO_DIR / "ActionUIWinUI" / "Shim"
SHIM_WORK = REPO_DIR / ".build" / "winui-shim"
# The NuGet packages the shim is built from. WinUI 2.7.0 refers to WebView2's metadata, at the
# version its own package depends on.
WINUI_PACKAGES = {
    "microsoft.windows.cppwinrt": "3.0.260818.1",
    "microsoft.windowsappsdk.foundation": "2.7.0",
    "microsoft.windowsappsdk.interactiveexperiences": "2.7.0",
    "microsoft.windowsappsdk.dwrite": "2.7.0",
    "microsoft.windowsappsdk.winui": "2.7.0",
    "microsoft.windowsappsdk.runtime": "2.7.0",
    "microsoft.web.webview2": "1.0.3719.77",
}
# Installed in this order: the framework package first, the others depend on it.
WINUI_RUNTIME_MSIX = [
    "Microsoft.WindowsAppRuntime.2.msix",
    "Microsoft.WindowsAppRuntime.Main.2.msix",
    "Microsoft.WindowsAppRuntime.Singleton.2.msix",
    "Microsoft.WindowsAppRuntime.DDLM.2.msix",
]
SMOKE_TIMEOUT_SECONDS = 180


def run_step(name, command, results, env, cwd=REPO_DIR, timeout=STEP_TIMEOUT_SECONDS):
    """Runs `command` in `cwd`, writing its combined output to results/<name>.log.
    Returns a dict with the step's name, exit status, duration and a note."""
    log_path = results / f"{name}.log"
    started = time.monotonic()
    status = None
    note = ""
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        log.write(f"$ {' '.join(str(part) for part in command)}\n(cwd {cwd})\n\n")
        log.flush()
        try:
            completed = subprocess.run([str(part) for part in command], cwd=cwd, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, timeout=timeout)
            status = completed.returncode
            if status > 255 or status < 0:
                # A Windows exception code such as 0xC0000409 (fail-fast) reads better in hex.
                note = f"exit 0x{status & 0xFFFFFFFF:08X}"
        except FileNotFoundError as error:
            note = f"command not found: {error}"
            log.write(f"\n{note}\n")
        except subprocess.TimeoutExpired:
            note = f"timed out after {timeout} s"
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
    of them; else the distinct lines with 'error: ' or an MSVC 'error C2440:' / 'error LNK2019:'
    (a failed link, a failed command, an MSVC compile)."""
    text = ANSI_ESCAPE.sub("", log_path.read_text(encoding="utf-8", errors="replace"))
    located = re.findall(r"^\S.*:\d+:\d+: error: .*$", text, flags=re.MULTILINE)
    if not located:
        msvc_error = re.compile(r"\berror [A-Z]+\d{4}:")
        located = [line for line in text.splitlines() if "error: " in line or msvc_error.search(line)]
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
    if summary.get("findings"):
        lines += ["", "Findings:", ""] + [f"- {finding}" for finding in summary["findings"]]
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
    # --manifest-cache none: the package's exclude lists come from the folder listing (Package.swift).
    scratch = ["--scratch-path", str(REPO_DIR / ".build" / "ci-windows-core"), "--manifest-cache", "none"]
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


# MARK: - The WinUI shim


def windows_arch():
    """'arm64' or 'x64': the names the NuGet packages and vcvarsall.bat use."""
    return "arm64" if platform.machine().upper() == "ARM64" else "x64"


def fetch_packages(work, findings):
    """Downloads and extracts WINUI_PACKAGES into work/packages/<id>/ (kept between runs).
    Returns {id: folder}."""
    folders = {}
    packages = work / "packages"
    packages.mkdir(parents=True, exist_ok=True)
    for package_id, version in WINUI_PACKAGES.items():
        archive = packages / f"{package_id}.{version}.nupkg"
        folder = packages / f"{package_id}.{version}"
        if not archive.is_file():
            url = f"https://api.nuget.org/v3-flatcontainer/{package_id}/{version}/{package_id}.{version}.nupkg"
            partial = archive.with_suffix(".partial")
            urllib.request.urlretrieve(url, partial)
            partial.replace(archive)
            if folder.exists():
                shutil.rmtree(folder)
        if not folder.exists():
            # Extracted beside the folder and renamed, so an interrupted run leaves no half folder
            # for the next run to reuse.
            extracting = folder.with_name(folder.name + ".extracting")
            if extracting.exists():
                shutil.rmtree(extracting)
            with zipfile.ZipFile(archive) as zipped:
                zipped.extractall(extracting)
            extracting.replace(folder)
        folders[package_id] = folder
    findings.append("packages: " + ", ".join(f"{key} {value}" for key, value in WINUI_PACKAGES.items()))
    return folders


def newest_winmd_files(folders):
    """Every .winmd under the packages' metadata folders and directly in lib/ (WebView2); where the
    same file name is in several version folders (metadata/10.0.17763.0/...), the one in the
    highest version."""
    def version_key(path):
        return [int(part) if part.isdigit() else -1 for part in path.parent.name.split(".")]
    chosen = {}
    for folder in folders.values():
        candidates = list((folder / "metadata").rglob("*.winmd")) if (folder / "metadata").is_dir() else []
        candidates += list((folder / "lib").glob("*.winmd")) if (folder / "lib").is_dir() else []
        for winmd in sorted(candidates):
            current = chosen.get(winmd.name)
            if current is None or version_key(winmd) > version_key(current):
                chosen[winmd.name] = winmd
    return sorted(chosen.values())


def msvc_environment(arch, results):
    """The environment of the newest Visual Studio's developer prompt for `arch`
    (vcvarsall.bat x64 or arm64), and the vcvarsall.bat path."""
    program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    vswhere = Path(program_files_x86) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    install = capture([str(vswhere), "-latest", "-products", "*", "-property", "installationPath"])
    lines = install.splitlines()
    vcvars = Path(lines[-1].strip() if lines else "") / "VC" / "Auxiliary" / "Build" / "vcvarsall.bat"
    if not vcvars.is_file():
        raise RuntimeError(f"no vcvarsall.bat (vswhere said: {install!r})")
    script = results / "vcvars-environment.bat"
    script.write_text(f'@call "{vcvars}" {arch} >nul\r\n@set\r\n', encoding="ascii")
    completed = subprocess.run(["cmd", "/c", str(script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, timeout=300)
    environment = {}
    for line in completed.stdout.splitlines():
        if "=" in line and not line.startswith("="):
            key, value = line.split("=", 1)
            environment[key] = value
    if "INCLUDE" not in environment:
        raise RuntimeError(f"{vcvars} {arch} gave no INCLUDE")
    return environment, vcvars


def resolve_tool(name, env):
    """`name` looked up on env's Path: Windows looks a bare program name up on this process's PATH,
    not on the child's."""
    resolved = shutil.which(name, path=env.get("Path") or env.get("PATH") or "")
    return resolved if resolved else name


def generate_projection(folders, work, msvc, results, summary):
    """Runs cppwinrt.exe over the Windows SDK and the packages' metadata into work/generated,
    unless a projection from the same inputs is already there. Returns the folder or None."""
    generated = work / "generated"
    stamp = generated / "inputs.json"
    inputs = {"packages": WINUI_PACKAGES, "windows_sdk": msvc.get("WindowsSDKVersion", "")}
    if stamp.is_file() and json.loads(stamp.read_text(encoding="utf-8")) == inputs:
        summary["findings"].append("C++/WinRT projection: reused (same packages and Windows SDK)")
        return generated
    if generated.exists():
        shutil.rmtree(generated)
    winmds = newest_winmd_files(folders)
    command = [folders["microsoft.windows.cppwinrt"] / "bin" / "cppwinrt.exe", "-input", "sdk"]
    for winmd in winmds:
        command += ["-input", winmd]
    command += ["-output", generated]
    step = run_step("shim-cppwinrt", command, results, msvc, cwd=work, timeout=900)
    summary["steps"].append(step)
    if step["status"] != 0:
        return None
    stamp.write_text(json.dumps(inputs, indent=2) + "\n", encoding="utf-8")
    summary["findings"].append(f"C++/WinRT projection: generated from {len(winmds)} winmd files and the Windows SDK")
    return generated


def install_runtime(folders, arch, results):
    msix_folder = folders["microsoft.windowsappsdk.runtime"] / "tools" / "MSIX" / f"win10-{arch}"
    lines = ["$ErrorActionPreference = 'Stop'"]
    for name in WINUI_RUNTIME_MSIX:
        lines.append(f"Write-Output 'Add-AppxPackage {name}'")
        lines.append(f"Add-AppxPackage -Path '{msix_folder / name}' -ForceApplicationShutdown")
    lines.append("Get-AppxPackage -Name '*WindowsAppRuntime*' | Format-Table -AutoSize Name, Version, Architecture")
    script = results / "install-runtime.ps1"
    script.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
    return run_step("shim-runtime", ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script],
                    results, dict(os.environ), cwd=results, timeout=600)


def check_shim(results, install, swift=False):
    """The shim and its C smoke test; with `swift`, then the Swift package (windowsPackage) and its
    smoke test, ActionUIWinUISmoke, linked against the shim just built."""
    arch = windows_arch()
    name = ("WinUI shim and renderer build and drive a window from C and Swift" if swift
            else "WinUI shim builds and drives a window from C")
    summary = {"name": name, "environment": environment_facts(), "steps": [], "findings": [], "passed": False}
    findings = summary["findings"]

    def finish(passed):
        summary["passed"] = passed
        write_summary(results, summary)
        return 0 if passed else 1

    def failed_step(step):
        summary["errors"] = first_errors(results / step["log"])
        return finish(False)

    if platform.system() != "Windows":
        findings.append("not Windows: the shim builds on Windows only")
        return finish(False)
    work = SHIM_WORK
    work.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    try:
        folders = fetch_packages(work, findings)
    except Exception as error:  # a download or an archive failed
        findings.append(f"fetching the NuGet packages failed: {error}")
        return finish(False)
    summary["steps"].append({"step": "shim-fetch", "status": 0, "seconds": round(time.monotonic() - started, 1),
                             "note": f"{len(folders)} packages", "log": ""})
    try:
        msvc, vcvars = msvc_environment(arch, results)
    except Exception as error:
        findings.append(f"no MSVC environment: {error}")
        return finish(False)
    findings.append(f"MSVC {msvc.get('VCToolsVersion', '?')} ({vcvars} {arch}), Windows SDK "
                    f"{msvc.get('WindowsSDKVersion', '?').strip(chr(92))}")

    generated = generate_projection(folders, work, msvc, results, summary)
    if generated is None:
        return failed_step(summary["steps"][-1])

    out = work / arch
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    foundation = folders["microsoft.windowsappsdk.foundation"]
    includes = [f"/I{generated}", f"/I{SHIM_DIR / 'include'}", f"/I{SHIM_DIR / 'src'}"]
    includes += [f"/I{folder / 'include'}" for folder in folders.values() if (folder / "include").is_dir()]
    sources = sorted((SHIM_DIR / "src").glob("*.cpp"))
    command = [resolve_tool("cl", msvc), "/nologo", "/std:c++20", "/EHsc", "/permissive-", "/MD", "/O1",
               "/bigobj", "/utf-8", "/W3", "/MP", "/DNOMINMAX"] + includes + sources + [
               "/LD", f"/Fe{out / 'ActionUIWinUIShim.dll'}", f"/Fo{out}\\",
               "/link", "windowsapp.lib", "user32.lib", "ole32.lib",
               foundation / "lib" / "native" / arch / "Microsoft.WindowsAppRuntime.Bootstrap.lib"]
    step = run_step("shim-build", command, results, msvc, cwd=out)
    summary["steps"].append(step)
    if step["status"] != 0:
        return failed_step(step)

    tests = SHIM_DIR / "Tests"
    command = [resolve_tool("cl", msvc), "/nologo", "/std:c11", "/W4", "/utf-8", f"/I{SHIM_DIR / 'include'}",
               tests / "ShimSmokeTest.c", f"/Fe{out / 'ShimSmokeTest.exe'}", f"/Fo{out}\\",
               "/link", out / "ActionUIWinUIShim.lib", "/MANIFEST:EMBED",
               f"/MANIFESTINPUT:{tests / 'ShimSmokeTest.exe.manifest'}"]
    step = run_step("smoke-build", command, results, msvc, cwd=out)
    summary["steps"].append(step)
    if step["status"] != 0:
        return failed_step(step)
    bootstrap = foundation / "runtimes" / f"win-{arch}" / "native" / "Microsoft.WindowsAppRuntime.Bootstrap.dll"
    shutil.copy2(bootstrap, out / bootstrap.name)

    if install:
        step = install_runtime(folders, arch, results)
        summary["steps"].append(step)
        if step["status"] != 0:
            return failed_step(step)

    png = results / "shim-smoke.png"
    step = run_step("smoke-test", [out / "ShimSmokeTest.exe", png], results, dict(os.environ), cwd=out,
                    timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    findings += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
                 if line.startswith("smoke:")]
    findings.append(f"ActionUIWinUIShim.dll: {(out / 'ActionUIWinUIShim.dll').stat().st_size} bytes")
    if not (step["status"] == 0 and png.is_file() and png.stat().st_size > 0):
        return finish(False)
    if not swift:
        return finish(True)
    return finish(check_swift_smoke(out, bootstrap, results, summary))


def check_swift_smoke(shim_out, bootstrap, results, summary):
    """Builds ActionUIWinUISmoke with the shim's import library on the linker path, places the shim
    DLL, the bootstrapper DLL and the program's manifest beside it, and runs it. True when it
    passed."""
    # --manifest-cache none: the package's exclude lists come from the folder listing (Package.swift).
    scratch = ["--scratch-path", str(REPO_DIR / ".build" / "ci-windows-winui"), "--manifest-cache", "none"]
    product = ["--product", "ActionUIWinUISmoke"]
    env = dict(os.environ)
    env.pop("ACTIONUI_CORE_ONLY", None)
    step = run_step("swift-build", ["swift", "build"] + product + scratch + ["-Xswiftc", f"-L{shim_out}"],
                    results, env)
    summary["steps"].append(step)
    if step["status"] != 0:
        summary["errors"] = first_errors(results / step["log"])
        return False
    shown = capture(["swift", "build"] + scratch + ["--show-bin-path"]).splitlines()
    bin_path = Path(shown[-1].strip()) if shown else Path()
    program = bin_path / "ActionUIWinUISmoke.exe"
    if not program.is_file():
        summary["findings"].append(f"no ActionUIWinUISmoke.exe in {bin_path}")
        return False
    for source in [shim_out / "ActionUIWinUIShim.dll", bootstrap]:
        shutil.copy2(source, bin_path / source.name)
    shutil.copy2(REPO_DIR / "ActionUIWinUI" / "Apps" / "Smoke" / "ActionUIWinUISmoke.exe.manifest",
                 bin_path / "ActionUIWinUISmoke.exe.manifest")
    png = results / "swift-smoke.png"
    step = run_step("swift-smoke", [program, png], results, env, cwd=bin_path, timeout=SMOKE_TIMEOUT_SECONDS)
    summary["steps"].append(step)
    summary["findings"] += [line for line in (results / step["log"]).read_text(encoding="utf-8", errors="replace")
                            .splitlines() if line.startswith("smoke:")]
    return step["status"] == 0 and png.is_file() and png.stat().st_size > 0


def main():
    parser = argparse.ArgumentParser(description="ActionUI Windows build and test driver")
    parser.add_argument("command", choices=["core", "shim", "winui"])
    parser.add_argument("--results", default=str(REPO_DIR / ".build" / "ci-windows-results"))
    parser.add_argument("--install-runtime", action="store_true",
                        help="shim, winui: install the Windows App SDK runtime for the current user first")
    arguments = parser.parse_args()
    # Piped stdout on Windows uses the ANSI code page; a log line it cannot encode (a test
    # fixture's text in an assertion message) must not end the run with a traceback.
    sys.stdout.reconfigure(errors="backslashreplace")
    results = Path(arguments.results).resolve()
    results.mkdir(parents=True, exist_ok=True)
    if arguments.command == "core":
        if shutil.which("swift") is None:
            print("ci-windows: swift is not on PATH; install the Swift toolchain for Windows",
                  file=sys.stderr)
            return 1
        return check_core(results)
    if arguments.command == "shim":
        return check_shim(results, arguments.install_runtime)
    if arguments.command == "winui":
        if shutil.which("swift") is None:
            print("ci-windows: swift is not on PATH; install the Swift toolchain for Windows",
                  file=sys.stderr)
            return 1
        return check_shim(results, arguments.install_runtime, swift=True)
    return 2


if __name__ == "__main__":
    sys.exit(main())
