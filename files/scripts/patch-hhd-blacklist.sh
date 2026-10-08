#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -oue pipefail

# HHD 4.1.12 logs "Skipping blacklisted provider" for entries in
# /etc/hhd/plugins.yml but never skips them (the `continue` is missing), so the
# blacklisted overlay still loads. Its hhd-ui crashes in gamescope and keeps the
# controller grabbed, which stops gamepad input from reaching Steam.
#
# Insert the missing `continue`. Fail the build if upstream code changed, so a
# new HHD release gets reviewed instead of silently patched (or not).
#
# Usage: patch-hhd-blacklist.sh [path/to/hhd/__main__.py]

target="${1:-}"
if [[ -z "$target" ]]; then
    target="$(python3 -c 'import hhd, os; print(os.path.join(os.path.dirname(hhd.__file__), "__main__.py"))')"
fi

python3 - "$target" <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()
logline = "                logger.info(f\"Skipping blacklisted provider '{name}'.\")\n"
broken = "            if name in blacklist:\n" + logline + "            if whitelist"
fixed = "            if name in blacklist:\n" + logline + "                continue\n            if whitelist"

if fixed in src:
    print(f"{path}: blacklist already honoured, nothing to do.")
elif src.count(broken) == 1:
    open(path, "w").write(src.replace(broken, fixed))
    print(f"{path}: patched blacklist handling.")
else:
    sys.exit(f"{path}: HHD blacklist code changed upstream; review files/scripts/patch-hhd-blacklist.sh.")
PY

# Refresh bytecode so the stale RPM .pyc files are not used.
if [[ -z "${1:-}" ]]; then
    python3 -m compileall -q --invalidation-mode unchecked-hash "$target"
    python3 -O -m compileall -q --invalidation-mode unchecked-hash "$target"
fi
