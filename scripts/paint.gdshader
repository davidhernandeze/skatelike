shader_type canvas_item;
// Repaints the cream paint of a plank sprite (UiKit.paint_amount, kept in step) in the
// Control's local space: `top` to `bottom` down it, or left to right when `across`, so a
// pad whose touch position matters shows it as a gradient (flat when both are the same).
// The bare wood, the outline and the screws stay as they are.

uniform vec4 top : source_color = vec4(1.0);
uniform vec4 bottom : source_color = vec4(1.0);
uniform bool across = false;
// The Control's size (px), for the gradient.
uniform vec2 size = vec2(1.0);
// 0..1: lighter (a press flash).
uniform float flash = 0.0;
// 0..1: faded and dirty (not available now).
uniform float faded = 0.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

vec3 hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 h = hsv(c.rgb);
	float amount = clamp((0.34 - h.y) / 0.12, 0.0, 1.0) * clamp((h.z - 0.5) / 0.15, 0.0, 1.0);
	float t = clamp(across ? local.x / size.x : local.y / size.y, 0.0, 1.0);
	vec3 paint = mix(top.rgb, bottom.rgb, t);
	paint = mix(paint, vec3(1.0, 0.95, 0.8), flash * 0.45);
	float shade = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.86;
	vec3 color = mix(c.rgb, paint * shade, amount);
	color = mix(color, mix(vec3(dot(color, vec3(0.33))), vec3(0.42, 0.35, 0.28), 0.5) * 0.75, faded * 0.7);
	COLOR = vec4(color, c.a) * COLOR;
}
