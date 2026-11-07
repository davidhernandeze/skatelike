class_name SkaterView
extends Node2D
## The skater as a 2D cutout rig rendered as pixel art: the base sprite cut into pieces
## (a label map and joints, see tools/make_skater_rig.gd) that turn at their joints,
## posed every frame from Runner.skater_pose(). The rig is drawn into a small SubViewport
## at one texel per art pixel and shown `pixel` screen px per texel with nearest
## filtering, like BoardView, so turned pieces stay hard pixel art.
##
## Posing: the hip drops and the torso leans as the skater crouches, the legs reach the
## feet with two-bone IK (knees forward), the arms come up for balance, and the whole rig
## turns with the body, narrows through a body 180 and mirrors with the back to the
## camera. At the rest pose (riding, crouch 0.2) it draws the sprite exactly.
##
## Outfits: every item has the base's shape, so the rest pose is composed once per
## outfit (the base's slot layers recolored, items drawn over them, see Outfits) and cut
## into the same pieces; every pose then works with no new animation.

## Label map index -> piece (tools/make_skater_rig.gd writes red = (index + 1) * 20).
const LABELS: Array[String] = ["arm_back", "thigh_back", "shin_back", "shoe_back", "torso", "head",
	"thigh_front", "shin_front", "shoe_front", "arm_front"]
## Back to front.
const DRAW_ORDER: Array[String] = ["arm_back", "shoe_back", "shin_back", "thigh_back", "shoe_front",
	"shin_front", "thigh_front", "torso", "head", "arm_front"]
## Each piece's joint (it turns about it) in the rig's joints.
const PIVOTS := {
	arm_back = &"shoulder_back", arm_front = &"shoulder_front", torso = &"hip", head = &"neck",
	thigh_back = &"hip_back", shin_back = &"knee_back", shoe_back = &"ankle_back",
	thigh_front = &"hip_front", shin_front = &"knee_front", shoe_front = &"ankle_front",
}
## The piece each piece hangs from: around its joint, a piece also carries a copy of its
## parent's pixels (within JOINT_CAP texels, under its own), so bending the joint
## doesn't open a gap.
const PARENTS := {
	thigh_back = "torso", shin_back = "thigh_back", shoe_back = "shin_back",
	thigh_front = "torso", shin_front = "thigh_front", shoe_front = "shin_front",
}
const JOINT_CAP := 2.5
## Turned pieces are drawn RotSprite style (see _turned()), cached per this many degrees.
const ANGLE_STEP := 3.0
## Texels each side of the rig's anchor (between the soles): room for the rig at any turn.
const HALF := 40
## Crouch the rest pose is drawn at (riding along, see Runner._step_figure()).
const REST_CROUCH := 0.2
## Pixels darker than this are outline (kept as they are by recolors).
const OUTLINE_V := 0.22
## How far apart the feet are at rest in Runner.skater_pose(), each side of the base, at
## the default board_size (px).
const REST_FOOT := 22.0

@export var sprite: Texture2D = preload("res://assets/characters/skater.png")
@export var labels: Texture2D = preload("res://assets/characters/rig/labels.png")
@export_file("*.json") var joints_file := "res://assets/characters/rig/base.json"
## Screen px per texel at the default board_size (Runner.skater_pixel when following one).
@export var pixel := 5
## At full crouch: how far the hip drops (texels), the torso leans forward and the arms
## come up (degrees).
@export var crouch_drop := 3.0
@export var crouch_lean := 14.0
@export var arm_raise := 45.0
## Riding a manual: how far the hip moves toward the raised end (texels).
@export var manual_shift := 1.5
## Most the hip sinks to let a foot reach (texels): the back foot pushing on the ground.
@export var max_reach_drop := 3.5
## Width of the side view in the middle of a body 180 (1 = the sprite's); the arms come
## in to the body there.
@export var min_turn_width := 0.8

## The runner whose skater this draws (it skips its own then).
var runner: Runner:
	set(value):
		runner = value
		if runner:
			runner.skater_view = self
			pixel = runner.skater_pixel

