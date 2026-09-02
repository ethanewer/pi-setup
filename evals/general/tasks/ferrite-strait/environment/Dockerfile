FROM bench-base:ubuntu-24.04

WORKDIR /app

# Toolchain for the firmware-stage kiosk appliance: qemu (TCG, no KVM) for the
# emulated machine and its VNC display, busybox-static as the tiny HTTP/CGI
# host for the monitoring web plane, iproute2 for listener inspection.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        qemu-system-x86 \
        busybox-static \
        iproute2 \
        file \
 && apt-get clean
