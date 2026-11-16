#!/bin/sh
# Rebuilds AO3Kit's Resources/ellipsus-document.js: Yjs (MIT) plus a small
# bridge, so Parade can read an Ellipsus Reader page's document (a Yjs CRDT)
# in JavaScriptCore. Run from anywhere; needs node and npm.
set -e
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
cp "$here/bridge.js" "$here/shim.js" "$work/"
cd "$work"
npm init -y >/dev/null
npm i yjs@13 esbuild >/dev/null
npx esbuild bridge.js --bundle --minify --format=iife --legal-comments=none \
  --outfile="$here/../../AO3Kit/Sources/AO3Kit/Resources/ellipsus-document.js"
rm -rf "$work"
