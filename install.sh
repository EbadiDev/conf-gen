#!/usr/bin/env bash
# ==============================================================================
# ConfGen One-Line Installer & Runner (BackPack-Style)
#
# Install & Open Menu:
#   bash <(curl -fsSL https://raw.githubusercontent.com/EbadiDev/conf-gen/feat/confgen-python-protoswap-benchmark/install.sh)
#
# Install & Run Direct Command (e.g. Kharej Link Apply):
#   bash <(curl -fsSL https://raw.githubusercontent.com/EbadiDev/conf-gen/feat/confgen-python-protoswap-benchmark/install.sh) link apply 'confgen://...'
# ==============================================================================

set -e

REPO="EbadiDev/conf-gen"
BRANCH="${CONFGEN_BRANCH:-feat/confgen-python-protoswap-benchmark}"
ZIP_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/confgen.zip?t=$(date +%s)"

if [ "$(id -u)" -eq 0 ]; then
    TARGET_DIR="/usr/local/bin"
else
    TARGET_DIR="${HOME}/.local/bin"
fi
TARGET_BIN="${TARGET_DIR}/confgen"
mkdir -p "$TARGET_DIR"

# Ensure Python 3 is installed
if ! command -v python3 >/dev/null 2>&1; then
    echo "[INFO] Python 3 not found. Installing Python 3..."
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq python3 python3-pip >/dev/null 2>&1 || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm python >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y python3 >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y python3 >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk add python3 >/dev/null 2>&1 || true
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] Python 3 is required but could not be installed automatically." >&2
    exit 1
fi

TMP_FILE="$(mktemp /tmp/confgen.XXXXXX)"
echo "[INFO] Downloading ConfGen standalone package from GitHub..."
if ! curl -fsSL -H "Cache-Control: no-cache, no-store" --connect-timeout 10 --max-time 45 --retry 3 "$ZIP_URL" -o "$TMP_FILE"; then
    echo "[ERROR] Failed to download ConfGen from GitHub. Check network/DNS connectivity." >&2
    rm -f "$TMP_FILE"
    exit 1
fi

# Prepend python3 shebang to zip archive to create a standalone executable binary
{
    printf '#!/usr/bin/env python3\n'
    cat "$TMP_FILE"
} > "${TARGET_BIN}.tmp"
rm -f "$TMP_FILE"
chmod +x "${TARGET_BIN}.tmp"
mv -f "${TARGET_BIN}.tmp" "$TARGET_BIN"

# Ensure TARGET_DIR is in PATH
if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
    export PATH="$TARGET_DIR:$PATH"
fi

echo "[SUCCESS] ConfGen installed to $TARGET_BIN"

# If arguments were provided (e.g. link apply '...'), execute immediately
if [ "$#" -gt 0 ]; then
    exec "$TARGET_BIN" "$@"
fi

# If interactive terminal and no args, launch ConfGen BackPack menu
if [ -t 0 ]; then
    exec "$TARGET_BIN"
fi
