#!/usr/bin/env bash
# ConfGen Remote Runner for direct curl execution:
# bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/feat/confgen-python-protoswap-benchmark/run.sh) <commands...>
set -e

BRANCH="${CONFGEN_BRANCH:-feat/confgen-python-protoswap-benchmark}"
REPO="EbadiDev/conf-gen"
WORKDIR="/tmp/confgen_${UID:-0}"
mkdir -p "$WORKDIR"

# Primary: Download ultra-lightweight standalone bundle (31KB) from raw.githubusercontent.com
# (Same CDN domain that successfully served this runner script)
ZIP_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/confgen.zip"
if curl -fsSL --connect-timeout 8 --max-time 30 --retry 3 "$ZIP_URL" -o "$WORKDIR/confgen.zip" 2>/dev/null && [ -s "$WORKDIR/confgen.zip" ]; then
    exec python3 "$WORKDIR/confgen.zip" "$@"
fi

# Fallback 1: Codeload endpoint
TAR_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}"
if curl -fsSL --connect-timeout 8 --max-time 60 --retry 3 "$TAR_URL" -o "$WORKDIR/confgen.tar.gz" 2>/dev/null && [ -s "$WORKDIR/confgen.tar.gz" ]; then
    rm -rf "$WORKDIR/pkg"
    mkdir -p "$WORKDIR/pkg"
    tar -xzf "$WORKDIR/confgen.tar.gz" -C "$WORKDIR/pkg" --strip-components=1
    exec python3 "$WORKDIR/pkg/confgen.py" "$@"
fi

# Fallback 2: Cached bundle from prior run
if [ -s "$WORKDIR/confgen.zip" ]; then
    exec python3 "$WORKDIR/confgen.zip" "$@"
fi

echo "[ERROR] Failed to fetch ConfGen package from GitHub. Please check network/DNS connectivity." >&2
exit 1
