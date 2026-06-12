// 2D cousin of abyss_backdrop.gdshader for menu backgrounds: the same
// domain-warped FBM nebula, sampled in UV space (no world coords in a menu).
// Vignette/grain live in the dread_overlay ColorRect drawn on top.
shader_type canvas_item;

uniform float noise_scale = 4.0;        // nebula feature density across the rect
uniform float drift_speed = 0.015;
uniform float pan_speed = 0.012;        // whole field crawls right-to-left, barely
uniform float warp_strength = 1.6;
uniform float brightness = 1.0;
uniform vec3 base_color : source_color = vec3(0.012, 0.010, 0.018);
uniform vec3 accent_a : source_color = vec3(0.10, 0.05, 0.17);
uniform vec3 accent_b : source_color = vec3(0.03, 0.10, 0.11);

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
	vec2 p = UV * vec2(noise_scale * 1.78, noise_scale);   // ~16:9 aspect correction
	p.x += TIME * pan_speed;   // sample window slides right -> nebula drifts left
	float t = TIME * drift_speed;
	vec2 q = vec2(fbm(p + vec2(t, -t * 0.7)),
			fbm(p + vec2(5.2, 1.3) - vec2(t * 0.6, t)));
	float n = fbm(p + warp_strength * q);
	float n2 = fbm(p * 1.7 - warp_strength * q.yx + vec2(t * 0.5, 0.0));
	vec3 col = base_color;
	col += accent_a * smoothstep(0.45, 0.85, n) * 0.9;
	col += accent_b * smoothstep(0.50, 0.90, n2) * 0.7;
	COLOR = vec4(col * brightness, 1.0);
}
