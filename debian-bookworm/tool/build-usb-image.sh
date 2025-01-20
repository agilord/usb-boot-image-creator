#!/bin/bash -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

docker run -v ./out:/build/out -e DEBIAN_MIRROR="http://ftp.bme.hu/debian/" usb-boot-image-creator
