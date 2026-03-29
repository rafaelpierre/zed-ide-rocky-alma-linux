#!/usr/bin/env bash
# extract-zed.sh
# Builds the Zed Docker image (if needed) and copies the compiled binaries
# out of the container onto your host machine.
#
# Usage:
#   ./extract-zed.sh [--dest <dir>] [--skip-build] [--zed-ref <git-ref>]
#
# Options:
#   --dest        Where to put the binaries (default: ./zed-dist)
#   --skip-build  Skip `docker build` and just extract from an existing image
#   --zed-ref     Git branch/tag to build (default: main)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
IMAGE_NAME="zed-rocky8-builder"
DEST_DIR="./zed-dist"
SKIP_BUILD=true
ZED_REF="main"
ARTEFACTS_PATH="/home/builder/artefacts"   # must match Dockerfile

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --dest)        DEST_DIR="$2";  shift 2 ;;
    --skip-build)  SKIP_BUILD=true; shift  ;;
    --zed-ref)     ZED_REF="$2";   shift 2 ;;
    *) echo "Unknown option: $1"; exit 1   ;;
  esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "❌  docker not found in PATH."
  exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
  echo "🔨  Building Docker image '${IMAGE_NAME}' (this takes 20-30 min)…"
  docker build \
    --platform linux/amd64 \
    --build-arg ZED_REF="${ZED_REF}" \
    --tag "${IMAGE_NAME}" \
    --file "$(dirname "$0")/Dockerfile" \
    "$(dirname "$0")"
  echo "✅  Build complete."
else
  echo "⏭️   Skipping build (--skip-build set)."
  if ! docker image inspect "${IMAGE_NAME}" &>/dev/null; then
    echo "❌  Image '${IMAGE_NAME}' not found locally. Run without --skip-build first."
    exit 1
  fi
fi

# ── Extract ───────────────────────────────────────────────────────────────────
echo "📦  Extracting artefacts from image…"

# Spin up a temporary container (no entrypoint, immediately exits)
CONTAINER_ID=$(docker create --pull never "${IMAGE_NAME}")

# Make sure we clean up the container no matter what happens next
cleanup() {
  echo "🧹  Removing temporary container ${CONTAINER_ID}…"
  docker rm "${CONTAINER_ID}" >/dev/null
}
trap cleanup EXIT

mkdir -p "${DEST_DIR}"

# docker cp copies the *contents* of the directory when you append /. to the src
docker cp "${CONTAINER_ID}:${ARTEFACTS_PATH}/." "${DEST_DIR}/"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "✅  Done! Artefacts written to: ${DEST_DIR}"
echo ""
ls -lh "${DEST_DIR}"
echo ""
echo "To run Zed (needs a display + Vulkan GPU on the host):"
echo "  ${DEST_DIR}/zed"