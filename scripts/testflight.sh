#!/bin/bash
# Archives Road Sign Math for the App Store and uploads it to TestFlight,
# for internal testers only (Config/ExportOptions-TestFlight.plist). Builds
# come from a clean commit on main: Apple's build number is the commit
# count, so it only goes up, and the app's Info.plist names the commit.
#
#   scripts/testflight.sh               internal testers only
#   scripts/testflight.sh --external    a build outside testers can get too,
#                                       once Apple's Beta App Review passes it
#
# When to upload is in AGENTS.md; every --external upload is Jamie's call
# (docs/DISTRIBUTION.md).
#
# Needs the team in Config/Signing.local.xcconfig and the app made in App
# Store Connect for xyz.roadsignmath.app. Signing is automatic: either the
# developer account signed in to Xcode (Settings > Accounts), which only a
# login session (Terminal) has, or an App Store Connect API key, which
# works from any shell: a team key with the Admin role (Apple's
# cloud-managed distribution certificate takes Admin), its
# AuthKey_<key id>.p8 in ~/.appstoreconnect/private_keys, and its ids in
# Config/AppStoreConnect.local, which git ignores:
#   ASC_KEY_ID=<key id>
#   ASC_ISSUER_ID=<issuer id>
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

options=Config/ExportOptions-TestFlight.plist
case ${1:-} in
  "") ;;
  --external) external=1 ;;
  *) echo "Usage: scripts/testflight.sh [--external]" >&2; exit 64 ;;
esac

if ! grep -qE '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}' Config/Signing.local.xcconfig 2>/dev/null; then
  echo "Put DEVELOPMENT_TEAM = <your team ID> in Config/Signing.local.xcconfig first." >&2
  exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
  echo "The checkout has changes. TestFlight builds come from a clean commit." >&2
  exit 1
fi
git fetch -q origin main
if ! git merge-base --is-ancestor HEAD origin/main; then
  echo "This commit isn't on main. TestFlight builds come from main." >&2
  exit 1
fi

auth=()
if [[ -f Config/AppStoreConnect.local ]]; then
  key_id=$(sed -nE 's/^ASC_KEY_ID=([A-Z0-9]+)$/\1/p' Config/AppStoreConnect.local)
  issuer=$(sed -nE 's/^ASC_ISSUER_ID=([0-9a-f-]+)$/\1/p' Config/AppStoreConnect.local)
  key=$HOME/.appstoreconnect/private_keys/AuthKey_$key_id.p8
  if [[ -z $key_id || -z $issuer || ! -f $key ]]; then
    echo "Config/AppStoreConnect.local needs ASC_KEY_ID and ASC_ISSUER_ID, and the key in $HOME/.appstoreconnect/private_keys." >&2
    exit 1
  fi
  auth=(-authenticationKeyPath "$key" -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$issuer")
fi

out=$root/build/testflight
rm -rf "$out"
mkdir -p "$out"
if [[ -n ${external:-} ]]; then
  # Apple: builds uploaded as internal only "can only be added to internal
  # tester groups", so an outside testers' build leaves the key out.
  cp "$options" "$out/ExportOptions-external.plist"
  options=$out/ExportOptions-external.plist
  /usr/libexec/PlistBuddy -c "Delete :testFlightInternalTestingOnly" "$options"
  echo "For outside testers too, once Beta App Review passes it."
fi
echo "Road Sign Math $(scripts/version.sh), build $(git rev-list --count HEAD) ($(git rev-parse --short HEAD))"
xcodebuild -project RoadSignMath.xcodeproj -scheme RoadSignMath -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$out/RoadSignMath.xcarchive" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} -quiet archive
xcodebuild -exportArchive -archivePath "$out/RoadSignMath.xcarchive" \
  -exportOptionsPlist "$options" -exportPath "$out/export" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
echo "Uploaded. App Store Connect takes a few minutes to process it; then it is in TestFlight."
