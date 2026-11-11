#!/bin/bash
#
# install-swift.sh - installs a swift.org Swift toolchain into /usr (the layout of swift.org's own
# Linux images), after checking that the download is signed by the Swift release key named on the
# command line. Run as root, by the swift-gtk recipe; also usable by hand.
#
# Usage: install-swift.sh <version> <platform> <key fingerprint> [sha256]
#   version          a Swift release, e.g. 6.4.2
#   platform         swift.org's name for this system's build, e.g. debian13-aarch64 or
#                    ubuntu26.04-aarch64; "auto" takes it from /etc/os-release and the machine
#   key fingerprint  the full fingerprint of the key that must have signed the download (the primary
#                    key or the signing subkey); swift.org lists its keys on its install page
#   sha256           optional; when given, a download with another SHA-256 is refused
#
# The signing key's fingerprint and the download's SHA-256 are printed. A toolchain of the same
# release already in /usr is left as it is.
# Exit status: 0 installed (or already there), 1 a step failed, 64 bad arguments.

swift_version="$1"
platform="$2"
key_fingerprint="$3"
expected_sha256="$4"

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    printf 'usage: %s <version> <platform|auto> <key fingerprint> [sha256]\n' "$0" >&2
    exit 64
fi
case "$swift_version" in
    ''|*[!0-9.]*|.*|*.)
        printf 'install-swift: "%s" is not a release number such as 6.4.2\n' "$swift_version" >&2
        exit 64
        ;;
esac
key_fingerprint="$(printf '%s' "$key_fingerprint" | /usr/bin/tr -d ' ' | /usr/bin/tr 'a-f' 'A-F')"
case "$key_fingerprint" in
    *[!0-9A-F]*)
        printf 'install-swift: "%s" is not a key fingerprint (40 hexadecimal digits)\n' "$3" >&2
        exit 64
        ;;
esac
if [ "${#key_fingerprint}" -ne 40 ]; then
    printf 'install-swift: "%s" is not a key fingerprint (40 hexadecimal digits)\n' "$3" >&2
    exit 64
fi
case "$expected_sha256" in
    *[!0-9a-f]*)
        printf 'install-swift: "%s" is not a SHA-256 in lower-case hexadecimal\n' "$expected_sha256" >&2
        exit 64
        ;;
esac
if [ -n "$expected_sha256" ] && [ "${#expected_sha256}" -ne 64 ]; then
    printf 'install-swift: "%s" is not a SHA-256 (64 hexadecimal digits)\n' "$expected_sha256" >&2
    exit 64
fi

# swift.org names a Linux build <distribution><version>, with -aarch64 for ARM: debian13-aarch64,
# ubuntu26.04-aarch64 (ubuntu26.04 on x86_64).
if [ "$platform" = auto ]; then
    if [ ! -r /etc/os-release ]; then
        printf 'install-swift: no /etc/os-release to name this system by; give the platform\n' >&2
        exit 1
    fi
    system="$(. /etc/os-release && printf '%s%s' "$ID" "$VERSION_ID")"
    machine="$(/usr/bin/uname -m)"
    case "$machine" in
        aarch64) platform="$system-aarch64" ;;
        x86_64) platform="$system" ;;
        *)
            printf 'install-swift: swift.org has no build for the %s processor\n' "$machine" >&2
            exit 1
            ;;
    esac
    printf 'install-swift: this system is %s\n' "$platform"
fi
case "$platform" in
    ''|*[!a-z0-9.-]*)
        printf 'install-swift: "%s" is not a swift.org platform name such as debian13-aarch64\n' "$platform" >&2
        exit 64
        ;;
esac

tag="swift-$swift_version-RELEASE"
platform_folder="$(printf '%s' "$platform" | /usr/bin/tr -d '.')"
url="https://download.swift.org/swift-$swift_version-release/$platform_folder/$tag/$tag-$platform.tar.gz"
keys_url="https://swift.org/keys/all-keys.asc"

installed="$(/usr/bin/swift --version 2>/dev/null | /usr/bin/head -n 1)"
case "$installed" in
    *"($tag)"*)
        printf 'install-swift: Swift %s is already installed: %s\n' "$swift_version" "$installed"
        exit 0
        ;;
esac

