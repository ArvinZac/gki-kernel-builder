# Panduan Lengkap Build Kernel GKI Android 12 (5.10) dengan KernelSU-Next & SuSFS

Panduan ini berisi langkah-demi-langkah untuk membangun (build) kernel **Generic Kernel Image (GKI)** versi 5.10 (KMI `android12-9`) yang telah dipatch dengan **KernelSU-Next** dan **SuSFS**.

Ada dua metode yang dapat digunakan:
1. **Metode GitHub Actions (Sangat Direkomendasikan)**: Proses build berjalan otomatis di Cloud. Gratis, cepat, dan tidak memakan resource PC.
2. **Metode Kompilasi Lokal (WSL2 / Linux)**: Untuk kamu yang ingin melakukan build di komputer sendiri (membutuhkan minimal 150GB disk kosong dan RAM 16GB+).

---

## METODE 1: Menggunakan GitHub Actions (Rekomendasi)

Metode ini menggunakan workflow CI/CD GitHub untuk mempermudah proses kompilasi tanpa perlu mendownload source code berukuran puluhan gigabyte ke komputer lokal.

### Langkah-langkah:
1. **Buat Repository Baru di GitHub**:
   - Masuk ke akun GitHub kamu.
   - Buat repository baru (bisa disetel ke *Private* atau *Public*).
2. **Unggah File Konfigurasi**:
   - Salin folder `.github/` dan isinya dari project ini ke repository GitHub baru kamu.
   - Struktur folder di GitHub harus seperti ini:
     ```text
     namarepo/
     └── .github/
         └── workflows/
             └── build_gki.yml
     ```
3. **Aktifkan GitHub Actions**:
   - Di repository GitHub kamu, klik tab **Actions**.
   - Jika ada peringatan, klik tombol hijau **"I understand my workflows, go ahead and enable them"**.
4. **Jalankan Workflow**:
   - Di tab **Actions**, pilih workflow **"Build GKI Kernel 5.10 with KSU-Next and SuSFS"** di menu sebelah kiri.
   - Klik menu drop-down **Run workflow** di sebelah kanan.
   - Kamu bisa menyesuaikan input parameter berikut jika ingin menggunakan source kernel khusus dari produsen HP kamu:
     * **Android Common Kernel Manifest Branch**: default `common-android12-5.10`
     * **Kernel Source Repo URL**: repository kernel yang ingin digunakan (bawaan: Google ACK `https://android.googlesource.com/kernel/common`).
     * **Kernel Source Repo Branch**: branch kernel (bawaan: `android12-5.10`).
     * **Build Config Target**: target konfigurasi build (bawaan: `common/build.config.gki.aarch64`).
   - Klik tombol **Run workflow** untuk memulai proses build.
5. **Download Hasil Build**:
   - Tunggu proses build selesai (biasanya memakan waktu 30–60 menit tergantung antrean runner GitHub).
   - Setelah selesai (centang hijau), klik pada nama run workflow tersebut.
   - Scroll ke bagian paling bawah di bawah sub-judul **Artifacts**.
   - Download file **`AnyKernel3-GKI-5.10-KSU-Next-SuSFS`** dalam format `.zip`.

---

## METODE 2: Kompilasi Lokal Menggunakan WSL2 (Windows)

Jika kamu ingin melakukan kompilasi di PC Windows kamu sendiri, gunakan **WSL2** dengan distro **Ubuntu** (direkomendasikan Ubuntu 22.04 LTS atau 24.04 LTS).

### Opsi Cepat: Script All-in-One

Kalau kamu tidak mau menjalankan langkah 1–5 satu-satu, gunakan `build_all_in_one.sh` yang menjalankan semuanya otomatis (install dependency → sync source → patch KSU-Next & SuSFS → compile → bikin zip AnyKernel3):
```bash
git clone https://github.com/ArvinZac/gki-kernel-builder.git
cd gki-kernel-builder
chmod +x build_all_in_one.sh
./build_all_in_one.sh
```
Hasil zip flashable akan ada di `~/gki-build/AnyKernel3-GKI-5.10-KSU-Next-SuSFS.zip`. Butuh disk kosong ±150GB dan RAM 16GB+. Kalau mau pakai manifest/branch/config kernel lain, override lewat env var, contoh:
```bash
KERNEL_BRANCH=android12-5.10 BUILD_CONFIG=common/build.config.gki.aarch64 ./build_all_in_one.sh
```

Kalau ingin paham/kontrol tiap langkahnya secara manual, ikuti langkah 1–5 di bawah ini.

### 1. Persiapan Environment
Buka terminal WSL2 Ubuntu kamu, lalu jalankan perintah berikut untuk menginstal package yang dibutuhkan:
```bash
sudo apt-get update
sudo apt-get install -y bc bison build-essential curl flex git gnupg gperf libelf-dev libssl-dev libxml2-utils lz4 python3 rsync unzip zip zstd
```

Instal tool `repo` dari Google:
```bash
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
```

