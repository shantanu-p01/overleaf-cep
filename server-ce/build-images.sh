#!/usr/bin/env bash
set -eo pipefail

TAG="${1:-16.10.26}"
BASE_IMAGE="shantanupatil01/overleaf:base-${TAG}"
MAIN_IMAGE="shantanupatil01/overleaf:${TAG}"
MAIN_IMAGE_LATEST="shantanupatil01/overleaf:latest"

send_notification() {
  local text="$1"
  curl -s -k -X POST 'https://wa.cloudnetes.com/api/sendText' \
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

# 1. Build OverLeaf-Base Image
send_notification "🚀 Build started for ${BASE_IMAGE}"
if docker buildx build --platform linux/amd64,linux/arm64 \
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
if docker buildx build --platform linux/amd64,linux/arm64 \
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
