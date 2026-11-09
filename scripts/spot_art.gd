class_name SpotArt
## A spot's asset group (assets/spots/<art>/, made by tools/make_spot_assets.gd and
## tools/make_backgrounds.gd from assets/spots/source/<set>/): what a stage looks like
## when its level says `art = "<art>"` (see Levels). Files, by name:
##
##   fill.png              the ground's fill, tiled inside it (Runner.fill_texture)
##   edge.png              the strip along its surface (Runner.edge_texture)
##   props/<name>.png      things standing on the floor, not ridden: cars, lamps... placed
##                         by the level (`props` on a floor piece, `start_props`)
##   backdrop/<layer>.png  the parallax backdrop's layers, back to front (ARTS.backdrop)
##
## A level without `art` keeps the Dusk Boardwalk (the concrete tiles and
## assets/backgrounds).

const DIR := "res://assets/spots/%s/"
## Per asset group: its backdrop's layers (back to front), how fast each one moves for
## one px of the level (ParallaxBackdrop.speeds), and whether the front one's bottom is
## left open, the layers behind carrying on under it (ParallaxBackdrop.open_bottom).
const ARTS := {
	bridge = {backdrop = {layers = ["sky", "river", "near"], speeds = [0.04, 0.12, 0.35],
		open_bottom = true}},
	school = {backdrop = {layers = ["sky", "city", "near"], speeds = [0.04, 0.12, 0.35], open_bottom = true}},
}


static func fill(art: String) -> Texture2D:
	return _load(art, "fill.png")


static func edge(art: String) -> Texture2D:
	return _load(art, "edge.png")


static func prop(art: String, name: String) -> Texture2D:
	return _load(art, "props/%s.png" % name)


## The backdrop's layers (back to front) and speeds, or {} for the default one.
static func backdrop(art: String) -> Dictionary:
	if not ARTS.has(art):
		return {}
	var layers: Array[Texture2D] = []
	for layer: String in ARTS[art].backdrop.layers:
		layers.append(_load(art, "backdrop/%s.png" % layer))
	return {layers = layers, speeds = PackedFloat32Array(ARTS[art].backdrop.speeds),
		open_bottom = ARTS[art].backdrop.get("open_bottom", false)}


static func _load(art: String, file: String) -> Texture2D:
	var path := DIR % art + file
	if not ResourceLoader.exists(path):
		push_error("SpotArt: no %s" % path)
		return null
	return load(path)
