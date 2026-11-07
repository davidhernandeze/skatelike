class_name Outfits
extends RefCounted
## What a skater wears, picked on the profile page (saved in Profile): one entry per slot.
## Every item has the base character's shape (the rig's rest pose, see SkaterView), so
## it works in every pose with no new animation. An item is a layer and a color ramp:
##   layer: "" for the base character's own pixels of that slot (its skin, white tee,
##          jeans or shoes), or an image on the rig's canvas worn instead (a shirt) or
##          over it (hair, hats): cut from Sprite Fusion edits of the base, drawn in
##          light grey (tools/sf_item.sh, tools/extract_item.gd); null for nothing.
##   ramp:  [dark, mid, light]: the layer's shading recolored from its darkest to its
##          lightest; empty keeps the layer's own colors.
## Each list starts with the default.

const SLOTS: Array[String] = ["skin", "hair", "hat", "shirt", "pants", "shoes"]
## Drawn in this order, each over the ones before.
const DRAW_ORDER: Array[String] = ["skin", "pants", "shoes", "shirt", "hair", "hat"]

const ITEMS := {
	skin = [
		{id = "tan", name = "Tan", layer = "", ramp = []},
		{id = "pale", name = "Pale", layer = "", ramp = [Color("b88068"), Color("f0c8a8"), Color("fde4cc")]},
		{id = "light", name = "Light", layer = "", ramp = [Color("a8705a"), Color("e8b08c"), Color("fcd8b8")]},
		{id = "brown", name = "Brown", layer = "", ramp = [Color("5a3220"), Color("93603c"), Color("c08458")]},
		{id = "dark", name = "Dark", layer = "", ramp = [Color("2e1a10"), Color("5e3622"), Color("8a5634")]},
	],
	hair = [
		{id = "none", name = "Bald", layer = null, ramp = []},
		{id = "short_black", name = "Short black", layer = "res://assets/characters/items/hair_short.png",
			ramp = [Color("141010"), Color("2a2220"), Color("4a3c34")]},
		{id = "short_brown", name = "Short brown", layer = "res://assets/characters/items/hair_short.png",
			ramp = [Color("3a2414"), Color("6a4226"), Color("94623a")]},
		{id = "short_blond", name = "Short blond", layer = "res://assets/characters/items/hair_short.png",
			ramp = [Color("8a6420"), Color("c89a3a"), Color("ecd27a")]},
		{id = "short_ginger", name = "Short ginger", layer = "res://assets/characters/items/hair_short.png",
			ramp = [Color("6a2410"), Color("b04a1e"), Color("e0803e")]},
		{id = "curly_black", name = "Curly black", layer = "res://assets/characters/items/hair_curly.png",
			ramp = [Color("141010"), Color("2a2220"), Color("4a3c34")]},
		{id = "curly_brown", name = "Curly brown", layer = "res://assets/characters/items/hair_curly.png",
			ramp = [Color("3a2414"), Color("6a4226"), Color("94623a")]},
		{id = "curly_blond", name = "Curly blond", layer = "res://assets/characters/items/hair_curly.png",
			ramp = [Color("8a6420"), Color("c89a3a"), Color("ecd27a")]},
		{id = "curly_ginger", name = "Curly ginger", layer = "res://assets/characters/items/hair_curly.png",
			ramp = [Color("6a2410"), Color("b04a1e"), Color("e0803e")]},
	],
	hat = [
		{id = "none", name = "None", layer = null, ramp = []},
		{id = "beanie_grey", name = "Grey beanie", layer = "res://assets/characters/items/hat_beanie.png",
			ramp = []},
		{id = "beanie_red", name = "Red beanie", layer = "res://assets/characters/items/hat_beanie.png",
			ramp = [Color("5a1418"), Color("b02a2a"), Color("e8665a")]},
		{id = "beanie_black", name = "Black beanie", layer = "res://assets/characters/items/hat_beanie.png",
			ramp = [Color("101014"), Color("26262c"), Color("4a4a54")]},
		{id = "beanie_orange", name = "Orange beanie", layer = "res://assets/characters/items/hat_beanie.png",
			ramp = [Color("7a2e0c"), Color("d0601c"), Color("f49a4c")]},
		{id = "cap_navy", name = "Navy cap", layer = "res://assets/characters/items/hat_cap.png",
			ramp = [Color("121a3a"), Color("24346e"), Color("4a64a8")]},
		{id = "cap_white", name = "White cap", layer = "res://assets/characters/items/hat_cap.png",
			ramp = [Color("b8b4ac"), Color("e8e4dc"), Color("fcfaf4")]},
		{id = "cap_red", name = "Red cap", layer = "res://assets/characters/items/hat_cap.png",
			ramp = [Color("5a1418"), Color("b02a2a"), Color("e8665a")]},
		{id = "cap_green", name = "Green cap", layer = "res://assets/characters/items/hat_cap.png",
			ramp = [Color("173a22"), Color("2f6b3a"), Color("5ea062")]},
	],
	shirt = [
		{id = "white", name = "White tee", layer = "", ramp = []},
		{id = "red", name = "Red tee", layer = "",
			ramp = [Color("5a1418"), Color("b02a2a"), Color("e8665a")]},
		{id = "black", name = "Black tee", layer = "",
			ramp = [Color("101014"), Color("26262c"), Color("4a4a54")]},
		{id = "mustard", name = "Mustard tee", layer = "",
			ramp = [Color("7a5410"), Color("d49a24"), Color("f4cc5c")]},
		{id = "green", name = "Green tee", layer = "",
			ramp = [Color("173a22"), Color("2f6b3a"), Color("5ea062")]},
		{id = "navy", name = "Navy tee", layer = "",
			ramp = [Color("121a3a"), Color("24346e"), Color("4a64a8")]},
		{id = "long_white", name = "White long sleeve", layer = "res://assets/characters/items/shirt_longsleeve.png",
			ramp = []},
		{id = "long_black", name = "Black long sleeve", layer = "res://assets/characters/items/shirt_longsleeve.png",
			ramp = [Color("101014"), Color("26262c"), Color("4a4a54")]},
		{id = "long_green", name = "Green long sleeve", layer = "res://assets/characters/items/shirt_longsleeve.png",
			ramp = [Color("173a22"), Color("2f6b3a"), Color("5ea062")]},
		{id = "long_mustard", name = "Mustard long sleeve", layer = "res://assets/characters/items/shirt_longsleeve.png",
			ramp = [Color("7a5410"), Color("d49a24"), Color("f4cc5c")]},
		{id = "hoodie_grey", name = "Grey hoodie", layer = "res://assets/characters/items/shirt_hoodie.png",
			ramp = []},
		{id = "hoodie_black", name = "Black hoodie", layer = "res://assets/characters/items/shirt_hoodie.png",
			ramp = [Color("101014"), Color("26262c"), Color("4a4a54")]},
		{id = "hoodie_navy", name = "Navy hoodie", layer = "res://assets/characters/items/shirt_hoodie.png",
			ramp = [Color("121a3a"), Color("24346e"), Color("4a64a8")]},
		{id = "hoodie_red", name = "Red hoodie", layer = "res://assets/characters/items/shirt_hoodie.png",
			ramp = [Color("5a1418"), Color("b02a2a"), Color("e8665a")]},
		{id = "hoodie_green", name = "Green hoodie", layer = "res://assets/characters/items/shirt_hoodie.png",
			ramp = [Color("173a22"), Color("2f6b3a"), Color("5ea062")]},
	],
	pants = [
		{id = "jeans", name = "Blue jeans", layer = "", ramp = []},
		{id = "black", name = "Black jeans", layer = "", ramp = [Color("0e0e12"), Color("22222a"), Color("3c3c48")]},
		{id = "khaki", name = "Khakis", layer = "", ramp = [Color("6a5530"), Color("a88a52"), Color("d2b97e")]},
		{id = "grey", name = "Grey", layer = "", ramp = [Color("3a3c42"), Color("6c7078"), Color("a4a8b0")]},
	],
	shoes = [
		{id = "white", name = "White", layer = "", ramp = []},
		{id = "black", name = "Black", layer = "", ramp = [Color("101012"), Color("2a2a30"), Color("55555f")]},
		{id = "red", name = "Red", layer = "", ramp = [Color("5a1014"), Color("b0262c"), Color("e85a50")]},
	],
}


