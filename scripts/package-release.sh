#!/bin/zsh
set -eu
cd "${0:A:h}/.."
./scripts/build-app.sh
VERSION="$(cat VERSION)"
ARCH="$(uname -m)"
ASSET="ClipNest-$VERSION-macos-$ARCH.zip"
mkdir -p build/releases
ditto -c -k --sequesterRsrc --keepParent build/ClipNest.app "build/releases/$ASSET"
(cd build/releases && shasum -a 256 "$ASSET" > "$ASSET.sha256")
echo "build/releases/$ASSET"
