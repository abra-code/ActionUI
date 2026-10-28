// Finds what implements the ActionUI C functions and tells cargo how to link it.
//
// macOS: the static frameworks. They are Swift static libraries, so besides the
// frameworks themselves the final link needs the Swift library search paths: the object
// files name the Swift libraries they use, and the linker has to be able to find them.
//
// Linux: libActionUI.so from the ActionUI library package, which carries the Swift
// runtime itself. It is copied into OUT_DIR and linked from there: cargo puts search
// paths inside the target folder on the dynamic library path when it runs a program
// (cargo run, cargo test), so no absolute rpath goes into the binaries. A program run on
// its own finds the copy beside it through an $ORIGIN rpath (.cargo/config.toml).

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const FRAMEWORKS: [&str; 5] = [
    "ActionUI",
    "ActionUICAdapter",
    "ActionUIAppKitApplication",
    "ActionUIMenuBar",
    "ActionUIRemote",
];

// System frameworks ActionUI's Swift code uses. Most are named by the object files
// themselves; AVKit is not (see the note in ActionUI's Package.swift), and listing the
// main ones keeps the link independent of that mechanism.
const SYSTEM_FRAMEWORKS: [&str; 5] = ["Foundation", "AppKit", "SwiftUI", "AVKit", "Charts"];

// In the library package (actionui-<version>-linux-<arch>/).
const LIBRARY_FILE: &str = "lib/libActionUI.so";

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    match target_os.as_str() {
        "macos" => link_frameworks(),
        "linux" => link_library(),
        // The crate is empty on other systems; nothing to link.
        _ => {}
    }
}

fn link_library() {
    println!("cargo:rerun-if-env-changed=ACTIONUI_LIBRARY_DIR");

    let library_dir = find_library_dir();
    let library = library_dir.join(LIBRARY_FILE);
    println!("cargo:rerun-if-changed={}", library.display());

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let copy = out_dir.join("libActionUI.so");
    if let Err(error) = fs::copy(&library, &copy) {
        panic!("could not copy {} to {}: {error}", library.display(), copy.display());
    }

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=dylib=ActionUI");

    // Read by dependent build scripts as DEP_ACTIONUI_LIBRARY_DIR (the package, with its
    // C headers), and by this crate's tests through env!().
    println!("cargo:library_dir={}", library_dir.display());
    println!("cargo:rustc-env=ACTIONUI_SYS_LIBRARY_DIR={}", library_dir.display());
}

fn find_library_dir() -> PathBuf {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let default_dir = manifest_dir.join("../library");

    if let Ok(value) = env::var("ACTIONUI_LIBRARY_DIR") {
        let dir = PathBuf::from(&value);
        if dir.join(LIBRARY_FILE).is_file() {
            return dir.canonicalize().unwrap_or(dir);
        }
        panic!(
            "ACTIONUI_LIBRARY_DIR is set to '{value}', but there is no {LIBRARY_FILE} in it. \
             It must be the unpacked ActionUI library package (actionui-<version>-linux-<arch>), \
             the folder that holds lib/ and include/."
        );
    }

    if default_dir.join(LIBRARY_FILE).is_file() {
        return default_dir.canonicalize().unwrap_or(default_dir);
    }

    panic!(
        "The ActionUI library package was not found in '{}'. Unpack actionui-<version>-linux-<arch>.tar.gz \
         (made by Scripts/make-linux-library-package.sh) and set ACTIONUI_LIBRARY_DIR to the unpacked folder, \
         or put its lib/ and include/ folders there.",
        default_dir.display()
    );
}

fn link_frameworks() {
    println!("cargo:rerun-if-env-changed=ACTIONUI_FRAMEWORKS_DIR");

    let frameworks_dir = find_frameworks_dir();
    println!("cargo:rerun-if-changed={}", frameworks_dir.display());

    println!("cargo:rustc-link-search=framework={}", frameworks_dir.display());
    for framework in FRAMEWORKS {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
    for framework in SYSTEM_FRAMEWORKS {
        println!("cargo:rustc-link-lib=framework={framework}");
    }

    // The Swift runtime lives in the system; the toolchain directory holds the
    // compatibility libraries the object files may also name.
    println!("cargo:rustc-link-search=native=/usr/lib/swift");
    if let Some(toolchain_swift_dir) = toolchain_swift_lib_dir() {
        println!("cargo:rustc-link-search=native={}", toolchain_swift_dir.display());
    }
    if let Some(sdk_swift_dir) = sdk_swift_lib_dir() {
        println!("cargo:rustc-link-search=native={}", sdk_swift_dir.display());
    }

    // Read by dependent build scripts as DEP_ACTIONUI_FRAMEWORKS_DIR, and by this
    // crate's tests through env!().
    println!("cargo:frameworks_dir={}", frameworks_dir.display());
    println!("cargo:rustc-env=ACTIONUI_SYS_FRAMEWORKS_DIR={}", frameworks_dir.display());
}

fn has_all_frameworks(dir: &Path) -> bool {
    FRAMEWORKS
        .iter()
        .all(|framework| dir.join(format!("{framework}.framework")).is_dir())
}

fn find_frameworks_dir() -> PathBuf {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let default_dir = manifest_dir.join("../frameworks/Release");

    if let Ok(value) = env::var("ACTIONUI_FRAMEWORKS_DIR") {
        let dir = PathBuf::from(&value);
        if has_all_frameworks(&dir) {
            return dir.canonicalize().unwrap_or(dir);
        }
        panic!(
            "ACTIONUI_FRAMEWORKS_DIR is set to '{value}', but that directory does not hold all of: {}. \
             It must be the directory that directly contains the .framework bundles \
             (the 'Release' directory written by ActionUIRust/build_frameworks.sh).",
            FRAMEWORKS.join(".framework, ") + ".framework"
        );
    }

    if has_all_frameworks(&default_dir) {
        return default_dir.canonicalize().unwrap_or(default_dir);
    }

    panic!(
        "The ActionUI frameworks were not found in '{}'. Run ActionUIRust/build_frameworks.sh, \
         or set ACTIONUI_FRAMEWORKS_DIR to the directory that contains the .framework bundles.",
        default_dir.display()
    );
}

fn xcrun(args: &[&str]) -> Option<PathBuf> {
    let output = Command::new("/usr/bin/xcrun").args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8(output.stdout).ok()?;
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(PathBuf::from(trimmed))
}

// <toolchain>/usr/bin/swiftc -> <toolchain>/usr/lib/swift/macosx
fn toolchain_swift_lib_dir() -> Option<PathBuf> {
    let swiftc = xcrun(&["--find", "swiftc"])?;
    let dir = swiftc.parent()?.parent()?.join("lib/swift/macosx");
    dir.is_dir().then_some(dir)
}

fn sdk_swift_lib_dir() -> Option<PathBuf> {
    let sdk = xcrun(&["--sdk", "macosx", "--show-sdk-path"])?;
    let dir = sdk.join("usr/lib/swift");
    dir.is_dir().then_some(dir)
}
