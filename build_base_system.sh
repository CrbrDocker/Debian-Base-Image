#!/bin/bash
#
# build_base_system.sh
#
# Build a minimal, systemd-free Debian base rootfs from scratch and, optionally,
# import it as a single-layer Docker image.
#
# Linux only: needs debootstrap + chroot + root. The build is NATIVE (ARCH
# defaults to the host arch), so no qemu is involved when run on a matching
# runner. debian-archive-keyring must be present so debootstrap can verify the
# archive (install it alongside debootstrap).
#
# Params (positional or env):
#   SUITE  (arg1)  Debian codename to build: trixie, bookworm, sid, ...  [required]
#   ARCH   (arg2)  dpkg architecture to build for                        [default: host]
# Optional env:
#   ROOTFS      target rootfs directory       [default: ./rootfs-<suite>-<arch>]
#   MIRROR      Debian mirror                 [default: http://deb.debian.org/debian]
#   SECMIRROR   Debian security mirror        [default: http://deb.debian.org/debian-security]
#   IMAGE       if set, `docker import` the rootfs to this image reference
#   VCS_REF     git sha stamped as an OCI label   [default: git HEAD, else "unknown"]
#   BUILD_DATE  RFC3339 date stamped as a label   [default: now, UTC]
#   SOURCE_URL  repo URL for the OCI source label [default: derived from git remote]

set -euo pipefail

SUITE="${SUITE:-${1:-}}"
ARCH="${ARCH:-${2:-$(dpkg --print-architecture)}}"
if [ -z "$SUITE" ]; then
  echo "ERROR: SUITE (codename) is required.  Usage: $0 <suite> [arch]" >&2
  exit 1
fi

MIRROR="${MIRROR:-http://deb.debian.org/debian}"
SECMIRROR="${SECMIRROR:-http://deb.debian.org/debian-security}"
ROOTFS="${ROOTFS:-./rootfs-${SUITE}-${ARCH}}"
VCS_REF="${VCS_REF:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
# Source URL for the OCI label: use $SOURCE_URL, else derive from the git remote.
if [ -z "${SOURCE_URL:-}" ]; then
  _r="$(git remote get-url origin 2>/dev/null || true)"; _r="${_r%.git}"
  case "$_r" in
    git@*:*)            _r="${_r#git@}"; SOURCE_URL="https://${_r%%:*}/${_r#*:}" ;;
    ssh://*)            _r="${_r#ssh://}"; _r="${_r#*@}"; SOURCE_URL="https://${_r}" ;;
    http://*|https://*) SOURCE_URL="$_r" ;;
    *)                  SOURCE_URL="" ;;
  esac
fi

# Packages kept in every image. Anything tool-specific belongs in a derived
# `FROM` image, not here.
INCLUDE="wget,curl,ca-certificates,tzdata"
# Kept out from the first stage; also pinned to -1 below so nothing restores them.
EXCLUDE="systemd,systemd-sysv,dbus,apparmor,nano"
COMPONENTS="main contrib non-free non-free-firmware"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root (debootstrap/chroot need it)." >&2
  exit 1
fi

# Unmount the pseudo-filesystems whatever happens.
cleanup() {
  local m
  for m in dev/pts dev sys proc; do
    mountpoint -q "$ROOTFS/$m" && umount -lf "$ROOTFS/$m" || true
  done
}
trap cleanup EXIT

echo ">>> Building Debian '${SUITE}' (${ARCH}) into ${ROOTFS}"
rm -rf "$ROOTFS"

# Some runners ship a debootstrap that predates the target codename; fall back
# to the generic sid script (works for any modern Debian suite).
SCRIPTDIR=/usr/share/debootstrap/scripts
if [ ! -e "$SCRIPTDIR/$SUITE" ]; then
  echo ">>> debootstrap has no script for '${SUITE}'; linking it to sid"
  ln -sf sid "$SCRIPTDIR/$SUITE"
fi

# --- 1. Base rootfs -------------------------------------------------------
# minbase = the Essential set + apt only.
debootstrap \
  --arch="$ARCH" \
  --variant=minbase \
  --components="$(echo "$COMPONENTS" | tr ' ' ,)" \
  --include="$INCLUDE" \
  --exclude="$EXCLUDE" \
  "$SUITE" "$ROOTFS" "$MIRROR"

# --- 2. APT configuration -------------------------------------------------
# sources.list: main, plus -updates / -security only when that dist actually
# exists (so sid / testing don't get bogus entries).
dist_exists() { curl -sfL -o /dev/null "$1/dists/$2/Release"; }
{
  echo "deb ${MIRROR} ${SUITE} ${COMPONENTS}"
  if dist_exists "$MIRROR" "${SUITE}-updates"; then
    echo "deb ${MIRROR} ${SUITE}-updates ${COMPONENTS}"
  fi
  if dist_exists "$SECMIRROR" "${SUITE}-security"; then
    echo "deb ${SECMIRROR} ${SUITE}-security ${COMPONENTS}"
  fi
} > "$ROOTFS/etc/apt/sources.list"

