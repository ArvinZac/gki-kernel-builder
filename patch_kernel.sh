#!/bin/bash
set -e

# patch_kernel.sh
# Script to patch KernelSU-Next and SUSFS into Android 12 GKI 5.10 kernel source.
# Must be run from the workspace root, i.e. the directory that directly
# contains the "common" kernel source checkout (as produced by `repo sync`).

echo "[+] Starting KernelSU-Next and SUSFS patching process..."

if [ ! -d "common/drivers" ] || [ ! -d "common/fs" ]; then
    echo "[!] Error: 'common/drivers' and 'common/fs' not found. Run this script from the workspace root (the directory containing 'common/')."
    exit 1
fi

echo "[+] 1. Cloning KernelSU-Next..."
rm -rf KernelSU-Next
git clone https://github.com/KernelSU-Next/KernelSU-Next.git

echo "[+] 2. Cloning SUSFS repository (branch gki-android12-5.10)..."
rm -rf susfs_src
git clone -b gki-android12-5.10 https://gitlab.com/simonpunk/susfs4ksu.git susfs_src

echo "[+] 3. Applying SUSFS patch to KernelSU-Next driver source..."
KSU_PATCH="susfs_src/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
if [ -f "$KSU_PATCH" ]; then
    cd KernelSU-Next
    patch -p1 < "../$KSU_PATCH" || echo "[!] Warning: KSU SuSFS patch had some rejected hunks. You might need to merge manually."
    cd ..
else
    echo "[!] Warning: KSU SuSFS patch file not found at $KSU_PATCH"
fi

echo "[+] 4. Wiring KernelSU-Next into common/drivers (Kconfig + Makefile)..."
cd common/drivers
ln -sf ../../KernelSU-Next/kernel kernelsu
grep -q 'kernelsu/' Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> Makefile
grep -q 'drivers/kernelsu/Kconfig' Kconfig || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' Kconfig
cd ../..

echo "[+] 5. Copying SUSFS core files into kernel source..."
cp -fv susfs_src/kernel_patches/fs/susfs.c common/fs/
cp -fv susfs_src/kernel_patches/fs/susfs_proc.c common/fs/ || echo "[!] susfs_proc.c not found, skipping copy"
mkdir -p common/include/linux
cp -fv susfs_src/kernel_patches/include/linux/susfs.h common/include/linux/
cp -fv susfs_src/kernel_patches/include/linux/susfs_def.h common/include/linux/ || echo "[!] susfs_def.h not found, skipping copy"

echo "[+] 6. Applying kernel-side SUSFS patch..."
cd common
KERNEL_PATCH="../susfs_src/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"
if [ -f "$KERNEL_PATCH" ]; then
    patch -p1 < "$KERNEL_PATCH" || echo "[!] Warning: Kernel SuSFS patch had some rejected hunks. You might need to merge manually."
else
    GENERIC_PATCH=$(find ../susfs_src/kernel_patches/ -maxdepth 1 -name "*5.10*.patch" | head -n 1)
    if [ -n "$GENERIC_PATCH" ]; then
        echo "[*] Found fallback patch: $GENERIC_PATCH. Applying..."
        patch -p1 < "$GENERIC_PATCH" || echo "[!] Warning: Fallback Kernel patch had some rejected hunks."
    else
        echo "[!] Error: No kernel patch found for 5.10 in susfs4ksu"
    fi
fi
cd ..

rm -rf susfs_src

echo "[+] 7. Updating defconfig..."
DEFCONFIG="common/arch/arm64/configs/gki_defconfig"
if [ -f "$DEFCONFIG" ]; then
    echo "[*] Appending KernelSU-Next and SuSFS configuration to $DEFCONFIG..."
    # Ensure options are not duplicated if script is re-run
    sed -i '/CONFIG_KSU/d' "$DEFCONFIG"
    cat <<EOF >> "$DEFCONFIG"

# KernelSU-Next and SUSFS
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
EOF
    echo "[+] defconfig successfully updated."
else
    echo "[!] Warning: defconfig not found at $DEFCONFIG. Please manually enable KernelSU & SUSFS configurations in your device's defconfig."
fi

echo "[+] Patching completed successfully!"
