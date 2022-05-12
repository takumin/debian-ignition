FROM debian:stable-slim
RUN apt-get update && apt-get install -yqq mmdebstrap qemu-user-static xz-utils pixz squashfs-tools-ng
