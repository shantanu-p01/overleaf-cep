# Build OverLeaf-Base Image
curl -k -X POST 'https://wa.cloudnetes.com/api/sendText' \
  -H 'accept: application/json' \
  -H 'X-Api-Key: 55bcdb029bd24b669303c58d01a15d51' \
  -H 'Content-Type: application/json' \
  -d '{
    "chatId": "917744957705@c.us",
    "reply_to": null,
    "text": "🚀 Build started for overleaf:base-16.10.26",
    "linkPreview": true,
    "linkPreviewHighQuality": false,
    "session": "default"
  }' && \
docker buildx build --platform linux/amd64,linux/arm64 \
  -f ./server-ce/Dockerfile-base \
  -t shantanupatil01/overleaf:base-16.10.26 \
  --push . && \
curl -k -X POST 'https://wa.cloudnetes.com/api/sendText' \
  -H 'accept: application/json' \
  -H 'X-Api-Key: 55bcdb029bd24b669303c58d01a15d51' \
  -H 'Content-Type: application/json' \
  -d '{
    "chatId": "917744957705@c.us",
    "reply_to": null,
    "text": "✅ Build pushed successfully!",
    "linkPreview": true,
    "linkPreviewHighQuality": false,
    "session": "default"
  }' || \
curl -k -X POST 'https://wa.cloudnetes.com/api/sendText' \
  -H 'accept: application/json' \
  -H 'X-Api-Key: 55bcdb029bd24b669303c58d01a15d51' \
  -H 'Content-Type: application/json' \
  -d '{
    "chatId": "917744957705@c.us",
    "reply_to": null,
    "text": "❌ Build Failed!",
    "linkPreview": true,
    "linkPreviewHighQuality": false,
    "session": "default"
  }'



Build OverLeaf-Main Image
curl -k -X POST 'https://wa.cloudnetes.com/api/sendText' \
  -H 'accept: application/json' \
  -H 'X-Api-Key: 55bcdb029bd24b669303c58d01a15d51' \
  -H 'Content-Type: application/json' \
  -d '{
    "chatId": "917744957705@c.us",
    "reply_to": null,
    "text": "🚀 Build started for overleaf:16.10.26",
    "linkPreview": true,
    "linkPreviewHighQuality": false,
    "session": "default"
  }' && \
docker buildx build --platform linux/amd64,linux/arm64 \
  -f ./server-ce/Dockerfile \
  -t shantanupatil01/overleaf:latest \
  -t shantanupatil01/overleaf:16.10.26 \
  --push . && \
curl -k -X POST 'https://wa.cloudnetes.com/api/sendText' \
  -H 'accept: application/json' \
  -H 'X-Api-Key: 55bcdb029bd24b669303c58d01a15d51' \
  -H 'Content-Type: application/json' \
  -d '{
    "chatId": "917744957705@c.us",
    "reply_to": null,
    "text": "✅ Build pushed successfully!",
    "linkPreview": true,
    "linkPreviewHighQuality": false,
    "session": "default"
  }' || \
curl -k -X POST 'https://wa.cloudnetes.com/api/sendText' \
  -H 'accept: application/json' \
  -H 'X-Api-Key: 55bcdb029bd24b669303c58d01a15d51' \
  -H 'Content-Type: application/json' \
  -d '{
    "chatId": "917744957705@c.us",
    "reply_to": null,
    "text": "❌ Build Failed!",
    "linkPreview": true,
    "linkPreviewHighQuality": false,
    "session": "default"
  }'
