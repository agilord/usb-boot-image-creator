FROM debian:bookworm-slim

# Prerequisites
## Install applications needed to build the live environment.
RUN apt update && apt-get upgrade -y
RUN apt install -y --no-install-recommends \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-common \
    syslinux-efi \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-ia32-bin \
    mtools \
    dosfstools;

RUN mkdir -p /build/out
RUN mkdir -p /build/root

COPY bin/ /build/bin
COPY opt/ /build/opt
RUN rm /build/opt/README.md

ENV DEBIAN_MIRROR="http://ftp.us.debian.org/debian/"
ENV HOSTNAME="live-usb"
ENV ROOT_PASSWORD="live"

ENTRYPOINT ["/bin/bash", "/build/bin/script.sh"]
