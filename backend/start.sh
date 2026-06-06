#!/bin/bash
# Auto-detect current LAN IP, update ALL configs, then start server

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
BACKEND_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$BACKEND_DIR/.env"
FLUTTER_LIB="/Users/mackbook/Projects/YshopProjectFlutter/lib"
SWIFT_PLIST="/Users/mackbook/Projects/YShop-App/YShop/Info.plist"
SWIFT_CONSTANTS="/Users/mackbook/Projects/YShop-App/YShop/Core/Utilities/AppConstants.swift"

echo "Detected IP: $IP"

# 1. Backend .env
sed -i '' "s|^API_BASE_URL=.*|API_BASE_URL=http://$IP:3000|" "$ENV_FILE"
sed -i '' "s|^BACKEND_URL=.*|BACKEND_URL=http://$IP:3000|" "$ENV_FILE"
sed -i '' "s|^CORS_ORIGIN=.*|CORS_ORIGIN=http://$IP:3000|" "$ENV_FILE"
sed -i '' "s|^FRONTEND_URL=.*|FRONTEND_URL=http://$IP:3000|" "$ENV_FILE"
# Ensure BASE_URL is also set (used in some models)
if grep -q "^BASE_URL=" "$ENV_FILE"; then
  sed -i '' "s|^BASE_URL=.*|BASE_URL=http://$IP:3000|" "$ENV_FILE"
else
  echo "BASE_URL=http://$IP:3000" >> "$ENV_FILE"
fi
echo "backend/.env -> $IP"

# 2. Swift Info.plist
if [ -f "$SWIFT_PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :API_BASE_HOST http://$IP:3000" "$SWIFT_PLIST" 2>/dev/null && \
  echo "Swift Info.plist -> $IP"
fi

# 3. Swift AppConstants.swift fallback IP
if [ -f "$SWIFT_CONSTANTS" ]; then
  sed -i '' "s|http://[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:3000|http://$IP:3000|g" "$SWIFT_CONSTANTS"
  echo "Swift AppConstants.swift -> $IP"
fi

# 4. Flutter — all dart files with hardcoded IP (any 192.168.x.x or 127.0.0.1:3000)
if [ -d "$FLUTTER_LIB" ]; then
  find "$FLUTTER_LIB" -name "*.dart" | xargs grep -l "192\.168\.[0-9]*\.[0-9]*:3000\|127\.0\.0\.1:3000" 2>/dev/null | while read file; do
    sed -i '' "s|http://[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:3000|http://$IP:3000|g" "$file"
    echo "  Flutter: $(basename $file) -> $IP"
  done
  echo "Flutter dart files -> $IP"
fi

echo ""
echo "Starting YShop backend on http://$IP:3000"
echo "Rebuild Swift: Cmd+R in Xcode"
echo "Flutter: press R for hot restart"
echo ""

exec npx nodemon src/server.js
