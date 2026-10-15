#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for cmd in gh curl python3 make docker sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }
done
VERSION=${1:-$(tr -d '\r\n' < payload-manager.version)}
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'Invalid version' >&2; exit 1; }
REPO=itsPLK/ps5-payload-manager
if [[ "$VERSION" == latest ]]; then
  RELEASE=$(gh api "repos/$REPO/releases/latest")
else
  RELEASE=$(gh api "repos/$REPO/releases/tags/$VERSION")
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s' "$RELEASE" > "$TMP/release.json"
python3 - "$TMP/release.json" "$TMP" <<'PY'
import json, pathlib, re, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
assets = [a for a in r.get('assets', []) if re.fullmatch(r'pldmgr_v.*\.elf', a['name'])]
if len(assets) != 1:
    raise SystemExit('Expected exactly one versioned Payload Manager ELF')
a = assets[0]
digest = a.get('digest') or ''
if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
    raise SystemExit('Release has no usable SHA-256 digest; refusing unverified download')
base = pathlib.Path(sys.argv[2])
for key, value in {'tag': r['tag_name'], 'url': a['browser_download_url'], 'sha256': digest.split(':')[1]}.items():
    (base / key).write_text(value)
PY
TAG=$(cat "$TMP/tag")
EXPECTED=$(cat "$TMP/sha256")
curl --fail --location --retry 3 --output "$TMP/pldmgr.elf" "$(cat "$TMP/url")"
printf '%s  %s\n' "$EXPECTED" "$TMP/pldmgr.elf" | sha256sum --check -
python3 - "$TMP/pldmgr.elf" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    if f.read(4) != b'\x7fELF':
        raise SystemExit('Downloaded file is not an ELF')
PY
# Keep the exploit and loader dependencies pinned to the upstream submodules.
bash scripts/download_deps.sh
AUTO=third_party/ps5-unified-autoloader
[[ -f "$AUTO/Makefile" && -f "$AUTO/Dockerfile.sdk" ]] || { echo 'Initialize submodules recursively first' >&2; exit 1; }
cp "$TMP/pldmgr.elf" "$AUTO/pldmgr.elf"
# Build directly: build_release.sh would replace the supplied ELF.
docker build -t vampitech-unified-autoloader-sdk -f "$AUTO/Dockerfile.sdk" "$AUTO"
docker run --rm --user "$(id -u):$(id -g)" -v "$(pwd)/$AUTO:/src" -w /src vampitech-unified-autoloader-sdk make clean all
cp "$AUTO/autoloader.elf" src/ps5-unified-autoloader.elf
make clean
make all BUILD_TYPE=dev
{
  printf 'payload_manager_tag=%s\n' "$TAG"
  printf 'payload_manager_sha256=%s\n' "$EXPECTED"
  printf 'y2jb_commit=%s\n' "$(git rev-parse HEAD)"
  printf 'unified_autoloader_commit=%s\n' "$(git -C "$AUTO" rev-parse HEAD)"
  git submodule status --recursive
  sha256sum src/ps5-unified-autoloader.elf y2jb_update.zip
} > embedded-build-manifest.txt
echo "Built y2jb_update.zip with Payload Manager $TAG"
