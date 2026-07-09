#!/bin/bash
set -euo pipefail

# patch_kernel.sh
# Script to patch KernelSU and SUSFS into Android 12 GKI 5.10 kernel source.
# Must be run from the workspace root, i.e. the directory that directly
# contains the "common" kernel source checkout (as produced by `repo sync`).

echo "[+] Starting KernelSU and SUSFS patching process..."

if [ ! -d "common/drivers" ] || [ ! -d "common/fs" ]; then
    echo "[!] Error: 'common/drivers' and 'common/fs' not found. Run this script from the workspace root (the directory containing 'common/')."
    exit 1
fi

echo "[+] 1. Cloning KernelSU..."
rm -rf KernelSU
git clone --depth=1 https://github.com/tiann/KernelSU.git

echo "[+] 2. Cloning SUSFS repository (branch gki-android12-5.10)..."
rm -rf susfs_src
git clone --depth=1 -b gki-android12-5.10 https://gitlab.com/simonpunk/susfs4ksu.git susfs_src

echo "[+] 3. Applying SUSFS patch to KernelSU driver source..."
KSU_PATCH="susfs_src/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
if [ ! -f "$KSU_PATCH" ]; then
    echo "[!] Error: KSU SuSFS patch not found at $KSU_PATCH"
    exit 1
fi
cd KernelSU
patch -p1 --no-backup-if-mismatch < "../$KSU_PATCH"
cd ..

echo "[+] 4. Wiring KernelSU into common/drivers (Kconfig + Makefile)..."
cd common/drivers
ln -sf ../../KernelSU/kernel kernelsu
grep -q 'kernelsu/' Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> Makefile
grep -q 'drivers/kernelsu/Kconfig' Kconfig || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' Kconfig
cd ../..

echo "[+] 5. Copying SUSFS core files into kernel source..."
cp -fv susfs_src/kernel_patches/fs/susfs.c common/fs/
cp -fv susfs_src/kernel_patches/fs/susfs_proc.c common/fs/ 2>/dev/null || true
mkdir -p common/include/linux
cp -fv susfs_src/kernel_patches/include/linux/susfs.h common/include/linux/
cp -fv susfs_src/kernel_patches/include/linux/susfs_def.h common/include/linux/ 2>/dev/null || true

echo "[+] 6. Applying kernel-side SUSFS patch..."
cd common
KERNEL_PATCH="../susfs_src/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"
if [ -f "$KERNEL_PATCH" ]; then
    patch -p1 --no-backup-if-mismatch < "$KERNEL_PATCH"
else
    GENERIC_PATCH=$(find ../susfs_src/kernel_patches/ -maxdepth 1 -name "*5.10*.patch" | head -n 1)
    if [ -n "$GENERIC_PATCH" ]; then
        echo "[*] Found fallback patch: $GENERIC_PATCH. Applying..."
        patch -p1 --no-backup-if-mismatch < "$GENERIC_PATCH"
    else
        echo "[!] Error: No kernel patch found for 5.10 in susfs4ksu"
        exit 1
    fi
fi
cd ..

rm -rf susfs_src

echo "[+] Patching completed successfully!"
echo "[*] Note: CONFIG_KSU and all CONFIG_KSU_SUSFS_* options default to 'y' in Kconfig,"
echo "[*]       so no defconfig modification is needed (check_defconfig will pass)."
