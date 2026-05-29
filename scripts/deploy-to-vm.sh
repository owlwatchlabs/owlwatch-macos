#!/usr/bin/env bash
set -euo pipefail

# This host has xcode-select pointing at CommandLineTools by default,
# which makes xcodebuild error out. Pin to Xcode.app explicitly so
# the script works without `sudo xcode-select -s`.
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

# Run xcodegen + xcodebuild from the directory that owns
# project.yml, regardless of the cwd the caller invoked from.
cd "$(dirname "$0")/../apps/Owlwatch"

VM_NAME=owlwatch-dev; VM_USER=admin
VM_HOST=$(tart ip "$VM_NAME" 2>/dev/null) || {
  echo "VM '$VM_NAME' not running — ask the human: tart run $VM_NAME" >&2; exit 1; }

xcodegen generate
xcodebuild -project Owlwatch.xcodeproj -scheme Owlwatch \
  -configuration Debug -allowProvisioningUpdates clean build

APP="$(xcodebuild -project Owlwatch.xcodeproj -scheme Owlwatch -showBuildSettings \
  | awk '/^ *BUILT_PRODUCTS_DIR =/ {print $3}')/Owlwatch.app"
SEXT="$APP/Contents/Library/SystemExtensions/OwlwatchContentFilter.systemextension"
test -d "$APP"  || { echo "built app missing: $APP" >&2; exit 1; }
test -d "$SEXT" || { echo "content filter not embedded in app" >&2; exit 1; }
codesign --verify --strict --verbose=2 "$APP"

echo "--- shipping to $VM_USER@$VM_HOST ---"
# Trailing slashes on both sides — without them rsync nests the
# bundle as `/tmp/Owlwatch.app/Owlwatch.app/`. With them, the
# remote `/tmp/Owlwatch.app/` ends up as a faithful copy of the
# host's app bundle.
rsync -a --delete "$APP/" "$VM_USER@$VM_HOST:/tmp/Owlwatch.app/"
ssh "$VM_USER@$VM_HOST" '
  sudo systemextensionsctl reset 2>/dev/null || true
  sudo rm -rf /Applications/Owlwatch.app
  sudo cp -R /tmp/Owlwatch.app /Applications/
  open /Applications/Owlwatch.app
'
sleep 2
echo "--- systemextensionsctl list (VM) ---"
ssh "$VM_USER@$VM_HOST" 'systemextensionsctl list'
