// Fullscreen post-process: vignette + animated film grain + subtle radial
// chromatic bleed. Lives on a ColorRect in a CanvasLayer BELOW the Ui layer,
// so the HUD text stays crisp on top. Desaturation lives in the Environment
// adjustments (one place only), not here.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.38;
uniform float vignette_radius : hint_range(0.3, 1.0) = 0.75;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.035;
uniform float aberration : hint_range(0.0, 0.02) = 0.006;
// Rare glitch bursts (band tearing + extra RGB split + flicker). Off by
// default so gameplay stays clean; the menus opt in with strength 1.
uniform float glitch_strength : hint_range(0.0, 1.0) = 0.0;
uniform float glitch_period = 9.0;   // seconds per burst window
uniform float glitch_len = 0.22;     // burst duration inside the window

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_c = uv - 0.5;
	float d = length(from_c);

	// One burst per window, at a random moment inside it — stare long enough
	// and the screen tears for a blink.
	float slot = floor(TIME / glitch_period);
	float t_in = TIME - slot * glitch_period;
	float start = hash(vec2(slot, 3.7)) * (glitch_period - glitch_len);
	float active = glitch_strength * step(start, t_in) * step(t_in, start + glitch_len);

	// Chromatic bleed: R shifted outward, B inward, growing toward the edges.
	vec2 off = from_c * d * aberration;
	if (active > 0.0) {
		float band = floor(uv.y * 28.0);
		float r1 = hash(vec2(band, slot));
		float r2 = hash(vec2(band + 57.0, slot));
		uv.x += (r1 - 0.5) * 0.08 * step(0.72, r2);   // a few bands tear sideways
		off += vec2(0.006, 0.0);                       // harder RGB split
	}
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;
	if (active > 0.0) {
		col *= 1.0 - 0.12 * hash(vec2(floor(TIME * 90.0), 1.3));   // brightness flicker
	}

	// Animated film grain.
	float g = hash(FRAGCOORD.xy + vec2(fract(TIME) * 311.0, fract(TIME * 0.7) * 173.0)) - 0.5;
	col += g * grain_amount;

	// Vignette: v is 1 at the centre and falls to 0 toward the corners.
	float v = smoothstep(vignette_radius, vignette_radius * 0.45, d);
	col *= mix(1.0 - vignette_strength, 1.0, v);

	COLOR = vec4(col, 1.0);
}