# The toolchain is about a gigabyte: /var/tmp, since /tmp may be in memory.
work="$(/usr/bin/mktemp -d -p /var/tmp install-swift.XXXXXX)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'install-swift: could not make a work folder in /var/tmp\n' >&2
    exit 1
fi
trap '/bin/rm -rf "$work"' EXIT
tarball="$work/swift.tar.gz"

for pair in "$url|$tarball" "$url.sig|$tarball.sig" "$keys_url|$work/all-keys.asc"; do
    source_url="${pair%%|*}"
    target="${pair#*|}"
    printf 'install-swift: downloading %s\n' "$source_url"
    /usr/bin/curl --fail --silent --show-error --location --retry 3 -o "$target" "$source_url"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'install-swift: downloading %s failed (curl status %s); is %s a swift.org platform with a %s release?\n' \
            "$source_url" "$status" "$platform" "$swift_version" >&2
        exit 1
    fi
done

export GNUPGHOME="$work/gnupg"
/bin/mkdir -m 700 "$GNUPGHOME"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'install-swift: could not make %s\n' "$GNUPGHOME" >&2
    exit 1
fi
/usr/bin/gpg --batch --quiet --import "$work/all-keys.asc" 2>/dev/null
status=$?
if [ "$status" -ne 0 ]; then
    printf "install-swift: importing swift.org's keys failed (gpg status %s)\n" "$status" >&2
    exit 1
fi
verify_output="$(/usr/bin/gpg --batch --status-fd 1 --verify "$tarball.sig" "$tarball" 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ]; then
    printf "install-swift: the signature of %s does not verify against swift.org's keys (gpg status %s)\n" "$url" "$status" >&2
    exit 1
fi
# VALIDSIG <signing key fingerprint> ... <primary key fingerprint> (the 10th field after the first)
signer="$(printf '%s\n' "$verify_output" | /usr/bin/awk '$2 == "VALIDSIG" { print $3 }')"
primary="$(printf '%s\n' "$verify_output" | /usr/bin/awk '$2 == "VALIDSIG" { print $12 }')"
printf 'install-swift: good signature by key %s (primary key %s)\n' "$signer" "$primary"
if [ "$signer" != "$key_fingerprint" ] && [ "$primary" != "$key_fingerprint" ]; then
    printf 'install-swift: %s is signed by key %s, not by the expected key %s; if swift.org moved to a new key, check it on its install page and give its fingerprint\n' \
        "$url" "$primary" "$key_fingerprint" >&2
    exit 1
fi
# gpg verifies a signature by a revoked key and exits 0, saying so only in these status lines.
revoked="$(printf '%s\n' "$verify_output" | /usr/bin/awk '$2 == "REVKEYSIG" || $2 == "KEYREVOKED" { print $2 }')"
if [ -n "$revoked" ]; then
    printf "install-swift: the key that signed %s has been revoked; check swift.org's install page for its current key\n" "$url" >&2
    exit 1
fi

actual_sha256="$(/usr/bin/sha256sum "$tarball" | /usr/bin/cut -d ' ' -f 1)"
printf 'install-swift: SHA-256 of %s-%s.tar.gz: %s\n' "$tag" "$platform" "$actual_sha256"
if [ -n "$expected_sha256" ] && [ "$actual_sha256" != "$expected_sha256" ]; then
    printf 'install-swift: %s has SHA-256 %s, expected %s\n' "$url" "$actual_sha256" "$expected_sha256" >&2
    exit 1
fi

/usr/bin/tar -xzf "$tarball" --directory / --strip-components=1 --no-same-owner
status=$?
if [ "$status" -ne 0 ]; then
    printf 'install-swift: unpacking the toolchain into /usr failed (tar status %s)\n' "$status" >&2
    exit 1
fi

# The tarball's folders keep swift.org's modes; every user must be able to read the toolchain.
for folder in /usr/lib/swift /usr/lib/swift_static; do
    if [ -d "$folder" ]; then
        /bin/chmod -R o+rX "$folder"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'install-swift: making %s readable failed (chmod status %s)\n' "$folder" "$status" >&2
            exit 1
        fi
    fi
done

installed="$(/usr/bin/swift --version 2>/dev/null | /usr/bin/head -n 1)"
case "$installed" in
    *"($tag)"*)
        printf 'install-swift: installed %s\n' "$installed"
        ;;
    *)
        printf 'install-swift: after unpacking, swift --version says: %s\n' "$installed" >&2
        exit 1
        ;;
esac
