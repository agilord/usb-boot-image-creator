#!/bin/bash

set -e

BUILD_DIR="/build"
BUILD_ROOT="/build/root"
CUSTOM_OPT_DIR="/opt/custom-boot"
mkdir -p "${BUILD_ROOT}"

# Bootstrap and Configure Debian
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    stable \
    "${BUILD_ROOT}" \
    "${DEBIAN_MIRROR}"

## Set a custom hostname for your Debian environment.
echo "${HOSTNAME}" >"${BUILD_ROOT}"/etc/hostname

## Install a Linux kernel of your choosing.
chroot "${BUILD_ROOT}" << EOF
apt update && \
apt install -y --no-install-recommends \
    linux-image-amd64 \
    live-boot \
    systemd-sysv
EOF

## Install programs of your choosing...
chroot "${BUILD_ROOT}" << EOF
apt install -y --no-install-recommends \
    curl \
    less \
    nano \
    openssh-client \
    wget;

# Set the root password. root will be the only user in this live environment by default, but you may add additional users as needed.
echo "${ROOT_PASSWORD}\n${ROOT_PASSWORD}" | passwd root
EOF

## Install programs from the opt directory...
mkdir -p "${BUILD_ROOT}"/opt
cp -r "${BUILD_DIR}"/opt "${BUILD_ROOT}${CUSTOM_OPT_DIR}"

if [ -f "${BUILD_ROOT}${CUSTOM_OPT_DIR}/setup-build.sh" ]; then
  "${BUILD_ROOT}${CUSTOM_OPT_DIR}/setup-build.sh"
  rm "${BUILD_ROOT}${CUSTOM_OPT_DIR}/setup-build.sh"
fi

if [ -f "${BUILD_ROOT}${CUSTOM_OPT_DIR}/setup-chroot.sh" ]; then
  chroot "${BUILD_ROOT}" "${CUSTOM_OPT_DIR}/setup-chroot.sh"
  rm "${BUILD_ROOT}${CUSTOM_OPT_DIR}/setup-chroot.sh"
fi


## Create directories that will contain files for our live environment files and scratch files
mkdir -p "${BUILD_DIR}"/{staging/{EFI/BOOT,boot/grub/x86_64-efi,isolinux,live},tmp}

## Compress the chroot environment into a Squash filesystem.
mksquashfs \
    "${BUILD_ROOT}" \
    "${BUILD_DIR}/staging/live/filesystem.squashfs" \
    -e boot

## Copy the kernel and initramfs from inside the chroot to the live directory.
cp "${BUILD_ROOT}/boot"/vmlinuz-* "${BUILD_DIR}/staging/live/vmlinuz"
cp "${BUILD_ROOT}/boot"/initrd.img-* "${BUILD_DIR}/staging/live/initrd"


# Prepare Boot Loader Menus

## Create an ISOLINUX (Syslinux) boot menu. This boot menu is used when booting in BIOS/legacy mode.
cat <<'EOF' >"${BUILD_DIR}/staging/isolinux/isolinux.cfg"
UI vesamenu.c32

MENU TITLE Boot Menu
DEFAULT linux
TIMEOUT 600
MENU RESOLUTION 640 480
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

LABEL linux
  MENU LABEL Debian Live [BIOS/ISOLINUX]
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live

LABEL linux
  MENU LABEL Debian Live [BIOS/ISOLINUX] (nomodeset)
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live nomodeset
EOF

## Create a second, similar, boot menu for GRUB. This boot menu is used when booting in EFI/UEFI mode.
cat <<'EOF' >"${BUILD_DIR}/staging/boot/grub/grub.cfg"
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660

insmod all_video
insmod font

set default="0"
set timeout=30

# If X has issues finding screens, experiment with/without nomodeset.

menuentry "Debian Live [EFI/GRUB]" {
    search --no-floppy --set=root --label DEBLIVE
    linux ($root)/live/vmlinuz boot=live
    initrd ($root)/live/initrd
}

menuentry "Debian Live [EFI/GRUB] (nomodeset)" {
    search --no-floppy --set=root --label DEBLIVE
    linux ($root)/live/vmlinuz boot=live nomodeset
    initrd ($root)/live/initrd
}
EOF

## Copy the grub.cfg file to the EFI BOOT directory.
cp "${BUILD_DIR}/staging/boot/grub/grub.cfg" "${BUILD_DIR}/staging/EFI/BOOT/"

## Create a third boot config.
## This config will be an early configuration file that is embedded inside GRUB in the EFI partition.
## This finds the root and loads the GRUB config from there.
cat <<'EOF' > "${BUILD_DIR}/tmp/grub-embed.cfg"
if ! [ -d "$cmdpath" ]; then
    # On some firmware, GRUB has a wrong cmdpath when booted from an optical disc.
    # https://gitlab.archlinux.org/archlinux/archiso/-/issues/183
    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
        cmdpath="${isodevice}/EFI/BOOT"
    fi
fi
configfile "${cmdpath}/grub.cfg"
EOF

# Prepare Boot Loader Files

## Copy BIOS/legacy boot required files into our workspace.
cp /usr/lib/ISOLINUX/isolinux.bin "${BUILD_DIR}/staging/isolinux/" && \
cp /usr/lib/syslinux/modules/bios/* "${BUILD_DIR}/staging/isolinux/"

## Copy EFI/modern boot required files into our workspace.
cp -r /usr/lib/grub/x86_64-efi/* "${BUILD_DIR}/staging/boot/grub/x86_64-efi/"

## Generate an EFI bootable GRUB image.
grub-mkstandalone -O i386-efi \
    --modules="part_gpt part_msdos fat iso9660" \
    --locales="" \
    --themes="" \
    --fonts="" \
    --output="${BUILD_DIR}/staging/EFI/BOOT/BOOTIA32.EFI" \
    "boot/grub/grub.cfg=${BUILD_DIR}/tmp/grub-embed.cfg"

grub-mkstandalone -O x86_64-efi \
    --modules="part_gpt part_msdos fat iso9660" \
    --locales="" \
    --themes="" \
    --fonts="" \
    --output="${BUILD_DIR}/staging/EFI/BOOT/BOOTx64.EFI" \
    "boot/grub/grub.cfg=${BUILD_DIR}/tmp/grub-embed.cfg"

## Create a FAT16 UEFI boot disk image containing the EFI bootloaders.
(cd "${BUILD_DIR}/staging" && \
    dd if=/dev/zero of=efiboot.img bs=1M count=20 && \
    mkfs.vfat efiboot.img && \
    mmd -i efiboot.img ::/EFI ::/EFI/BOOT && \
    mcopy -vi efiboot.img \
        "${BUILD_DIR}/staging/EFI/BOOT/BOOTIA32.EFI" \
        "${BUILD_DIR}/staging/EFI/BOOT/BOOTx64.EFI" \
        "${BUILD_DIR}/staging/boot/grub/grub.cfg" \
        ::/EFI/BOOT/
)

## Create Bootable ISO/CD
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "${BUILD_DIR}/out/live.iso" \
    -full-iso9660-filenames \
    -volid "DEBLIVE" \
    --mbr-force-bootable -partition_offset 16 \
    -joliet -joliet-long -rational-rock \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot \
        isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
    -eltorito-alt-boot \
        -e --interval:appended_partition_2:all:: \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B ${BUILD_DIR}/staging/efiboot.img \
    "${BUILD_DIR}/staging"
