#!/usr/bin/env bash
if [ -z "$BASH_VERSION" ]; then
  exec bash "$0" "$@"
fi
set -eo pipefail

if [ -d "./server-ce" ]; then
  ROOT_DIR="$(pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "${ROOT_DIR}"

TARGET="all"
TAG="16.10.26"

case "${1:-}" in
  base)
    TARGET="base"
    shift
    ;;
  main)
    TARGET="main"
    shift
    ;;
  all)
    TARGET="all"
    shift
    ;;
esac

if [ -n "${1:-}" ]; then
  TAG="$1"
fi

BASE_IMAGE_TAGGED="shantanupatil01/overleaf-extended:base-${TAG}"
BASE_IMAGE_LATEST="shantanupatil01/overleaf-extended:base-latest"
MAIN_IMAGE_TAGGED="shantanupatil01/overleaf-extended:${TAG}"
MAIN_IMAGE_LATEST="shantanupatil01/overleaf-extended:latest"

send_notification() {
  local text="$1"
  curl -s -k -o /dev/null -X POST 'https://wa.cloudnetes.com/api/sendText' \
    -H 'accept: application/json' \
    -H 'X-Api-Key: 55bcdb029bd24b669303c58d01a15d51' \
    -H 'Content-Type: application/json' \
    -d "{
      \"chatId\": \"917744957705@c.us\",
      \"reply_to\": null,
      \"text\": \"${text}\",
      \"linkPreview\": true,
      \"linkPreviewHighQuality\": false,
      \"session\": \"default\"
    }" || true
}

setup_native_builder() {
  local builder="multiarch-native"
  local local_uname="$(uname -m)"
  local local_arch=""
  local local_platform=""
  local missing_arch=""
  local missing_platform=""

  case "${local_uname}" in
    arm64|aarch64)
      local_arch="arm64"
      local_platform="linux/arm64"
      missing_arch="amd64"
      missing_platform="linux/amd64"
      ;;
    x86_64|amd64)
      local_arch="amd64"
      local_platform="linux/amd64"
      missing_arch="arm64"
      missing_platform="linux/arm64"
      ;;
    *)
      echo "⚠️ Unknown local architecture: ${local_uname}, continuing with default builder..."
      return 0
      ;;
  esac

  # Automatically load SSH key if available
  if [ -f "$HOME/Keys/prod_key.pem" ]; then
    ssh-add "$HOME/Keys/prod_key.pem" 2>/dev/null || true
  fi
  if [ -f "$HOME/.ssh/id_rsa" ]; then
    ssh-add "$HOME/.ssh/id_rsa" 2>/dev/null || true
  fi
  if [ -f "$HOME/.ssh/id_ed25519" ]; then
    ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null || true
  fi

  local needs_setup=0
  if [ "${RECONFIGURE_BUILDER:-0}" = "1" ]; then
    needs_setup=1
  elif ! docker buildx inspect "${builder}" >/dev/null 2>&1; then
    needs_setup=1
  elif ! docker buildx inspect "${builder}" 2>/dev/null | grep -q "remote-${missing_arch}"; then
    needs_setup=1
  elif ! docker buildx inspect "${builder}" 2>/dev/null | grep -q 'network="host"'; then
    needs_setup=1
  fi

  if [ "${needs_setup}" -eq 0 ]; then
    docker buildx use "${builder}" 2>/dev/null || true
    echo "🚀 Using existing healthy multi-node native builder '${builder}'"
    return 0
  fi

  local remote_target=""
  if [ -n "${REMOTE_BUILDER_IP:-}" ]; then
    remote_target="${REMOTE_BUILDER_IP}"
  else
    echo "=========================================================="
    echo "⚡ Multi-Node Native Builder Setup"
    echo "Current machine is [${local_arch}]."
    echo "To build multi-arch natively without slow QEMU emulation,"
    echo "we need a native [${missing_arch}] machine."
    echo "=========================================================="
    if [ -e /dev/tty ]; then
      read -r -p "Enter IP address or SSH user@host for native [${missing_arch}] machine: " remote_target < /dev/tty || true
    else
      read -r -p "Enter IP address or SSH user@host for native [${missing_arch}] machine: " remote_target || true
    fi
  fi

  if [ -z "${remote_target}" ]; then
    echo "⚠️ No remote host provided. Falling back to local builder (QEMU emulation will be used for ${missing_arch})."
    return 0
  fi

  if [[ "${remote_target}" != *"@"* ]]; then
    remote_target="${USER}@${remote_target}"
  fi

  # Automatically accept host key if new IP
  ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes "${remote_target}" true 2>/dev/null || true

  echo "🔌 Testing Docker connection at ssh://${remote_target}..."
  if ! docker -H "ssh://${remote_target}" info >/dev/null 2>&1; then
    echo "❌ Could not connect to Docker at ssh://${remote_target}."
    echo "Make sure SSH key access and Docker are running on the remote machine."
    echo "Falling back to local builder..."
    return 0
  fi

  echo "🛠️ Configuring multi-node builder '${builder}' with host networking..."
  docker buildx rm "${builder}" 2>/dev/null || true

  docker buildx create --name "${builder}" \
    --driver docker-container \
    --driver-opt network=host \
    --platform "${local_platform}" \
    --node "local-${local_arch}"

  docker buildx create --name "${builder}" \
    --append \
    --driver docker-container \
    --driver-opt network=host \
    --platform "${missing_platform}" \
    --node "remote-${missing_arch}" \
    "ssh://${remote_target}"

  echo "🔄 Bootstrapping builder..."
  docker buildx inspect --bootstrap "${builder}" || true
  docker buildx use "${builder}" 2>/dev/null || true
  echo "🚀 Using multi-node native builder '${builder}'"
}

setup_native_builder

BUILDER_FLAG=""
if docker buildx inspect "multiarch-native" >/dev/null 2>&1; then
  BUILDER_FLAG="--builder multiarch-native"
fi

# 1. Build OverLeaf-Base Image
if [ "${TARGET}" = "base" ] || [ "${TARGET}" = "all" ]; then
  send_notification "🚀 Build started for ${BASE_IMAGE_TAGGED}"
  if docker buildx build ${BUILDER_FLAG} --platform linux/amd64,linux/arm64 \
    -f ./server-ce/Dockerfile-base \
    -t "${BASE_IMAGE_TAGGED}" \
    -t "${BASE_IMAGE_LATEST}" \
    --push .; then
    send_notification "✅ Base build pushed successfully!"
  else
    send_notification "❌ Base build Failed!"
    exit 1
  fi
else
  echo "⏩ Skipping base image build (TARGET=${TARGET})"
fi

# 2. Build OverLeaf-Main Image
if [ "${TARGET}" = "main" ] || [ "${TARGET}" = "all" ]; then
  send_notification "🚀 Build started for ${MAIN_IMAGE_TAGGED}"
  if docker buildx build ${BUILDER_FLAG} --platform linux/amd64,linux/arm64 \
    -f ./server-ce/Dockerfile \
    --build-arg OVERLEAF_BASE_TAG="${BASE_IMAGE_TAGGED}" \
    -t "${MAIN_IMAGE_TAGGED}" \
    -t "${MAIN_IMAGE_LATEST}" \
    --push .; then
    send_notification "✅ Main build pushed successfully!"
  else
    send_notification "❌ Main build Failed!"
    exit 1
  fi
else
  echo "⏩ Skipping main image build (TARGET=${TARGET})"
fi