var _viewport: SubViewport
var _root: Node2D
var _shown: Sprite2D
var _pieces := {}
## Joints relative to the anchor (texels, y down, facing right), and where the anchor is
## on the rig's canvas (texels): the base sprite placed at `_offset` with room for items.
var _joints := {}
var _anchor := Vector2.ZERO
var _canvas := Vector2i.ZERO
var _offset := Vector2i.ZERO
## What it wears (slot -> Outfits item id), the base's slot layers and each canvas
## pixel's piece (made once).
var _outfit := Outfits.default_outfit()
var _layers := {}
var _field := PackedInt32Array()
## Each piece in the rest pose: {image (on the canvas), big (its used part, 8x by Scale2x
## three times), crop (that part on the canvas), turns: {angle step: [texture, origin]}}.
var _art := {}


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(HALF * 2, HALF * 2)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_root = Node2D.new()
	_root.position = Vector2(HALF, HALF)
	_viewport.add_child(_root)
	_load_joints()
	_cut_pieces(_compose())
	_shown = Sprite2D.new()
	_shown.texture = _viewport.get_texture()
	_shown.centered = false
	_shown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_shown)


func _process(_delta: float) -> void:
	if runner:
		show_pose(runner.skater_pose(), runner.board_size.x / 96.0)


## Draws the skater at a pose from Runner.skater_pose(), `size_scale` times the default size.
func show_pose(pose: Dictionary, size_scale := 1.0) -> void:
	if _root == null:
		return
	var s := pixel * size_scale
	var face: float = pose.face
	# Through a body 180 the side view narrows to min_turn_width and mirrors: a body seen
	# from the front is narrower than from the side, but not a sliver.
	var width := signf(face if face != 0.0 else 1.0) * lerpf(min_turn_width, 1.0, smoothstep(0.0, 1.0, absf(face)))
	_root.rotation = pose.angle
	_root.scale = Vector2(width, 1.0)
	_solve(pose, s)
	var base: Vector2 = pose.base
	base = (base / Runner.PIXEL).round() * Runner.PIXEL  # On the world's pixel grid, like the board.
	_shown.scale = Vector2(s, s)
	_shown.position = base - Vector2(HALF, HALF) * s


## Places and turns every piece for `pose` (texels, rig space: anchor at 0, facing right).
func _solve(pose: Dictionary, s: float) -> void:
	var fallen: bool = pose.fall >= 0.0
	var c := 0.0 if fallen else clampf((float(pose.crouch) - REST_CROUCH) / (1.0 - REST_CROUCH), 0.0, 1.0)
	var manual: float = pose.get("manual", 0.0)
	var hip: Vector2 = _joints.hip + Vector2(0.6 * c + manual * manual_shift, crouch_drop * c)
	# Where the feet go: the runner's feet (on the board, or the ground while pushing)
	# relative to where they are at rest.
	var feet: Array = pose.feet
	var ankles: Array[Vector2] = []
	for i in 2:
		var side := "back" if i == 0 else "front"
		var local: Vector2 = (feet[i] - pose.base).rotated(-float(pose.angle)) / s
		var rest_local := Vector2((-1.0 if i == 0 else 1.0) * REST_FOOT / pixel, 0.0)
		ankles.append(_joints[&"ankle_" + side] + (local - rest_local))
	# A foot out of reach (the back foot pushing on the ground): the hip sinks toward it,
	# bending the other knee, so the foot gets there.
	for i in 2:
		var side := "back" if i == 0 else "front"
		var to_foot: Vector2 = ankles[i] - (hip + _joints[&"hip_" + side] - _joints.hip)
		var excess := to_foot.length() - _leg_length(side)
		if excess > 0.0:
			hip += to_foot.normalized() * minf(excess, max_reach_drop)
	var lean := deg_to_rad(crouch_lean) * c
	_place("torso", hip, lean)
	var on_torso := func(j: StringName) -> Vector2: return hip + (_joints[j] - _joints.hip).rotated(lean)
	_place("head", on_torso.call(&"neck"), lean * 0.4)
	var raise := deg_to_rad(arm_raise) * c
	# Mid-180 the arms hang in toward the body (seen from the front they'd be in line
	# with it, not out to the sides).
	var tuck := 1.0 - smoothstep(0.0, 0.6, absf(float(pose.face)))
	_place("arm_back", on_torso.call(&"shoulder_back"), lerpf(lean + raise, deg_to_rad(-25.0), tuck))
	_place("arm_front", on_torso.call(&"shoulder_front"), lerpf(lean - raise, deg_to_rad(20.0), tuck))
	for i in 2:
		var side := "back" if i == 0 else "front"
		var hip_j: Vector2 = hip + (_joints[&"hip_" + side] - _joints.hip)
		var knee_rest: Vector2 = _joints[&"knee_" + side]
		var ankle_rest: Vector2 = _joints[&"ankle_" + side]
		var hip_rest: Vector2 = _joints[&"hip_" + side]
		var ik := _two_bone(hip_j, ankles[i], (knee_rest - hip_rest).length(), (ankle_rest - knee_rest).length())
		var knee: Vector2 = ik[0]
		var ankle: Vector2 = ik[1]
		_place("thigh_" + side, hip_j, (knee - hip_j).angle() - (knee_rest - hip_rest).angle())
		_place("shin_" + side, knee, (ankle - knee).angle() - (ankle_rest - knee_rest).angle())
		_place("shoe_" + side, ankle, 0.0)


