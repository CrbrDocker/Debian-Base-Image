# Wraps a debootstrap rootfs tarball (produced by build_base_system.sh) into a
# single-layer image. Not a standalone build: the context must contain the
# matching `rootfs.tar`. Used by build_base_system.sh (local) and the CI workflow.
FROM scratch
ARG IMAGE_VERSION=""
ARG IMAGE_REVISION=""
ARG IMAGE_CREATED=""
ARG IMAGE_SOURCE=""
ADD rootfs.tar /
LABEL org.opencontainers.image.title="debian" \
      org.opencontainers.image.description="Minimal Debian base image" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}"
CMD ["/bin/bash"]
