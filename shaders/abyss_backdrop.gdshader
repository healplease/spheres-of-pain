// Abyssal-void backdrop: slow, domain-warped FBM nebula sampled in WORLD XY so
// the feature scale stays consistent with the 1 m spheres at any field size.
// Unshaded, ALBEDO only (never EMISSION) so the backdrop can never trip glow —
// the board must always out-shine it.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, specular_disabled;

uniform float noise_scale = 0.12;       // world units -> noise space (~8 m features)
uniform float drift_speed = 0.015;      // very slow swirl
uniform float pan_speed = 0.004;        // glacial right-to-left crawl of the whole field
uniform float warp_strength = 1.6;
uniform float brightness = 1.0;         // master dial for board readability
uniform vec3 base_color : source_color = vec3(0.012, 0.012, 0.02);
uniform vec3 violet : source_color = vec3(0.10, 0.05, 0.17);
uniform vec3 teal : source_color = vec3(0.03, 0.10, 0.11);

varying vec3 world_pos;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xy * noise_scale;
	p.x += TIME * pan_speed;   // sample window slides right -> nebula drifts left
	float t = TIME * drift_speed;
	// Domain warp: two fbm fields drifting in opposite directions feed a third.
	vec2 q = vec2(fbm(p + vec2(t, -t * 0.7)),
			fbm(p + vec2(5.2, 1.3) - vec2(t * 0.6, t)));
	float n = fbm(p + warp_strength * q);
	float n2 = fbm(p * 1.7 - warp_strength * q.yx + vec2(t * 0.5, 0.0));
	vec3 col = base_color;
	col += violet * smoothstep(0.45, 0.85, n) * 0.9;
	col += teal * smoothstep(0.50, 0.90, n2) * 0.7;
	ALBEDO = col * brightness;
}