## Thigh plus shin of a leg ("back" or "front"), at the rest pose (texels).
func _leg_length(side: String) -> float:
	var knee: Vector2 = _joints[&"knee_" + side]
	return (knee - _joints[&"hip_" + side]).length() + (_joints[&"ankle_" + side] - knee).length()


## A piece's joint on `at` (rig space), turned `angle` about it. The piece is drawn
## unturned (turned art, see _turned()) with its texels on whole rig texels, so pixels stay
## square and an unturned piece is drawn exactly as in the sprite.
func _place(piece: String, at: Vector2, angle: float) -> void:
	var node: Sprite2D = _pieces[piece]
	var pivot: Vector2 = _joints[PIVOTS[piece]]
	var turn := _turned(piece, roundi(rad_to_deg(angle) / ANGLE_STEP))
	node.texture = turn[0]
	node.offset = Vector2(turn[1]) - (pivot + _anchor)
	node.position = (at - pivot).round() + pivot


## A piece's art turned `step` * ANGLE_STEP degrees about its joint, and where its top
## left is on the canvas: each texel takes the pixel under its middle, turned back, in the
## piece made 8x bigger with Scale2x (RotSprite), which keeps lines and outlines whole
## where turning the small art would break them up.
func _turned(piece: String, step: int) -> Array:
	var art: Dictionary = _art[piece]
	var turns: Dictionary = art.turns
	if turns.has(step):
		return turns[step]
	var angle := deg_to_rad(step * ANGLE_STEP)
	var crop: Rect2i = art.crop
	var joint: Vector2 = _joints[PIVOTS[piece]] + _anchor
	var low := Vector2(INF, INF)
	var high := -low
	for corner in [Vector2(crop.position), Vector2(crop.end.x, crop.position.y), Vector2(crop.end),
			Vector2(crop.position.x, crop.end.y)]:
		var q: Vector2 = joint + (corner - joint).rotated(angle)
		low = low.min(q)
		high = high.max(q)
	var origin := Vector2i(low.floor())
	var size := Vector2i(high.ceil()) - origin
	var big: Image = art.big
	var out := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var p := joint + (Vector2(origin.x + x + 0.5, origin.y + y + 0.5) - joint).rotated(-angle)
			var b := Vector2i(((p - Vector2(crop.position)) * 8.0).floor())
			if b.x >= 0 and b.y >= 0 and b.x < big.get_width() and b.y < big.get_height():
				out.set_pixel(x, y, big.get_pixelv(b))
	var turn := [ImageTexture.create_from_image(out), origin]
	turns[step] = turn
	return turn


## `image` twice as big, by Scale2x (EPX): each pixel becomes four, rounding off the
## corners of diagonal lines.
static func _scale2x(image: Image) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var out := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := image.get_pixel(x, y)
			var a := image.get_pixel(x, y - 1) if y > 0 else p
			var b := image.get_pixel(x + 1, y) if x < w - 1 else p
			var c := image.get_pixel(x - 1, y) if x > 0 else p
			var d := image.get_pixel(x, y + 1) if y < h - 1 else p
			out.set_pixel(x * 2, y * 2, a if c == a and c != d and a != b else p)
			out.set_pixel(x * 2 + 1, y * 2, b if a == b and a != c and b != d else p)
			out.set_pixel(x * 2, y * 2 + 1, c if d == c and d != b and c != a else p)
			out.set_pixel(x * 2 + 1, y * 2 + 1, d if b == d and b != a and d != c else p)
	return out


