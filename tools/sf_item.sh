#!/bin/sh
# Asks Sprite Fusion (edit, 15 credits, 2 results) for an outfit item drawn on the base
# skater: the rig's rest pose (assets/characters/skater.png on the rig canvas) with only
# that item added or changed. Saves both results, the request and the stream under
# assets/characters/source/items/<name>/ for tools/extract_item.gd to cut the item out.
#
#   tools/sf_item.sh <name> "<what changes, e.g. a plain light grey knitted beanie>"
#
# Needs SPRITE_FUSION_API_KEY (from .env.agent), jq and the Godot binary (GODOT).
set -e
cd "$(dirname "$0")/.."
[ -f .env.agent ] && { set -a; . ./.env.agent; set +a; }
NAME=$1
CHANGE=$2
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
DIR=assets/characters/source/items/$NAME
mkdir -p "$DIR"
# The input: the base on the rig canvas (room for hats), as the item tool expects it.
"$GODOT" --headless --path . -s tools/extract_item.gd -- --base "$DIR/input.png" > /dev/null
PROMPT="Edit this pixel art skater: keep everything exactly the same, the same bald young man, the same side-view riding pose facing right, the same size, position and pixels, the same white t-shirt, blue jeans, white shoes and skin, and only change this: $CHANGE. The new item is drawn in the same style: clean one-pixel dark outline, three-tone cel shading lit from the top left, tidy pixel clusters, no dithering, no noise, no stray pixels. Transparent background, nothing else added."
URI="data:image/png;base64,$(base64 -i "$DIR/input.png" | tr -d '\n')"
jq -n --arg u "$URI" --arg p "$PROMPT" '{operation:"edit", prompt:$p, inputs:[{data_url:$u}], tags:["skatelike","character","item"]}' > "$DIR/request.json"
curl -sN -X POST https://www.spritefusion.com/api/v1/generate \
	-H "Authorization: Bearer $SPRITE_FUSION_API_KEY" -H "Content-Type: application/json" \
	-d @"$DIR/request.json" > "$DIR/stream.sse"
# Keep the prompt, drop the (big) input from the saved request.
jq '.inputs = ["input.png"]' "$DIR/request.json" > "$DIR/request.tmp" && mv "$DIR/request.tmp" "$DIR/request.json"
i=0
grep -o '"assetUrl":"[^"]*"' "$DIR/stream.sse" | cut -d'"' -f4 | sort -u | while read -r url; do
	curl -s "$url" -o "$DIR/result_$i.png"
	i=$((i + 1))
done
grep -o '"type":"completed"[^}]*}[^}]*}' "$DIR/stream.sse" || grep -o '"message":"[^"]*"' "$DIR/stream.sse" | tail -1
ls "$DIR"
