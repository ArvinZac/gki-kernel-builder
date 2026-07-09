#!/bin/bash
set -e

# build_all_in_one.sh
# One-shot local build script for GKI Kernel 5.10 (android12-5.10) with
# KernelSU-Next and SuSFS, for use inside WSL2 Ubuntu (or native Ubuntu 22.04/24.04).
#
# Usage:
#   chmod +x build_all_in_one.sh
#   ./build_all_in_one.sh
#
# Optional environment overrides:
#   WORKDIR=~/gki-build MANIFEST_BRANCH=common-android12-5.10 \
#   KERNEL_BRANCH=android12-5.10 BUILD_CONFIG=common/build.config.gki.aarch64 \
#   ./build_all_in_one.sh

WORKDIR="${WORKDIR:-$HOME/gki-build}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-common-android12-5.10}"
KERNEL_BRANCH="${KERNEL_BRANCH:-android12-5.10}"
BUILD_CONFIG="${BUILD_CONFIG:-common/build.config.gki.aarch64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo " GKI 5.10 + KernelSU-Next + SuSFS — All-in-One Build"
echo "=================================================="
echo "Work directory : $WORKDIR"
echo "Manifest branch: $MANIFEST_BRANCH"
echo "Kernel branch  : $KERNEL_BRANCH"
echo "Build config   : $BUILD_CONFIG"
echo "=================================================="

echo
echo "[1/6] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y bc bison build-essential curl flex git gnupg gperf \
    libelf-dev libssl-dev libxml2-utils lz4 python3 rsync unzip zip zstd

if ! command -v repo >/dev/null 2>&1; then
    echo "[*] Installing 'repo' tool..."
    mkdir -p "$HOME/bin"
    curl -s https://storage.googleapis.com/git-repo-downloads/repo > "$HOME/bin/repo"
    chmod a+x "$HOME/bin/repo"
    export PATH="$PATH:$HOME/bin"
    grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH=$PATH:$HOME/bin' >> "$HOME/.bashrc"
fi

echo
echo "[2/6] Fetching GKI kernel source (repo init/sync)..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"
repo init -u https://android.googlesource.com/kernel/manifest -b "$MANIFEST_BRANCH" --depth=1
repo sync -c -j"$(nproc)" --no-clone-bundle --no-tags --force-sync

echo
echo "[3/6] Applying KernelSU-Next + SuSFS patches..."
cp -f "$SCRIPT_DIR/patch_kernel.sh" "$WORKDIR/"
chmod +x "$WORKDIR/patch_kernel.sh"
cd "$WORKDIR"
./patch_kernel.sh

echo
echo "[4/6] Building kernel..."
cd "$WORKDIR/common"
export PATH="$PATH:$HOME/bin"
BUILD_CONFIG="$BUILD_CONFIG" ../build/build.sh

echo
echo "[5/6] Packaging with AnyKernel3..."
cd "$WORKDIR"
DIST_DIR=$(find out -maxdepth 2 -type d -name dist | head -n 1)
if [ -z "$DIST_DIR" ] || [ ! -f "$DIST_DIR/Image" ]; then
    echo "[!] Error: build output (Image) not found under out/*/dist/. Build likely failed."
    exit 1
fi

rm -rf anykernel
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git anykernel
rm -rf anykernel/.git

cp -fv "$DIST_DIR/Image" anykernel/

mkdir -p anykernel/modules
find "$DIST_DIR" -name "*.ko" -exec cp -f {} anykernel/modules/ \;
[ "$(ls -A anykernel/modules)" ] || rm -rf anykernel/modules

sed -i 's/do.devicecheck=1/do.devicecheck=0/g' anykernel/anykernel.sh
sed -i 's/block=boot/block=auto/g' anykernel/anykernel.sh

cd anykernel
zip -r ../AnyKernel3-GKI-5.10-KSU-Next-SuSFS.zip * >/dev/null
cd ..

echo
echo "[6/6] Done!"
echo "=================================================="
echo "Flashable zip ready at:"
echo "  $WORKDIR/AnyKernel3-GKI-5.10-KSU-Next-SuSFS.zip"
echo "=================================================="
