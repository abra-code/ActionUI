"""
Platform-suffix awareness for the verifier.

Mirrors the platform token set in:
  - ActionUI/Common/PlatformFilter.swift          (`PlatformFilter.allPlatforms`)
  - ActionUIAndroid/library/.../PlatformFilter.kt (`PlatformFilter.ALL_PLATFORMS`)

A key like `text:ios` is a platform-specific variant of `text`. The runtime
filter rewrites it to `text` on iOS and drops it elsewhere. The verifier
mirrors this:

  - Known suffix (in ALL_PLATFORMS): treat as a valid variant of the base key.
  - Unknown suffix: warn (key will be dropped at runtime), skip validation
    of the value. Catches typos like `tint:Android` (capital A).

Both filters must agree on this set so a JSON file's "known platform tokens"
don't depend on which platform is reading it.
"""
from __future__ import annotations

ALL_PLATFORMS: frozenset[str] = frozenset({
    "ios", "macos", "tvos", "watchos", "visionos", "apple",
    "android", "androidtv", "wear",
    "desktop", "web",
})


def split_platform_suffix(key: str) -> tuple[str, str | None]:
    """Split a key on its last colon.

    Returns (base, suffix-or-None). A key without ':' returns (key, None).
    A key with ':' always returns the split, regardless of whether the
    suffix is a known platform — callers check ALL_PLATFORMS membership
    to distinguish real platform tags from typos.
    """
    idx = key.rfind(":")
    if idx < 0:
        return key, None
    return key[:idx], key[idx + 1:]


def format_suffix_label(base: str, suffix: str | None) -> str:
    """Render `base[:suffix]` for use in error/warning messages."""
    return base if suffix is None else f"{base}:{suffix}"
