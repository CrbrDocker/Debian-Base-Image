#!/bin/bash
#
# need_rebuild.sh
#
# Decide whether a published base image must be rebuilt. The build is expensive,
# so a scheduled run only proceeds when something actually changed:
#
#   rebuild =  image missing in registry
#           OR image built from a different commit than HEAD
#           OR the image has pending APT updates (i.e. it lags the archive)
#
# Requires docker, and (for private/GHCR images) a prior `docker login`.
#
# Params (positional or env):
#   IMAGE   (arg1)  published image ref to check, e.g. ghcr.io/crbrdocker/debian:trixie  [required]
#   VCS_REF (arg2)  current commit sha to compare against the image's label
#                   [default: $GITHUB_SHA, else git HEAD, else "unknown"]
#
# Output:
#   - prints "REBUILD=true|false" and the reason(s)
#   - if $GITHUB_OUTPUT is set, appends "build=true|false" for the workflow
#   - exits 0 unless the arguments are wrong (2)

set -uo pipefail

IMAGE="${IMAGE:-${1:-}}"
VCS_REF="${VCS_REF:-${2:-${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}}}"
if [ -z "$IMAGE" ]; then
  echo "ERROR: IMAGE is required.  Usage: $0 <image-ref> [vcs-ref]" >&2
  exit 2
fi

REVISION_LABEL="org.opencontainers.image.revision"
rebuild=false
reasons=()
flag() { rebuild=true; reasons+=("$1"); }

if ! docker pull "$IMAGE" >/dev/null 2>&1; then
  # First build, a new suite, or the tag was removed.
  flag "image '${IMAGE}' not found in registry"
else
  # Built from the current commit?  (missing label -> "<none>" -> mismatch -> rebuild)
  img_ref=$(docker image inspect \
    --format '{{ with .Config.Labels }}{{ index . "org.opencontainers.image.revision" }}{{ end }}' \
    "$IMAGE" 2>/dev/null || true)
  img_ref="${img_ref:-<none>}"
  if [ "$img_ref" != "$VCS_REF" ]; then
    flag "built from '${img_ref}', HEAD is '${VCS_REF}'"
  fi

  # Pending APT updates?  The image wipes /var/lib/apt/lists, so refresh first,
  # then simulate a dist-upgrade and count the packages it would touch.
  pending=$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
    'apt-get -qq update >/dev/null 2>&1; apt-get -s dist-upgrade 2>/dev/null | grep -c "^Inst "' \
    2>/dev/null || echo 0)
  [[ "$pending" =~ ^[0-9]+$ ]] || pending=0
  echo "pending APT updates: ${pending}"
  if [ "$pending" -gt 0 ]; then
    flag "${pending} pending APT update(s)"
  fi
fi

echo "REBUILD=${rebuild}"
if [ "${#reasons[@]}" -gt 0 ]; then
  printf '  - %s\n' "${reasons[@]}"
else
  echo "  - up to date; nothing to do"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "build=${rebuild}" >> "$GITHUB_OUTPUT"
fi