## Ids saved in profiles before their items were replaced, and what they wear now.
const RENAMED := {hair = {buzz_black = "short_black", buzz_brown = "short_brown", buzz_blond = "short_blond"}}


## The item of `slot` with `id`, else the slot's default (the first).
static func find(slot: String, id: String) -> Dictionary:
	id = RENAMED.get(slot, {}).get(id, id)
	for item: Dictionary in ITEMS[slot]:
		if item.id == id:
			return item
	return ITEMS[slot][0]


## Every slot's default item id.
static func default_outfit() -> Dictionary:
	var outfit := {}
	for slot in SLOTS:
		outfit[slot] = ITEMS[slot][0].id
	return outfit


## A color to show the item by (a picker swatch): its ramp's middle, or the base's.
static func swatch(item: Dictionary, base_color: Color) -> Color:
	var ramp: Array = item.ramp
	return ramp[1] if ramp.size() == 3 else base_color


## The image of an item's layer (a path in ITEMS).
static func layer_image(path: String) -> Image:
	var image := (load(path) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## `layer` with its shading mapped onto `ramp` ([dark, mid, light]) from its darkest to
## its lightest pixel; outline pixels and an empty ramp keep their colors.
static func recolored(layer: Image, ramp: Array) -> Image:
	if ramp.size() != 3:
		return layer
	var out := layer.duplicate() as Image
	var low := INF
	var high := -INF
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a >= 0.5 and c.v >= SkaterView.OUTLINE_V:
				low = minf(low, c.get_luminance())
				high = maxf(high, c.get_luminance())
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a < 0.5 or c.v < SkaterView.OUTLINE_V:
				continue
			var t := 0.5 if high - low < 0.001 else (c.get_luminance() - low) / (high - low)
			var color: Color = ramp[0].lerp(ramp[1], t * 2.0) if t < 0.5 else ramp[1].lerp(ramp[2], t * 2.0 - 1.0)
			out.set_pixel(x, y, Color(color, c.a))
	return out


## A picker icon for an item with its own image: the recolored layer cropped to what it
## covers, scaled up (whole pixels) to fit `size`, centered. Null for the base's layers.
static func icon(item: Dictionary, size: int) -> Image:
	if not (item.layer is String) or item.layer == "":
		return null
	var layer := recolored(layer_image(item.layer), item.ramp)
	var used := layer.get_used_rect()
	var crop := layer.get_region(used)
	var zoom := maxi(1, mini(size / used.size.x, size / used.size.y))
	crop.resize(used.size.x * zoom, used.size.y * zoom, Image.INTERPOLATE_NEAREST)
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	out.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), (Vector2i(size, size) - crop.get_size()) / 2)
	return out
