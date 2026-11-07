class_name BoardView
extends Node2D
## The board as a small 3D model rendered as pixel art: a low-res SubViewport (one
## texel = `pixel` screen px) drawn back as a sprite with nearest filtering, stepped
## toon shading and a 1 texel outline. Flips, shuvits and body turns are real 3D turns
## (Runner.board_motion()), so the grip shows on top and the deck graphic underneath.
## The wheels roll with the board (and keep spinning down in the air). A board item is
## its textures and colors: `deck_graphic`, grip, deck, truck, wheel and wheel core
## colors; apply_profile() puts on the one picked on the profile page. Follows `runner` when set; else show_pose() places it by hand (a preview).

## The runner whose board this draws (it skips its own flat board then).
var runner: Runner:
	set(value):
		runner = value
		if runner:
			runner.board_view = self

## Screen px per texel of the pixel art: the game's one pixel size (Runner.PIXEL), shared
## with the skater sprite and the tiles.
@export var pixel := 3
## How far the camera looks down on the board (degrees): a strip of grip shows on top.
@export var view_pitch := 10.0
## Steps per turn that flips and shuvits snap to (0 = smooth): stepped turns read as
## hand-animated frames and keep the edges from flickering mid-spin.
@export var turn_steps := 24
## Snap the board's place on screen to the texel grid.
@export var snap := true
@export var outline := true
@export var outline_color := Color(0.05, 0.05, 0.08)
## Underneath the deck (shows in flips), across the deck nose to tail. Null: a
## generated placeholder. Sized for the texels it covers: 32 x 8 at pixel 3.
@export var deck_graphic: Texture2D
## The top of the deck. Null: generated grip tape in `grip_color`.
@export var grip: Texture2D
@export var grip_color := Color(0.2, 0.2, 0.23)
@export var deck_color := Color(1.0, 0.85, 0.3)
@export var truck_color := Color(0.7, 0.72, 0.78)
## The wheels' urethane, and their core (the hub in the middle).
@export var wheel_color := Color(0.95, 0.95, 0.95)
@export var wheel_core_color := Color(0.45, 0.47, 0.52)
## Steps per turn that the wheels' roll snaps to (0 = smooth).
@export var wheel_steps := 16
## How fast spinning wheels slow down in the air (1/s).
@export var wheel_spin_decay := 0.6
## Size of the board on screen at default board_size (px): length, height and width.
@export var board_size := Vector3(96.0, 28.0, 24.0)

const HALF_LENGTH := 49.0
## Where the kicktails start to rise (|x|) and the ends round off in plan view.
const KICK_START := 38.0
const ROUND_START := 37.0
## Most the wheels are seen to turn in a frame (rad): see _process().
const MAX_WHEEL_STEP := PI * 0.4

var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D
var _sprite: Sprite2D
var _deck_materials: Array[ShaderMaterial] = []
var _wheel_material: ShaderMaterial
var _wheels: Array[MeshInstance3D] = []
## How far the wheels have turned (rad, + clockwise on screen) and how fast (rad/s).
var _wheel_turn := 0.0
var _wheel_spin := 0.0

const TOON := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform bool use_tex = false;
// Vertex color is a mask: red takes `accent` (a wheel's core), green darkens (a mark
// on the wheel, so it shows rolling).
uniform vec4 accent : source_color = vec4(1.0);
// Light from the upper left, toward the camera (view space = world: the camera never turns).
uniform vec3 light_dir = vec3(-0.45, 0.75, 0.5);
uniform float mid = 0.78;
uniform float dark = 0.58;
void fragment() {
	vec3 base = albedo.rgb;
	if (use_tex) {
		base *= texture(tex, UV).rgb;
	}
	base = mix(base, accent.rgb, COLOR.r) * (1.0 - 0.5 * COLOR.g);
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	float d = dot(n, normalize(light_dir));
	ALBEDO = base * (d > 0.35 ? 1.0 : (d > -0.2 ? mid : dark));
}
"""

const OUTLINE := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform bool enabled = true;
varying vec4 modulate;
void vertex() {
	modulate = COLOR;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float a = max(max(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
				max(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
		c = (enabled && a >= 0.5) ? outline_color : vec4(0.0);
	} else {
		c.a = 1.0;
	}
	COLOR = c * modulate;
}
"""


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = Vector3(0.0, 0.0, 300.0)
	_camera.near = 1.0
	_camera.far = 600.0
	_viewport.add_child(_camera)
	_camera.current = true
	_model = Node3D.new()
	_viewport.add_child(_model)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _build_mesh()
	_model.add_child(mesh)
	var wheel_mesh := _build_wheel(Runner.WHEEL_R, 5.0)
	for x in [-Runner.WHEEL_X, Runner.WHEEL_X]:
		for z in [-8.5, 8.5]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(x, -Runner.WHEEL_Y, z)
			_model.add_child(wheel)
			_wheels.append(wheel)
	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var outline_material := ShaderMaterial.new()
	outline_material.shader = _shader(OUTLINE)
	_sprite.material = outline_material
	add_child(_sprite)
	_fit_viewport(Vector2.ONE)
	_update_materials()
	if runner:
		truck_color = runner.truck_color
		apply_profile()