## Knee and ankle for a leg from `hip` reaching `target` with bones `a` (thigh) and `b`
## (shin), the knee bent forward (+x). Out of reach: straight toward the target.
static func _two_bone(hip: Vector2, target: Vector2, a: float, b: float) -> Array[Vector2]:
	var d := target - hip
	var dist := clampf(d.length(), absf(a - b) + 0.01, a + b)
	var dir := d.normalized() if d.length() > 0.001 else Vector2.DOWN
	var ankle := hip + dir * dist
	var cos_a := clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
	var bend := acos(cos_a)
	var k1 := hip + dir.rotated(bend) * a
	var k2 := hip + dir.rotated(-bend) * a
	return [k1 if k1.x > k2.x else k2, ankle]


func _load_joints() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(joints_file))
	var raw: Dictionary = data.joints
	_anchor = Vector2(raw.anchor[0], raw.anchor[1]).floor()  # On a texel corner.
	for name: String in raw:
		_joints[StringName(name)] = Vector2(raw[name][0], raw[name][1]) - _anchor
	_canvas = Vector2i(data.canvas[0], data.canvas[1])
	_offset = Vector2i(data.offset[0], data.offset[1])


## Puts on the outfit picked on the profile page (Profile, Outfits).
func apply_profile() -> void:
	Profile.load_profile()
	set_outfit(Profile.outfit)


## Wears `outfit` (slot -> Outfits item id; missing slots: the default).
func set_outfit(outfit: Dictionary) -> void:
	_outfit = outfit.duplicate()
	if _root:
		_cut_pieces(_compose())