# Keep derived builds lean by default.
cat > "$ROOTFS/etc/apt/apt.conf.d/90lean" <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests   "false";
EOF

# The real guard against a dependency dragging the init/dbus stack back in.
cat > "$ROOTFS/etc/apt/preferences.d/no-systemd" <<'EOF'
Package: systemd systemd-sysv dbus apparmor
Pin: release *
Pin-Priority: -1
EOF

# --- 3. Slimming ----------------------------------------------------------
# Keep man/info/docs/translations from coming back on future installs...
cat > "$ROOTFS/etc/dpkg/dpkg.cfg.d/99-slim" <<'EOF'
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/lintian/*
path-exclude=/usr/share/bug/*
path-exclude=/usr/share/doc-base/*
path-exclude=/usr/share/locale/*
EOF
# ...and drop what debootstrap already laid down (our rules only apply to
# packages configured after this point). Copyright files are kept for
# redistribution compliance.
rm -rf "$ROOTFS"/usr/share/man/* \
       "$ROOTFS"/usr/share/info/* \
       "$ROOTFS"/usr/share/lintian/* \
       "$ROOTFS"/usr/share/locale/* 2>/dev/null || true
find "$ROOTFS/usr/share/doc" -mindepth 1 ! -type d ! -name copyright -delete 2>/dev/null || true
find "$ROOTFS/usr/share/doc" -type d -empty -delete 2>/dev/null || true

# --- 4. Locale & timezone -------------------------------------------------
# No `locales` package: glibc's built-in C.UTF-8 gives correct UTF-8 + English.
echo 'LANG=C.UTF-8' > "$ROOTFS/etc/default/locale"
echo 'LANG=C.UTF-8' > "$ROOTFS/etc/environment"
# Timezone is left at tzdata's default (UTC). Consumers override at runtime with
# `-v /etc/localtime:/etc/localtime:ro` or `-e TZ=<zone>`.

# --- 5. Post-install inside the rootfs ------------------------------------
# Give the chroot working pseudo-fs + DNS for the upgrade, none of it baked in.
mkdir -p "$ROOTFS"/proc "$ROOTFS"/sys "$ROOTFS"/dev/pts
mount -t proc  proc "$ROOTFS/proc"
mount -t sysfs sys  "$ROOTFS/sys"
mount -o bind /dev     "$ROOTFS/dev"
mount -o bind /dev/pts "$ROOTFS/dev/pts"
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

cat > "$ROOTFS/tmp/post_inst.sh" <<'EOF'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

apt-get -y update
apt-get -y dist-upgrade

# Belt-and-suspenders purge; the pin should already prevent these existing.
apt-get -y purge 'systemd*' 'dbus*' 'apparmor*' 2>/dev/null || true
apt-get -y autoremove --purge

apt-get clean
apt-get autoclean
dpkg --clear-avail

rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin 2>/dev/null || true
rm -rf /var/lib/dpkg/*-old /var/cache/debconf/*-old /var/cache/ldconfig/aux-cache 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
find /var/log -type f -delete 2>/dev/null || true
EOF
chmod 755 "$ROOTFS/tmp/post_inst.sh"
chroot "$ROOTFS" /tmp/post_inst.sh
rm -f "$ROOTFS/tmp/post_inst.sh"

cleanup
# Don't bake the build host's DNS into the image; the runtime provides it.
: > "$ROOTFS/etc/resolv.conf"

# --- 6. Optional: import as a single-layer Docker image -------------------
if [ -n "${IMAGE:-}" ]; then
  echo ">>> Importing image ${IMAGE} (linux/${ARCH})"
  changes=(
    --change 'CMD ["/bin/bash"]'
    --change 'LABEL org.opencontainers.image.title=debian'
    --change 'LABEL org.opencontainers.image.description="Minimal Debian base image"'
    --change "LABEL org.opencontainers.image.version=${SUITE}"
    --change "LABEL org.opencontainers.image.revision=${VCS_REF}"
    --change "LABEL org.opencontainers.image.created=${BUILD_DATE}"
  )
  [ -n "${SOURCE_URL}" ] && changes+=(--change "LABEL org.opencontainers.image.source=\"${SOURCE_URL}\"")
  tar -C "$ROOTFS" -cpf - . | docker import --platform "linux/${ARCH}" "${changes[@]}" - "$IMAGE"
fi

echo ">>> Done. Rootfs size:"
du -sh "$ROOTFS"
