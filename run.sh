#!/usr/bin/env bash
# ConfGen Remote Runner for direct curl execution:
# bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/feat/confgen-python-protoswap-benchmark/run.sh) <commands...>
set -e

BRANCH="${CONFGEN_BRANCH:-feat/confgen-python-protoswap-benchmark}"
REPO="EbadiDev/conf-gen"
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

WORKDIR="/tmp/confgen_${UID:-0}"
mkdir -p "$WORKDIR"

# Fetch latest archive from GitHub
curl -sSL "$ARCHIVE_URL" | tar -xz -C "$WORKDIR"
EXTRACTED=$(find "$WORKDIR" -maxdepth 1 -type d -name "conf-gen-*" | head -n 1)
rm -rf "$WORKDIR/pkg"
mv "$EXTRACTED" "$WORKDIR/pkg"

exec python3 "$WORKDIR/pkg/confgen.py" "$@"
