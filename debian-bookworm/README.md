Creates Debian (`bookworm`) Linux USB boot image using dockerized build
environment, allowing also custom scripts to be run easily.

The script (mostly) follows the steps outlined in the article here:
https://www.willhaley.com/blog/custom-debian-live-environment/

# Usage

1. `git clone` the repository.
1. Put optional files in `src/opt/` directory.
1. run `docker build ./src/ -t usb-boot-image-creator`
1. run `docker run -v ./out:/out usb-boot-image-creator`
