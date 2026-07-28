# Debian Base Image

Minimal, **systemd-free** Debian base images, built from scratch and published
for `amd64` and `arm64`. Rebuilt weekly, but only when there is actually
something new to ship (a config change or pending security/package updates).

## What's in it (and what isn't)

- **From scratch** via `debootstrap --variant=minbase` — the Essential set + APT,
  nothing more.
- **No init system, no systemd/dbus/apparmor.** They are excluded at bootstrap,
  purged, and pinned to priority `-1` so a dependency can't pull them back in.
  Run your process as PID 1, or add a lightweight init (`tini`, `dumb-init`) in a
  derived image.
- **Trimmed package set:** `wget`, `curl`, `ca-certificates`, `tzdata`. Anything
  tool-specific (git, ssh, editors, …) belongs in your own `FROM` image.
- **Lean by default:** `APT::Install-Recommends` and `-Suggests` are off; man
  pages, docs, info, and translations are stripped (copyright files are kept).
- **Locale:** no `locales` package — glibc's built-in `C.UTF-8` (correct UTF-8,
  English messages).
- **Timezone:** **UTC** by default (`tzdata` is included, so you can switch).
- **Single layer** (`docker import` of the rootfs).

## Where to get it

Published to both **GitHub Container Registry** and **Docker Hub**:

```sh
# GHCR
docker pull ghcr.io/crbrdocker/debian:stable

# Docker Hub
docker pull crbrdocker/debian:stable
```


[![GHCR](https://img.shields.io/badge/GHCR-debian-blue?logo=docker)](https://github.com/users/CrbrDocker/packages/container/package/debian)


### Tags

| Tag                         | Points to                          |
| --------------------------- | ---------------------------------- |
| `latest`, `stable`, `trixie`| current Debian stable (13)         |
| `oldstable`, `bookworm`     | previous Debian stable (12)        |
| `<codename>-amd64` / `-arm64` | per-arch images (manifest inputs) |

Codenames are resolved automatically from Debian's release metadata, so `stable`
/ `oldstable` **move to the next release on their own** over time. Pin to a
codename (e.g. `:bookworm`) if you need a fixed release.

## Runtime notes

```sh
# Timezone: inherit the host, or pick one (tzdata is shipped)
docker run -v /etc/localtime:/etc/localtime:ro ...
docker run -e TZ=Europe/Paris ...

# APT lists are wiped to keep the image small — refresh before installing
docker run --rm ghcr.io/crbrdocker/debian:stable \
  sh -c 'apt-get update && apt-get install -y <pkg>'
```

## How it's built

A weekly GitHub Actions workflow (`.github/workflows/build.yml`):

1. **resolve** — reads the current `stable` / `oldstable` codenames from Debian's
   `Release` files (never hardcoded).
2. **gate** — for each suite, rebuilds only if the published image is missing,
   was built from a different commit, or has pending APT updates
   (`need_rebuild.sh`).
3. **build** — one native runner per arch (`ubuntu-24.04` / `ubuntu-24.04-arm`,
   no QEMU), pushes per-arch tags.
4. **manifest** — merges the per-arch tags into the codename tag + aliases on both
   registries.

Manual runs are available via *Run workflow* (`workflow_dispatch`), with an
optional `suite` input to build any codename/suite (e.g. `sid`).

## Building locally

Linux only; needs `debootstrap` + `debian-archive-keyring` and root:

```sh
# build a rootfs and import it as a local image
sudo IMAGE=debian:trixie ./build_base_system.sh trixie

# check whether a published image needs rebuilding
./need_rebuild.sh ghcr.io/crbrdocker/debian:trixie
```

`ARCH` defaults to the host architecture (native build). See the header of each
script for all options.

## Repository layout

| Path                          | Purpose                                   |
| ----------------------------- | ----------------------------------------- |
| `build_base_system.sh`        | parameterized from-scratch builder        |
| `need_rebuild.sh`             | rebuild gate                              |
| `.github/workflows/build.yml` | CI: resolve → gate → build → manifest     |
| `OLD/`                        | archived previous (manual) implementation |