### 2. Unduh Source Code GKI 5.10
Buat direktori kerja dan lakukan inisialisasi source code:
```bash
mkdir -p ~/gki-build
cd ~/gki-build

# Inisialisasi repo dengan depth 1 (untuk menghemat penyimpanan)
repo init -u https://android.googlesource.com/kernel/manifest -b common-android12-5.10 --depth=1

# Sinkronisasi source code (manifest common-android12-5.10 sudah otomatis
# ter-scope hanya ke project yang diperlukan untuk build aarch64)
repo sync -c -j$(nproc) --no-clone-bundle --no-tags --force-sync
```

### 3. Jalankan Script Patching
Salin file `patch_kernel.sh` yang sudah dibuat di workspace ini ke dalam direktori `~/gki-build/` di WSL2 kamu. Jalankan script tersebut:
```bash
chmod +x patch_kernel.sh
./patch_kernel.sh
```
Script ini akan otomatis:
1. Mengunduh source code **KernelSU-Next** ke `~/gki-build/KernelSU-Next`.
2. Mengunduh source code **SuSFS** cabang `gki-android12-5.10`.
3. Menerapkan patch SuSFS ke source KernelSU-Next.
4. Menyambungkan KernelSU-Next ke kernel lewat symlink `common/drivers/kernelsu` plus entri di `common/drivers/Kconfig` dan `common/drivers/Makefile` (tanpa ini, `CONFIG_KSU` tidak akan dikenali sama sekali oleh build system).
5. Menyalin file modul SuSFS (`susfs.c`, `susfs.h`, `susfs_def.h`) ke direktori kernel dan menerapkan patch SuSFS pada source kernel.
6. Mengaktifkan konfigurasi KernelSU dan SuSFS di `common/arch/arm64/configs/gki_defconfig`.

### 4. Proses Kompilasi Kernel
Setelah selesai melakukan patching, jalankan perintah kompilasi berikut:
```bash
BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
```
Proses ini akan memakan waktu tergantung spesifikasi CPU komputer kamu. Jika berhasil, file kernel binary `Image` dan modul kernel (`*.ko`) akan terletak di direktori `out/android12-5.10/dist/`.

### 5. Membuat File Flashable AnyKernel3
Buat paket flashable zip untuk mempermudah pemasangan ke HP kamu:
```bash
cd ~/gki-build
git clone https://github.com/osm0sis/AnyKernel3.git anykernel
rm -rf anykernel/.git

# Copy file Image hasil build ke folder AnyKernel3
cp out/android12-5.10/dist/Image anykernel/

# Salin modul kernel (*.ko) jika ada
mkdir -p anykernel/modules
find out/android12-5.10/dist/ -name "*.ko" -exec cp -f {} anykernel/modules/ \;
[ "$(ls -A anykernel/modules)" ] || rm -rf anykernel/modules

# Ubah konfigurasi anykernel.sh agar cocok untuk generic GKI
sed -i 's/do.devicecheck=1/do.devicecheck=0/g' anykernel/anykernel.sh
sed -i 's/block=boot/block=auto/g' anykernel/anykernel.sh

# Zip AnyKernel3
cd anykernel
zip -r ../AnyKernel3-GKI-5.10-KSU-Next-SuSFS.zip *
```
Sekarang, file `AnyKernel3-GKI-5.10-KSU-Next-SuSFS.zip` siap di-flash.

---

## CARA FLASH & KONFIGURASI

Setelah kamu mendapatkan file `.zip` AnyKernel3 (baik dari GitHub Actions atau build lokal):

### 1. Flash Kernel ke Perangkat
Ada beberapa cara untuk memasang zip tersebut:
* **Menggunakan Custom Recovery (TWRP / OrangeFox)**:
  1. Pindahkan file `.zip` ke memori internal/SD Card HP kamu.
  2. Boot ke Recovery Mode.
  3. Pilih **Install**, cari file `.zip` tersebut, lalu swipe untuk mengonfirmasi instalasi.
  4. Reboot System.
* **Menggunakan Aplikasi KernelFlasher (Jika perangkat sudah dalam kondisi Root)**:
  - Buka aplikasi KernelFlasher, pilih file `.zip` AnyKernel3 tersebut, lalu flash ke slot boot/init_boot yang aktif.

> [!WARNING]
> Sangat disarankan untuk mem-back up partisi `boot.img` bawaan kamu melalui recovery terlebih dahulu sebelum melakukan flashing. Jika terjadi bootloop, kamu tinggal restore `boot.img` stock tersebut melalui fastboot atau TWRP.

### 2. Pemasangan Manager & Modul Userspace
1. **Instal Manager**: Download dan pasang file APK **KernelSU-Next Manager** terbaru dari repository GitHub resmi `rifsxd/KernelSU-Next`.
2. **Pasang Modul SuSFS**:
   - Untuk mengaktifkan fitur perlindungan root hiding SuSFS secara penuh, instal modul **`susfs4ksu-module`** (oleh `sidex15`) lewat menu Modules di dalam KernelSU Manager.
   - Reboot perangkat kamu setelah modul selesai terpasang.
3. **Uji Coba**:
   - Buka kembali KernelSU Manager, pastikan status SuSFS aktif dan terdeteksi dengan benar.
   - Gunakan aplikasi pengecek integrity (seperti Play Integrity API Checker atau YASNAC) untuk menguji keefektifan sistem root hiding.
