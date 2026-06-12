// Slow-billowing smoke halo drawn behind the focused button (see
// focus_smoke.gd). Self-masking: alpha fades to zero at the rect edges, so it
// reads as haze leaking out from behind the button, not a box.
shader_type canvas_item;

uniform vec3 smoke_color : source_color = vec3(0.45, 0.12, 0.14);
uniform float intensity : hint_range(0.0, 1.0) = 0.8;
uniform float scale = 3.0;
uniform float speed = 0.12;
uniform float edge_soft = 0.22;     // fraction of the rect used for the fade

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * vec2(scale * 3.0, scale);
	float t = TIME * speed;
	// Two passes of drifting noise: billows that curl upward and sideways.
	float n = fbm(p + vec2(-t * 1.5, -t));
	n = fbm(p + n * 1.4 + vec2(0.0, -t * 0.7));
	vec2 e = smoothstep(vec2(0.0), vec2(edge_soft), UV)
			* smoothstep(vec2(0.0), vec2(edge_soft), 1.0 - UV);
	float mask = e.x * e.y;
	COLOR = vec4(smoke_color * (0.5 + n * 0.8), n * n * mask * intensity);
}
