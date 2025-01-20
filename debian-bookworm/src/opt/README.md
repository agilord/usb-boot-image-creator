Put your scripts and related files here, they will be copied to the
`/opt/custom-boot/` directory of the final image.

The `setup-build.sh` (if exists) will be run from the main script
(outside the chrooted environment) and then will be deleted.

The `setup-chroot.sh` (if exists) will be run from the main script
(inside the chrooted environment) and then will be deleted.

This `README.md` file will be deleted.
