#!/usr/bin/env bash
#
# Package the web app into a self-contained, symlink-free directory that can be
# zipped or deployed as-is. Resolves the web/ symlinks to real files and copies
# only the core ActionUIWeb runtime, skipping README, demo, test, scripts.
# Output: out/<AppName>/  (gitignored)
#

HERE="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$HERE" ]; then
  echo "error: could not resolve the script directory" >&2
  exit 1
fi

APP="$(/usr/bin/basename "$HERE")"
WEB="$HERE/web"
OUT="$HERE/out/$APP"

if [ ! -d "$WEB" ]; then
  echo "error: web/ not found at $WEB" >&2
  exit 1
fi
if [ ! -e "$WEB/actionui" ]; then
  echo "error: $WEB/actionui (ActionUIWeb symlink) is missing or dangling" >&2
  exit 1
fi

/bin/rm -rf "$OUT"
if [ $? -ne 0 ]; then
  echo "error: could not clear $OUT" >&2
  exit 1
fi

/bin/mkdir -p "$OUT"
if [ $? -ne 0 ]; then
  echo "error: could not create $OUT" >&2
  exit 1
fi

# 1. App files: copy everything in web/ EXCEPT the `actionui` runtime symlink,
#    dereferencing links (-L) so the JSON symlink lands as a real file.
shopt -s dotglob nullglob
for item in "$WEB"/*; do
  name="$(/usr/bin/basename "$item")"
  if [ "$name" = "actionui" ]; then
    continue
  fi
  /bin/cp -RL "$item" "$OUT/$name"
  if [ $? -ne 0 ]; then
    echo "error: failed to copy $item -> $OUT/$name" >&2
    shopt -u dotglob nullglob
    exit 1
  fi
done
shopt -u dotglob nullglob

# 2. ActionUIWeb runtime: copy the resolved core, then drop the non-runtime parts.
/bin/cp -RL "$WEB/actionui" "$OUT/actionui"
if [ $? -ne 0 ]; then
  echo "error: failed to copy the ActionUIWeb runtime from $WEB/actionui" >&2
  exit 1
fi

/bin/rm -rf "$OUT/actionui/demo" "$OUT/actionui/scripts" "$OUT/actionui/test"
if [ $? -ne 0 ]; then
  echo "warning: could not remove some non-runtime ActionUIWeb dirs" >&2
fi

/bin/rm -f "$OUT"/actionui/README*
if [ $? -ne 0 ]; then
  echo "warning: could not remove ActionUIWeb README files" >&2
fi

echo "Packaged $APP -> $OUT"
echo "Serve it with:  ( cd '$OUT' && python3 -m http.server 8080 )"
