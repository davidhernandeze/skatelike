#!/bin/sh
# Build a signed release APK for android.skatelike.com, and optionally upload it.
#
#   tools/android-release.sh                 # build into build/android-site/
#   tools/android-release.sh user@host       # build, then rsync to the host's webroot
#
# Signing comes from ~/.config/skatelike/android.env (GODOT_ANDROID_KEYSTORE_RELEASE_*).
# version/code is set to minutes since the epoch for this build only, so every
# APK installs over the previous one; export_presets.cfg is restored afterwards.
set -eu

cd "$(dirname "$0")/.."
godot=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
env_file=${SKATELIKE_ANDROID_ENV:-$HOME/.config/skatelike/android.env}
out=build/android-site
remote_dir=/srv/infra/sites/skatelike-android/

. "$env_file"

sha=$(git rev-parse --short HEAD)
git diff --quiet HEAD -- . ':!export_presets.cfg' || sha="$sha-dirty"
code=$(( $(date +%s) / 60 ))
name="0.1.$code+$sha"

cp export_presets.cfg build/export_presets.cfg.bak
trap 'mv build/export_presets.cfg.bak export_presets.cfg' EXIT
# Only touch the Android preset's options (the section after [preset.1.options]).
awk -v code="$code" -v name="$name" '
	/^\[/ { in_android = ($0 == "[preset.1.options]") }
	in_android && /^version\/code=/ { $0 = "version/code=" code }
	in_android && /^version\/name=/ { $0 = "version/name=\"" name "\"" }
	{ print }
' build/export_presets.cfg.bak > export_presets.cfg

rm -rf "$out" && mkdir -p "$out"
"$godot" --headless --path . --export-release Android "$out/skatelike.apk"
rm -f "$out/skatelike.apk.idsig"

size=$(wc -c < "$out/skatelike.apk" | tr -d ' ')
sum=$(shasum -a 256 "$out/skatelike.apk" | cut -d' ' -f1)
cat > "$out/version.json" <<EOF
{
  "version_name": "$name",
  "version_code": $code,
  "commit": "$sha",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "size": $size,
  "sha256": "$sum"
}
EOF
cat "$out/version.json"

if [ $# -gt 0 ]; then
	rsync -av "$out/skatelike.apk" "$out/version.json" "$1:$remote_dir"
	echo "Uploaded. On the server, as root from /srv/infra, fix ownership (see docs/skatelike.md)."
fi
