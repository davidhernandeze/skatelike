class_name Boards
extends RefCounted
## The board parts a skater picks from on the profile page (saved in Profile): deck
## graphics (assets/boards, made with Sprite Fusion: see sources.json there), grip tape
## colors and wheel colors. Each list starts with the default.

## Deck graphics: the underside (48 x 12, see BoardView.deck_graphic) and the color
## of the deck's edge, the part seen while riding.
const GRAPHICS := [
	{id = "flames", name = "Flames", texture = "res://assets/boards/flames.png", edge = Color(0.96, 0.5, 0.12)},
	{id = "waves", name = "Waves", texture = "res://assets/boards/waves.png", edge = Color(0.15, 0.72, 0.78)},
]
const GRIPS := [
	{id = "black", name = "Black", color = Color(0.2, 0.2, 0.23)},
	{id = "blue", name = "Blue", color = Color(0.22, 0.38, 0.82)},
]
## Wheels: the urethane and the core.
const WHEELS := [
	{id = "white", name = "White", color = Color(0.95, 0.95, 0.95), core = Color(0.45, 0.47, 0.52)},
	{id = "red", name = "Red", color = Color(0.9, 0.25, 0.3), core = Color(0.98, 0.86, 0.4)},
]


## The entry of `list` with `id`, else the default (the first).
static func find(list: Array, id: String) -> Dictionary:
	for entry: Dictionary in list:
		if entry.id == id:
			return entry
	return list[0]


static func graphic_texture(id: String) -> Texture2D:
	return load(find(GRAPHICS, id).texture)