func _process(delta: float) -> void:
	if runner:
		var radius := Runner.WHEEL_R * runner.board_size.x / 96.0
		if runner.wheels_down():
			_wheel_spin = runner.rolling_velocity() / radius
		else:
			_wheel_spin *= exp(-wheel_spin_decay * delta)
		# The bar looks the same every half turn: past a quarter turn a frame it would
		# seem to spin backward, so fast wheels show just under that.
		roll_wheels(clampf(_wheel_spin * delta, -MAX_WHEEL_STEP, MAX_WHEEL_STEP))
		var m := runner.board_motion()
		var size_scale := runner.board_size / Vector2(96.0, 28.0)
		show_pose(m.anchor, m.local_anchor, m.angle, m.roll, m.yaw, size_scale)


## Draws the board with `local_anchor` (board space, see Runner.board_motion()) on
## `anchor`, turned `angle` in the screen plane, rolled `roll` and turned `yaw`, at
## `size_scale` times the default size.
func show_pose(anchor: Vector2, local_anchor: Vector2, angle: float, roll: float, yaw: float,
		size_scale := Vector2.ONE) -> void:
	if _viewport == null:
		return
	_fit_viewport(size_scale)
	var basis := _basis(angle, _stepped(roll), _stepped(yaw), size_scale)
	_model.transform = Transform3D(basis, Vector3.ZERO)
	var origin := anchor - _project(basis, local_anchor)
	if snap:
		origin = (origin / float(pixel)).round() * float(pixel)
	_sprite.position = origin
	(_sprite.material as ShaderMaterial).set_shader_parameter("enabled", outline)
	(_sprite.material as ShaderMaterial).set_shader_parameter("outline_color", outline_color)


## Turns the wheels `angle` more (rad, + clockwise on screen: rolling to the right).
func roll_wheels(angle: float) -> void:
	_wheel_turn = fmod(_wheel_turn + angle, TAU)
	var step := TAU / wheel_steps if wheel_steps > 0 else 0.0
	var shown := roundf(_wheel_turn / step) * step if step > 0.0 else _wheel_turn
	for wheel in _wheels:
		wheel.basis = Basis(Vector3.BACK, -shown)


## Puts on the board picked on the profile page (Profile, Boards).
func apply_profile() -> void:
	Profile.load_profile()
	var graphic := Boards.find(Boards.GRAPHICS, Profile.board_graphic)
	var wheels := Boards.find(Boards.WHEELS, Profile.board_wheels)
	grip_color = Boards.find(Boards.GRIPS, Profile.board_grip).color
	set_look(Boards.graphic_texture(graphic.id), null, graphic.edge, truck_color, wheels.color, wheels.core)


## Changes the board's look (an inventory board): textures (null = generated) and colors.
func set_look(graphic: Texture2D, top: Texture2D, deck: Color, trucks: Color, wheels: Color,
		cores: Color) -> void:
	deck_graphic = graphic
	grip = top
	deck_color = deck
	truck_color = trucks
	set_wheel_colors(wheels, cores)


## Changes just the wheels: the urethane and the core.
func set_wheel_colors(wheels: Color, cores: Color) -> void:
	wheel_color = wheels
	wheel_core_color = cores
	_update_materials()


## Board space to model space: the camera looking down `view_pitch`, the screen turn
## (clockwise on screen with y down), then the board's own yaw and roll, and its size.
func _basis(angle: float, roll: float, yaw: float, size_scale: Vector2) -> Basis:
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(view_pitch))
	var plane := Basis(Vector3.BACK, -angle)
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, roll)
	return pitch * plane * turn * Basis.from_scale(Vector3(size_scale.x, size_scale.y, size_scale.x))


