// Core/Common/ActionUIVersion.swift
/*
 The version of ActionUI: the release's git tag without its "v" (tag v0.9.0 is "0.9.0"). Written by
 hand only here. Scripts/set-version.sh writes it here and into every manifest that states it (the
 Xcode project's MARKETING_VERSION, the Python, Node.js, Rust and Web packages); with --check it
 reports any that differ. The C adapter's actionUIGetVersion returns it, and through it the Python,
 Node.js and Rust packages' version calls.
*/

public enum ActionUIVersion {
    /// "major.minor.patch".
    public static let string = "0.9.0"
}
