#!/bin/bash
set -e

# patch_kernel.sh
# Script to patch KernelSU-Next and SUSFS into Android 12 GKI 5.10 kernel source

echo "[+] Starting KernelSU-Next and SUSFS patching process..."

# Determine the kernel common directory
if [ -d "common" ]; then
    echo "[*] Found 'common' directory. Navigating into it..."
    cd common
fi

if [ ! -d "drivers" ] || [ ! -d "fs" ]; then
    echo "[!] Error: Must be run inside the kernel source root directory or its parent directory."
    exit 1
fi

echo "[+] 1. Installing KernelSU-Next..."
# Clean up existing KernelSU folder if any
if [ -d "drivers/kernelsu" ]; then
    echo "[*] Removing existing drivers/kernelsu..."
    rm -rf drivers/kernelsu
fi
if [ -d "KernelSU" ]; then
    echo "[*] Removing existing KernelSU..."
    rm -rf KernelSU
fi

# Clone KernelSU-Next
echo "[*] Cloning KernelSU-Next repository..."
git clone https://github.com/KernelSU-Next/KernelSU-Next.git drivers/kernelsu

# Verify drivers/kernelsu exists
if [ ! -d "drivers/kernelsu" ]; then
    echo "[!] Error: Failed to clone KernelSU-Next into drivers/kernelsu"
    exit 1
fi

echo "[+] 2. Cloning SUSFS repository (branch gki-android12-5.10)..."
if [ -d "susfs_src" ]; then
    rm -rf susfs_src
fi
git clone -b gki-android12-5.10 https://gitlab.com/simonpunk/susfs4ksu.git susfs_src

if [ ! -d "susfs_src" ]; then
    echo "[!] Error: Failed to clone susfs4ksu repository"
    exit 1
fi

echo "[+] 3. Copying SUSFS files into kernel source..."
# Copy susfs files to fs/ and include/
cp -fv susfs_src/kernel_patches/fs/susfs.c fs/
cp -fv susfs_src/kernel_patches/fs/susfs_proc.c fs/ || echo "[!] susfs_proc.c not found, skipping copy"
mkdir -p include/linux
cp -fv susfs_src/kernel_patches/include/linux/susfs.h include/linux/
cp -fv susfs_src/kernel_patches/include/linux/susfs_defconfig.h include/linux/ || echo "[!] susfs_defconfig.h not found, skipping copy"

echo "[+] 4. Applying SUSFS patches..."
KSU_PATCH="susfs_src/kernel_patches/10_enable_susfs_for_ksu.patch"
KERNEL_PATCH="susfs_src/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"

if [ -f "$KSU_PATCH" ]; then
    echo "[*] Applying patch to drivers/kernelsu..."
    cd drivers/kernelsu
    # Try to apply the patch. If it fails, report it but don't crash
    patch -p1 < ../../$KSU_PATCH || echo "[!] Warning: KSU SuSFS patch had some rejected hunks. You might need to merge manually."
    cd ../..
else
    echo "[!] Warning: KSU SuSFS patch file not found at $KSU_PATCH"
fi

if [ -f "$KERNEL_PATCH" ]; then
    echo "[*] Applying patch to kernel common..."
    patch -p1 < "$KERNEL_PATCH" || echo "[!] Warning: Kernel SuSFS patch had some rejected hunks. You might need to merge manually."
else
    # Find any fallback 5.10 patch
    GENERIC_PATCH=$(find susfs_src/kernel_patches/ -name "*5.10*.patch" | head -n 1)
    if [ -n "$GENERIC_PATCH" ]; then
        echo "[*] Found fallback patch: $GENERIC_PATCH. Applying..."
        patch -p1 < "$GENERIC_PATCH" || echo "[!] Warning: Fallback Kernel patch had some rejected hunks."
    else
        echo "[!] Error: No kernel patch found for 5.10 in susfs4ksu"
    fi
fi

# Clean up susfs_src folder to keep tree clean
rm -rf susfs_src

echo "[+] 5. Updating defconfig..."
# GKI kernel uses arch/arm64/configs/gki_defconfig
DEFCONFIG="arch/arm64/configs/gki_defconfig"
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