## Where a board-space point (y down, on the deck's middle plane) lands on screen,
## relative to the model's origin.
func _project(basis: Basis, local: Vector2) -> Vector2:
	var w := basis * Vector3(local.x, -local.y, 0.0)
	return Vector2(w.x, -w.y)


func _stepped(a: float) -> float:
	if turn_steps <= 0:
		return a
	var step := TAU / turn_steps
	return roundf(a / step) * step


## A square viewport big enough for the board at any turn, with a texel to spare for
## the outline; an even number of texels so the model's origin is on a texel corner.
func _fit_viewport(size_scale: Vector2) -> void:
	var reach := Vector3(HALF_LENGTH, 14.0, board_size.z * 0.5).length() * maxf(size_scale.x, size_scale.y)
	var texels := int(ceil(reach * 2.0 / pixel)) + 4
	texels += texels % 2
	if _viewport.size.x != texels:
		_viewport.size = Vector2i(texels, texels)
	_camera.size = texels * pixel  # `pixel` can change after the first fit.
	_sprite.scale = Vector2(pixel, pixel)


func _shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader


func _update_materials() -> void:
	if _deck_materials.is_empty():
		return
	var colors := [Color.WHITE, Color.WHITE, deck_color, truck_color]
	var textures: Array = [grip if grip else _make_grip(), deck_graphic if deck_graphic else _make_graphic(), null, null]
	for i in _deck_materials.size():
		var mat := _deck_materials[i]
		mat.set_shader_parameter("albedo", colors[i])
		mat.set_shader_parameter("use_tex", textures[i] != null)
		if textures[i]:
			mat.set_shader_parameter("tex", textures[i])
	_wheel_material.set_shader_parameter("albedo", wheel_color)
	_wheel_material.set_shader_parameter("accent", wheel_core_color)


# --- The model, in board space (px at the default size, y up in 3D) ---------------

## Surfaces: 0 grip (top), 1 graphic (bottom), 2 deck edge, 3 trucks. The wheels are
## their own meshes (_build_wheel()), to turn.
func _build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var tools: Array[SurfaceTool] = []
	for i in 4:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	_add_deck(tools[0], tools[1], tools[2])
	for x in [-Runner.WHEEL_X, Runner.WHEEL_X]:
		# Baseplate, hanger and axle (the wheels go on its ends).
		_add_box(tools[3], Vector3(x, 0.0, 0.0), Vector3(12.0, 2.0, 8.0))
		_add_box(tools[3], Vector3(x, -3.5, 0.0), Vector3(6.0, 5.0, 14.0))
		_add_box(tools[3], Vector3(x, -Runner.WHEEL_Y, 0.0), Vector3(2.0, 2.0, 20.0))
	_deck_materials.clear()
	for st in tools:
		st.commit(mesh)
		var mat := ShaderMaterial.new()
		mat.shader = _shader(TOON)
		_deck_materials.append(mat)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


## The deck: a plank with kicked ends, rounded in plan view; matches the flat board's
## outline seen from the side (top y = 7 px over the middle, bottom 1, kicks to 13).
func _add_deck(top: SurfaceTool, bottom: SurfaceTool, edge: SurfaceTool) -> void:
	var nx := 40
	var nz := 6
	var half_w := board_size.z * 0.5
	var rows: Array = []  # [x][j] -> [top point, bottom point, uv]
	for i in nx + 1:
		var x := lerpf(-HALF_LENGTH, HALF_LENGTH, float(i) / nx)
		var kick := clampf((absf(x) - KICK_START) / (HALF_LENGTH - KICK_START), 0.0, 1.0)
		kick = pow(kick, 1.3)
		var y_top := 7.0 + 6.0 * kick
		var y_bottom := 1.0 + 7.0 * kick
		var end := clampf((absf(x) - ROUND_START) / (HALF_LENGTH - ROUND_START), 0.0, 1.0)
		var w := half_w * sqrt(maxf(1.0 - end * end, 0.0))
		var row := []
		for j in nz + 1:
			var z := lerpf(-w, w, float(j) / nz)
			var uv := Vector2((x + HALF_LENGTH) / (2.0 * HALF_LENGTH), (z / half_w + 1.0) * 0.5)
			row.append([Vector3(x, y_top, z), Vector3(x, y_bottom, z), uv])
		rows.append(row)
	for i in nx:
		for j in nz:
			var a: Array = rows[i][j]
			var b: Array = rows[i + 1][j]
			var c: Array = rows[i + 1][j + 1]
			var d: Array = rows[i][j + 1]
			_add_quad(top, [a[0], b[0], c[0], d[0]], [a[2], b[2], c[2], d[2]], Vector3.UP)
			# Underneath, the graphic reads nose to tail the same way up as on top.
			_add_quad(bottom, [a[1], b[1], c[1], d[1]], [a[2], b[2], c[2], d[2]], Vector3.DOWN)
		for j in [0, nz]:
			var a: Array = rows[i][j]
			var b: Array = rows[i + 1][j]
			var out := Vector3((a[0].x + b[0].x) * 0.02, 0.0, signf(float(j) - 0.5))
			_add_quad(edge, [a[0], b[0], b[1], a[1]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], out)


