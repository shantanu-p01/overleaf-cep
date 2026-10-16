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

TAG="${1:-16.10.26}"
BASE_IMAGE="shantanupatil01/overleaf-extended:base-${TAG}"
MAIN_IMAGE="shantanupatil01/overleaf-extended:${TAG}"
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

  local needs_remote=0
  if [ "${RECONFIGURE_BUILDER:-0}" = "1" ]; then
    needs_remote=1
  elif ! docker buildx inspect "${builder}" >/dev/null 2>&1; then
    needs_remote=1
  elif ! docker buildx inspect "${builder}" 2>/dev/null | grep -q "remote-${missing_arch}"; then
    needs_remote=1
  elif docker buildx inspect "${builder}" 2>/dev/null | grep -A 4 "remote-${missing_arch}" | grep -q "Error:"; then
    echo "⚠️ Remote node 'remote-${missing_arch}' is not responding."
    needs_remote=1
  fi

  if [ "${needs_remote}" -eq 1 ]; then
    echo "=========================================================="
    echo "⚡ Multi-Node Native Builder Setup"
    echo "Current machine is [${local_arch}]."
    echo "To build multi-arch natively without slow QEMU emulation,"
    echo "we need a native [${missing_arch}] machine."
    echo "=========================================================="

    local remote_input=""
    if [ -n "${REMOTE_BUILDER_IP:-}" ]; then
      remote_input="${REMOTE_BUILDER_IP}"
    elif [ -e /dev/tty ]; then
      read -r -p "Enter IP address or SSH host for native [${missing_arch}] machine (e.g. 192.168.1.50 or user@host): " remote_input < /dev/tty || true
    fi

    if [ -z "${remote_input}" ]; then
      echo "⚠️ No remote host provided. Falling back to local builder (QEMU emulation will be used for ${missing_arch})."
      return 0
    fi

    local ssh_target="${remote_input}"
    if [[ "${ssh_target}" != *"@"* ]]; then
      ssh_target="${USER}@${ssh_target}"
    fi

    # Automatically accept host key if new IP
    ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes "${ssh_target}" true 2>/dev/null || true

    echo "🔌 Testing Docker connection at ssh://${ssh_target}..."
    if ! docker -H "ssh://${ssh_target}" info >/dev/null 2>&1; then
      echo "❌ Could not connect to Docker at ssh://${ssh_target}."
      echo "Make sure SSH key access and Docker are running on the remote machine."
      echo "Falling back to local builder..."
      return 0
    fi

    echo "🛠️ Configuring multi-node builder '${builder}'..."
    docker buildx rm "${builder}" 2>/dev/null || true

    docker buildx create --name "${builder}" \
      --driver docker-container \
      --platform "${local_platform}" \
      --node "local-${local_arch}"

    docker buildx create --name "${builder}" \
      --append \
      --driver docker-container \
      --platform "${missing_platform}" \
      --node "remote-${missing_arch}" \
      "ssh://${ssh_target}"

    echo "🔄 Bootstrapping builder..."
    docker buildx inspect --bootstrap "${builder}" || true
  fi

  docker buildx use "${builder}" 2>/dev/null || true
  echo "🚀 Using multi-node native builder '${builder}'"
}

setup_native_builder

# 1. Build OverLeaf-Base Image
send_notification "🚀 Build started for ${BASE_IMAGE}"
if docker buildx build --builder multiarch-native --platform linux/amd64,linux/arm64 \
  -f ./server-ce/Dockerfile-base \
  -t "${BASE_IMAGE}" \
  --push .; then
  send_notification "✅ Base build pushed successfully!"
else
  send_notification "❌ Base build Failed!"
  exit 1
fi

# 2. Build OverLeaf-Main Image
send_notification "🚀 Build started for ${MAIN_IMAGE}"
if docker buildx build --builder multiarch-native --platform linux/amd64,linux/arm64 \
  -f ./server-ce/Dockerfile \
  --build-arg OVERLEAF_BASE_TAG="${BASE_IMAGE}" \
  -t "${MAIN_IMAGE_LATEST}" \
  -t "${MAIN_IMAGE}" \
  --push .; then
  send_notification "✅ Main build pushed successfully!"
else
  send_notification "❌ Main build Failed!"
  exit 1
fi
