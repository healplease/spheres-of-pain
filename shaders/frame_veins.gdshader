// Obsidian frame bars: dark vitreous stone threaded with thin ember veins that
// drift and breathe. Noise is sampled in world space so the pattern runs
// continuously around corners and never stretches with bar dimensions. Peak
// emission sits just above the bloom threshold, so the brightest moments of a
// vein catch a faint glow — the frame reads as barely containing something.
shader_type spatial;
render_mode shadows_disabled;

uniform vec3 base_color: source_color = vec3(0.10, 0.09, 0.13);
uniform vec3 vein_color: source_color = vec3(1.0, 0.45, 0.18);
uniform float vein_scale = 1.3;     // vein density (per metre, roughly)
uniform float drift_speed = 0.04;   // how fast the veins crawl
uniform float vein_glow = 1.15;     // peak emission energy

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x),
			mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fold the depth axis into the sample plane so every face of the box gets an
	// unstretched slice of the field.
	vec2 p = vec2(world_pos.x + world_pos.z * 0.7, world_pos.y - world_pos.z * 0.4) * vein_scale;
	float n = fbm(p + TIME * drift_speed);
	// Ridged noise: the crease where the field folds back on itself reads as a vein.
	float ridge = 1.0 - abs(2.0 * fbm(p * 1.7 - TIME * drift_speed) - 1.0);
	float vein = smoothstep(0.88, 0.985, ridge);
	// Each stretch of vein breathes on its own phase (offset by the local noise).
	float pulse = 0.55 + 0.45 * sin(TIME * 0.7 + n * 12.0);
	ALBEDO = base_color * (0.75 + 0.5 * n);
	METALLIC = 0.25;
	ROUGHNESS = 0.45 + 0.25 * n;
	EMISSION = vein_color * vein * vein_glow * pulse;
}
