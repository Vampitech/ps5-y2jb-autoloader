#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
BASE=${Y2JB_NATIVE_HOME:-$HOME/.local/share/y2jb-native}
SDK=$BASE/sdk
export PS5_PAYLOAD_SDK=$SDK
export PATH="$BASE/node/bin:$BASE/tools:$SDK/bin:$PATH"
JOBS=${JOBS:-$(nproc)}
MODE=${1:-help}
mkdir -p "$BASE"
[[ "$BASE" != *' '* && "$ROOT" != *' '* ]] || { echo 'Use paths without spaces.' >&2; exit 1; }
case "$MODE" in
setup)
  . /etc/os-release
  [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || { echo 'Setup currently supports Ubuntu 24.04 only.' >&2; exit 1; }
  sudo apt-get update
  sudo apt-get install -y build-essential git ca-certificates curl wget xz-utils unzip zip cmake ninja-build pkg-config autoconf automake libtool clang-18 lld-18 llvm-18 python3 python3-pyelftools libc6-dev-amd64-cross xxd makefs file
  mkdir -p "$BASE/tools"
  for pair in clang:clang-18 clang++:clang++-18 ld.lld:ld.lld-18 llvm-objcopy:llvm-objcopy-18; do
    ln -sfn "$(command -v "${pair#*:}")" "$BASE/tools/${pair%%:*}"
  done
  [[ $(uname -m) == x86_64 ]] || { echo 'This setup supports x86_64 WSL only.' >&2; exit 1; }
  # Fixed baseline, not a claim that this is the latest Node release.
  NODE_VERSION=v22.14.0
  if [[ ! -x "$BASE/node/bin/node" ]]; then
    T=$(mktemp -d)
    trap 'rm -rf "$T"' EXIT
    ARCHIVE=node-$NODE_VERSION-linux-x64.tar.xz
    curl -fL --retry 3 "https://nodejs.org/dist/$NODE_VERSION/$ARCHIVE" -o "$T/$ARCHIVE"
    curl -fL --retry 3 "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" -o "$T/SHASUMS256.txt"
    (cd "$T"; grep "  $ARCHIVE$" SHASUMS256.txt | sha256sum -c -)
    mkdir -p "$BASE/node"
    tar -xJf "$T/$ARCHIVE" --strip-components=1 -C "$BASE/node"
    rm -rf "$T"
    trap - EXIT
  fi
  if [[ ! -d "$BASE/sdk-source/.git" ]]; then
    git clone https://github.com/ps5-payload-dev/sdk.git "$BASE/sdk-source"
  fi
  make -C "$BASE/sdk-source" -j"$JOBS" DESTDIR="$SDK" install
  printf 'SDK installed at %s\nNext: bash scripts/wsl-native.sh all\n' "$SDK"
  ;;
all|zip)
  for cmd in git make python3 node npm clang-18 llvm-objcopy-18 wget sha256sum; do
    command -v "$cmd" >/dev/null || { echo "Missing $cmd; run setup first." >&2; exit 1; }
  done
  [[ -f "$SDK/toolchain/prospero.mk" && -x "$SDK/bin/prospero-clang" ]] || { echo 'Run setup first: dedicated SDK is missing.' >&2; exit 1; }
  git submodule update --init --recursive
  VERSION=${2:-$(tr -d '\r\n' < payload-manager.version)}
  [[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ && "$VERSION" != latest ]] || { echo 'Use an explicit source tag, not latest.' >&2; exit 1; }
  MANAGER=${MANAGER_SOURCE:-$BASE/payload-manager-$VERSION}
  if [[ ! -d "$MANAGER/.git" && ! -f "$MANAGER/.git" ]]; then
    [[ -z "${MANAGER_SOURCE:-}" ]] || { echo 'MANAGER_SOURCE must point to an existing Git checkout.' >&2; exit 1; }
    git clone --branch "$VERSION" --depth 1 --recurse-submodules https://github.com/itsPLK/ps5-payload-manager.git "$MANAGER"
  fi
  [[ "$MANAGER" != *' '* ]] || { echo 'Manager path must not contain spaces.' >&2; exit 1; }
  git -C "$MANAGER" submodule update --init --recursive
  # Adapt upstream's hardcoded SDK paths in a generated copy only.
  python3 - "$MANAGER/build_deps.sh" "$BASE/build-manager-deps.sh" "$SDK" <<'PY'
import pathlib, sys
source, dest, sdk = sys.argv[1:]
pathlib.Path(dest).write_text(pathlib.Path(source).read_text().replace('/opt/ps5-payload-sdk', sdk))
PY
  bash "$BASE/build-manager-deps.sh"
  make -C "$MANAGER" clean
  make -C "$MANAGER" frontend-build
  make -C "$MANAGER" -j"$JOBS" all SDK="$SDK" TARGET="$SDK/target" CC="$SDK/bin/prospero-clang" STRIP="$SDK/bin/prospero-strip"
  ELFLDR=$ROOT/third_party/ps5-elfldr
  KEXP=$ROOT/third_party/ps5-kexp
  AUTO=$ROOT/third_party/ps5-unified-autoloader
  make -C "$ELFLDR" clean
  make -C "$ELFLDR" -j"$JOBS" all PS5_PAYLOAD_SDK="$SDK"
  make -C "$KEXP" clean
  make -C "$KEXP" -j"$JOBS" all CC=clang-18 OBJCOPY=llvm-objcopy-18
  cp "$MANAGER/pldmgr.elf" "$AUTO/pldmgr.elf"
  make -C "$AUTO" clean
  make -C "$AUTO" -j"$JOBS" all SDK="$SDK" TARGET="$SDK/target" CC="$SDK/bin/prospero-clang" STRIP="$SDK/bin/prospero-strip"
  # Remove competing dependency filenames so Make cannot select an old ELF/bin.
  rm -f src/elfldr*.elf src/kexp-*.bin src/kexp_v*.bin src/ps5-unified-autoloader*.elf
  EREV=$(git -C "$ELFLDR" rev-parse --short HEAD)
  KREV=$(git -C "$KEXP" rev-parse --short HEAD)
  cp "$ELFLDR/elfldr-ps5.elf" "src/elfldr-ps5-$EREV.elf"
  cp "$KEXP/build/kexp.bin" "src/kexp-$KREV.bin"
  cp "$AUTO/autoloader.elf" src/ps5-unified-autoloader.elf
  make clean
  make all BUILD_TYPE=dev
  mkdir -p dist-native
  cp y2jb_update.zip "$MANAGER/pldmgr.elf" "$AUTO/autoloader.elf" "$ELFLDR/elfldr-ps5.elf" "$KEXP/build/kexp.bin" dist-native/
  {
    printf 'requested_manager_tag=%s\n' "$VERSION"
    printf 'manager_source=%s\n' "$MANAGER"
    printf 'manager_commit=%s\n' "$(git -C "$MANAGER" rev-parse HEAD)"
    printf 'sdk_commit=%s\n' "$(git -C "$BASE/sdk-source" rev-parse HEAD)"
    printf 'y2jb_commit=%s\n' "$(git rev-parse HEAD)"
    git -C "$MANAGER" status --short
    git submodule status --recursive
    node --version
    clang-18 --version
    sha256sum dist-native/*.elf dist-native/*.bin dist-native/y2jb_update.zip
  } > dist-native/build-manifest.txt
  if [[ "$MODE" == all ]]; then
    bash "$ROOT/scripts/wsl-native.sh" image
  fi
  echo 'Build outputs: dist-native/'
  ;;
image)
  command -v makefs >/dev/null || { echo 'Install makefs (setup).' >&2; exit 1; }
  [[ -f dist-native/y2jb_update.zip ]] || { echo 'Build zip first.' >&2; exit 1; }
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT
  CACHE=$T/cache/splash_screen/aHR0cHM6Ly93d3cueW91dHViZS5jb20vdHY=
  mkdir -p "$CACHE"
  unzip -q dist-native/y2jb_update.zip -d "$CACHE"
  rm -f "$CACHE/update-info.txt"
  chmod -R 777 "$T/cache"
  makefs -t ffs -B little -s 336789504 -o version=2,bsize=32768,fsize=4096 "$T/download0.dat" "$T"
  [[ $(stat -c %s "$T/download0.dat") == 336789504 ]] || { echo 'Unexpected image size.' >&2; exit 1; }
  mv "$T/download0.dat" dist-native/download0.dat
  file dist-native/download0.dat
  sha256sum dist-native/download0.dat > dist-native/download0.dat.sha256
  echo 'UFS2 image generated; console compatibility still requires testing.'
  ;;
*)
  echo 'Usage: bash scripts/wsl-native.sh setup | all [tag] | zip [tag] | image'
  [[ "$MODE" == help ]] || exit 1
  ;;
esac
