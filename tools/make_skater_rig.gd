extends SceneTree
## Cuts the base skater sprite into the pieces of SkaterView's cutout rig: writes a label
## map (one pixel per canvas pixel, red = (piece index + 1) * 20, see SkaterView.LABELS)
## and the rig's joints (canvas px) as JSON. The canvas is the sprite with room around
## it (CANVAS, sprite at OFFSET) for items bigger than the base, like a hat: outfit items
## (assets/characters/items) are drawn on the same canvas, in the same rest pose. The rules below fit assets/characters/
## skater.png (20 x 35, side view facing right); a new base needs its own rules. They fit
## its back view too (skater_back.png: the same figure seen from behind, lined up with it
## pixel for pixel but for the face and the shirt's folds): `--back` cuts that one into
## labels_back.png and base_back.json, with the same joints.
##
##   godot --headless --path . -s tools/make_skater_rig.gd -- [--back] [preview.png]
##
## The optional preview paints each piece its own color, 8x bigger.

const SPRITE := "res://assets/characters/skater.png"
const OUT_LABELS := "res://assets/characters/rig/labels.png"
const OUT_JOINTS := "res://assets/characters/rig/base.json"
const BACK_SPRITE := "res://assets/characters/skater_back.png"
const BACK_LABELS := "res://assets/characters/rig/labels_back.png"
const BACK_JOINTS := "res://assets/characters/rig/base_back.json"
const CANVAS := Vector2i(24, 40)
const OFFSET := Vector2i(2, 5)
## Must match SkaterView.LABELS.
const LABELS := ["arm_back", "thigh_back", "shin_back", "shoe_back", "torso", "head",
	"thigh_front", "shin_front", "shoe_front", "arm_front"]
## Where the pieces turn (sprite px, OFFSET is added on writing), measured on the sprite: the middle of each limb
## where it meets the next, and between the soles for `anchor`.
const JOINTS := {
	anchor = [8.5, 35.0],
	hip = [9.5, 22.5],
	neck = [11.5, 8.0],
	shoulder_back = [4.0, 13.0],
	shoulder_front = [13.5, 15.0],
	hip_back = [6.0, 23.5],
	knee_back = [4.0, 27.0],
	ankle_back = [2.5, 31.0],
	hip_front = [12.0, 23.5],
	knee_front = [11.5, 27.0],
	ankle_front = [10.5, 31.0],
}
## Thigh above this row, shin from it; shoes from SHOE_ROW (except jeans pixels).
const KNEE_ROW := 27
const SHOE_ROW := 31
const LEG_ROW := 23


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var back := args.has("--back")
	args.erase("--back")
	var sprite := BACK_SPRITE if back else SPRITE
	var out_labels := BACK_LABELS if back else OUT_LABELS
	var out_joints := BACK_JOINTS if back else OUT_JOINTS
	var image := Image.load_from_file(ProjectSettings.globalize_path(sprite))
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	# Legs: split back and front by the jeans' two connected parts below the waist.
	var side := _leg_sides(image)
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var piece := ""
			if y <= 6 or (y <= 8 and x >= 10):
				piece = "head"
			elif x <= 4 and y >= 13 and y < LEG_ROW:
				piece = "arm_back"
			elif x >= 13 and y >= 15 and y < LEG_ROW:
				piece = "arm_front"
			elif y < LEG_ROW:
				piece = "torso"
			else:
				var s: String = side.get(Vector2i(x, y), "back" if x < 8 else "front")
				var jeans := _is_jeans(c)
				if y >= SHOE_ROW and not jeans:
					piece = "shoe_" + ("back" if x <= 6 else "front")
				elif y < KNEE_ROW:
					piece = "thigh_" + s
				else:
					piece = "shin_" + s
			label[y * w + x] = LABELS.find(piece)
	var out := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := label[y * w + x]
			if i >= 0:
				out.set_pixel(x + OFFSET.x, y + OFFSET.y, Color8((i + 1) * 20, 0, 0, 255))
	var joints := {}
	for name: String in JOINTS:
		joints[name] = [JOINTS[name][0] + OFFSET.x, JOINTS[name][1] + OFFSET.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/characters/rig"))
	out.save_png(ProjectSettings.globalize_path(out_labels))
	var joints_file := FileAccess.open(ProjectSettings.globalize_path(out_joints), FileAccess.WRITE)
	joints_file.store_string(JSON.stringify({sprite = sprite, labels = out_labels, canvas = [CANVAS.x, CANVAS.y],
		offset = [OFFSET.x, OFFSET.y], joints = joints}, "\t"))
	joints_file.close()
	if args.size() > 0:
		_save_preview(label, w, h, args[0])
	print("labels -> ", out_labels, ", joints -> ", out_joints)
	quit()


func _is_jeans(c: Color) -> bool:
	return c.v >= 0.22 and c.s >= 0.2 and c.h > 0.5 and c.h < 0.72


## Below the waist, each jeans pixel's leg ("back" or "front"): the two connected parts
## of jeans pixels (outline pixels split them), with outline pixels joining the nearer.
func _leg_sides(image: Image) -> Dictionary:
	var side := {}
	var seeds := {back = Vector2i(5, 25), front = Vector2i(12, 25)}
	for name: String in seeds:
		var stack: Array[Vector2i] = [seeds[name]]
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			if side.has(p) or p.x < 0 or p.y < LEG_ROW or p.x >= image.get_width() or p.y >= image.get_height():
				continue
			if not _is_jeans(image.get_pixelv(p)):
				continue
			side[p] = name
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				stack.append(p + d)
	# Everything else below the waist: the side of the nearest jeans pixel.
	var jeans := side.keys()
	for y in range(LEG_ROW, image.get_height()):
		for x in image.get_width():
			var p := Vector2i(x, y)
			if side.has(p) or image.get_pixelv(p).a < 0.5:
				continue
			var best := INF
			for q: Vector2i in jeans:
				var d := Vector2(p - q).length_squared()
				if d < best:
					best = d
					side[p] = side[q]
	return side


func _save_preview(label: PackedInt32Array, w: int, h: int, path: String) -> void:
	var colors := [Color.ORANGE, Color.DARK_GREEN, Color.SEA_GREEN, Color.SADDLE_BROWN, Color.WHITE,
		Color.PINK, Color.ROYAL_BLUE, Color.SKY_BLUE, Color.KHAKI, Color.ORANGE_RED]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.14))
	for y in h:
		for x in w:
			var i := label[y * w + x]
			if i >= 0:
				img.set_pixel(x, y, colors[i])
	img.resize(w * 8, h * 8, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