## The skater in the rest pose on the rig's canvas, wearing the outfit: the base
## character's slot layers (split by color, see _base_layers()) recolored by their items'
## ramps, then the items drawn over them in Outfits.DRAW_ORDER (an item shirt instead
## of the base's, hair under the hat). Outline pixels keep their color.
func _compose() -> Image:
	if _layers.is_empty():
		_layers = _base_layers()
	var out := Image.create(_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(_layers.outline, Rect2i(Vector2i.ZERO, _canvas), Vector2i.ZERO)
	out.blend_rect(_layers.detail, Rect2i(Vector2i.ZERO, _canvas), Vector2i.ZERO)
	var hat := Outfits.find("hat", _outfit.get("hat", ""))
	for slot in Outfits.DRAW_ORDER:
		var item := Outfits.find(slot, _outfit.get(slot, ""))
		var layer: Image
		if item.layer == null:
			continue
		elif item.layer == "":
			layer = _layers.get(slot)
		else:
			layer = Outfits.recolored(Outfits.layer_image(item.layer), item.ramp)
		if layer and item.layer == "":
			layer = Outfits.recolored(layer, item.ramp)
		if layer and slot == "hair" and hat.layer is String and hat.layer != "":
			layer = _under_hat(layer, Outfits.layer_image(hat.layer))
		if layer:
			out.blend_rect(layer, Rect2i(Vector2i.ZERO, _canvas), Vector2i.ZERO)
	return out


## `hair` tucked under `hat`: no hair above the hat's lowest row (its rim), so it
## doesn't stick out through the top.
static func _under_hat(hair: Image, hat: Image) -> Image:
	var rim := hat.get_used_rect().end.y - 1
	var out := hair.duplicate() as Image
	out.fill_rect(Rect2i(0, 0, out.get_width(), maxi(rim, 0)), Color(0, 0, 0, 0))
	return out


## The base sprite on the canvas split into layers: "outline" (dark pixels), "skin",
## "shirt", "pants", "shoes", and "detail" (the eye: light pixels on the head that aren't
## skin), by each pixel's color and rig piece.
func _base_layers() -> Dictionary:
	var image := sprite.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var labels_of := _labels()
	var layers := {}
	for name in ["outline", "detail", "skin", "shirt", "pants", "shoes"]:
		layers[name] = Image.create(_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var at := Vector2i(x, y) + _offset
			var piece := LABELS[labels_of[at.y * _canvas.x + at.x]] if labels_of[at.y * _canvas.x + at.x] >= 0 else ""
			var layer := "shirt"
			if c.v < OUTLINE_V:
				layer = "outline"
			elif c.s >= 0.2 and (c.h < 0.12 or c.h > 0.95):
				layer = "skin"
			elif c.s >= 0.2 and c.h > 0.5 and c.h < 0.72:
				layer = "pants"
			elif piece == "head":
				layer = "detail"
			elif piece.begins_with("shoe"):
				layer = "shoes"
			elif piece.begins_with("thigh") or piece.begins_with("shin"):
				layer = "pants"
			(layers[layer] as Image).set_pixelv(at, c)
	return layers


## The label map: each canvas pixel's piece (index in LABELS), -1 where it has none.
func _labels() -> PackedInt32Array:
	var label_image := labels.get_image()
	label_image.convert(Image.FORMAT_RGBA8)
	var out := PackedInt32Array()
	out.resize(_canvas.x * _canvas.y)
	for y in _canvas.y:
		for x in _canvas.x:
			var l := label_image.get_pixel(x, y)
			out[y * _canvas.x + x] = roundi(l.r * 255.0 / 20.0) - 1 if l.a > 0.5 else -1
	return out


## Each canvas pixel's piece: its label, or for pixels outside the base (an item reaching
## past it, like a hat) the nearest labeled pixel's.
func _label_field() -> PackedInt32Array:
	var field := _labels()
	var labeled: Array[Vector2i] = []
	for y in _canvas.y:
		for x in _canvas.x:
			if field[y * _canvas.x + x] >= 0:
				labeled.append(Vector2i(x, y))
	var out := field.duplicate()
	for y in _canvas.y:
		for x in _canvas.x:
			if out[y * _canvas.x + x] >= 0:
				continue
			var best := INF
			for q in labeled:
				var d := Vector2(q - Vector2i(x, y)).length_squared()
				if d < best:
					best = d
					out[y * _canvas.x + x] = field[q.y * _canvas.x + q.x]
	return out


## Whether the pixel at x, y of `image` touches a transparent one (or the border).
func _on_edge(image: Image, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := Vector2i(x + dx, y + dy)
			if q.x < 0 or q.y < 0 or q.x >= _canvas.x or q.y >= _canvas.y or image.get_pixelv(q).a < 0.5:
				return true
	return false


## One Sprite2D per piece from `image` (the canvas in the rest pose): the pixels of that
## piece, plus each edge outline pixel next to it (so a piece that turns away keeps its
## edge) and its parent's pixels around its joint (PARENTS), drawn about its joint, with
## its 8x Scale2x art for turning (_turned()). The nodes are made once; later outfits
## just change their art.
func _cut_pieces(image: Image) -> void:
	if _field.is_empty():
		_field = _label_field()
	var images := {}
	for name in LABELS:
		images[name] = Image.create(_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8)
	for y in _canvas.y:
		for x in _canvas.x:
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var i := _field[y * _canvas.x + x]
			(images[LABELS[i]] as Image).set_pixel(x, y, c)
			# An outline pixel on the figure's edge: also the edge of the pieces it touches
			# (inner outlines aren't: inside the figure they'd show as dark specks).
			if c.v < OUTLINE_V and _on_edge(image, x, y):
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x < 0 or q.y < 0 or q.x >= _canvas.x or q.y >= _canvas.y:
						continue
					var j := _field[q.y * _canvas.x + q.x]
					var cq := image.get_pixelv(q)
					if j != i and cq.a >= 0.5 and cq.v >= OUTLINE_V:
						(images[LABELS[j]] as Image).set_pixel(x, y, c)
	for name in LABELS:
		var piece: Image = images[name]
		var crop := piece.get_used_rect().grow(1).intersection(Rect2i(Vector2i.ZERO, _canvas))
		var big := piece.get_region(crop)
		for i in 3:
			big = _scale2x(big)
		_art[name] = {big = big, crop = crop, turns = {0: [ImageTexture.create_from_image(piece), Vector2i.ZERO]}}
	for name in DRAW_ORDER:
		var node: Sprite2D = _pieces.get(name)
		if node == null:
			node = Sprite2D.new()
			node.centered = false
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_root.add_child(node)
			_pieces[name] = node
		_place(name, _joints[PIVOTS[name]], 0.0)