func _add_quad(st: SurfaceTool, p: Array, uv: Array, outward: Vector3) -> void:
	_add_tri(st, [p[0], p[1], p[2]], [uv[0], uv[1], uv[2]], outward)
	_add_tri(st, [p[0], p[2], p[3]], [uv[0], uv[2], uv[3]], outward)


## A flat-shaded triangle, its normal turned to face `outward` (winding doesn't matter:
## the shader draws both sides).
## `mask`: the vertex color, read by the shader as a mask (see TOON).
func _add_tri(st: SurfaceTool, p: Array, uv: Array, outward: Vector3, mask := Color.BLACK) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if n.length_squared() < 0.000001:
		return
	n = n.normalized()
	if n.dot(outward) < 0.0:
		n = -n
	for k in 3:
		st.set_normal(n)
		st.set_color(mask)
		st.set_uv(uv[k])
		st.add_vertex(p[k])


func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var none := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for axis in 3:
		for side in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = side
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var c := center + n * h
			var du := u * h
			var dv := v * h
			_add_quad(st, [c - du - dv, c + du - dv, c + du + dv, c - du + dv], none, n)


## A wheel, centered on its axle: a cylinder across the board (along z). Its sides
## show the core in the middle, crossed by a darker bar (two opposite sectors, through
## the core) that turns as it rolls.
func _build_wheel(radius: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 12
	var core := radius * 0.5
	var none := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var marked := i % (sides / 2) == 0
		var mark := Color(0.0, 1.0, 0.0) if marked else Color.BLACK
		var core_mask := Color(1.0, 1.0 if marked else 0.0, 0.0)
		for side in [-1.0, 1.0]:
			var face := Vector3(0.0, 0.0, width * 0.5 * side)
			var out := Vector3(0.0, 0.0, side)
			_add_tri(st, [face, face + d0 * core, face + d1 * core], none.slice(0, 3), out, core_mask)
			_add_quad_masked(st, [face + d0 * core, face + d1 * core, face + d1 * radius, face + d0 * radius], out, mark)
		_add_quad_masked(st, [d0 * radius - Vector3(0, 0, width * 0.5), d1 * radius - Vector3(0, 0, width * 0.5),
				d1 * radius + Vector3(0, 0, width * 0.5), d0 * radius + Vector3(0, 0, width * 0.5)], (d0 + d1).normalized(), mark)
	var mesh := st.commit()
	_wheel_material = ShaderMaterial.new()
	_wheel_material.shader = _shader(TOON)
	mesh.surface_set_material(0, _wheel_material)
	return mesh


func _add_quad_masked(st: SurfaceTool, p: Array, outward: Vector3, mask: Color) -> void:
	var none := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	_add_tri(st, [p[0], p[1], p[2]], none, outward, mask)
	_add_tri(st, [p[0], p[2], p[3]], none, outward, mask)


# --- Placeholder textures (until boards come from the inventory) --------------------

## Grip tape: `grip_color` with a lighter speckle.
func _make_grip() -> Texture2D:
	var image := Image.create(32, 8, false, Image.FORMAT_RGBA8)
	image.fill(grip_color)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		image.set_pixel(rng.randi_range(0, 31), rng.randi_range(0, 7), grip_color.lightened(0.15))
	return ImageTexture.create_from_image(image)


## The deck graphic: the deck color with a dark band at each truck and a white
## chevron in the middle, so a flip clearly shows the underside.
func _make_graphic() -> Texture2D:
	var w := 32
	var h := 8
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(deck_color)
	var band := deck_color.darkened(0.45)
	for y in h:
		for x in [7, 8, 23, 24]:
			image.set_pixel(x, y, band)
		var cx := 13 + absi(y * 2 - (h - 1)) / 2
		for x in range(cx, cx + 3):
			image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
