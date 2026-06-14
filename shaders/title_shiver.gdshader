// Occasional dread for big labels: most of the time the text is perfectly
// still, then once per `interval` window (at a random moment inside it) the
// glyphs shudder for a fraction of a second — and on an independent clock the
// colour channels briefly tear apart (chromatic aberration flicker).
// `seed` desyncs labels that share this shader so they never twitch together.
shader_type canvas_item;

uniform float interval = 15.0;      // seconds per shiver window (one shiver each)
uniform float shiver_len = 1.5;     // how long a shiver lasts
uniform float amplitude = 2.0;      // pixels
uniform float speed = 70.0;         // tremor frequency
uniform float ab_interval = 11.0;   // seconds per aberration window (one flicker each)
uniform float ab_len = 0.55;        // how long a flicker lasts
uniform float ab_strength = 2.5;    // peak channel separation, pixels
uniform float seed = 0.0;           // per-label phase offset

// Accessibility kill-switch, driven by the Graphics settings via a RenderingServer
// global param (so one toggle reaches every title in every scene). 1 = on, 0 = off.
// The chromatic-aberration flicker is always on (no toggle).
global uniform float text_glitch;       // the positional shiver (glitched movement)

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// 0 outside the event window, easing 0 -> 1 -> 0 inside it. One event per
// `period`, starting at a random moment within the window.
float window_env(float t, float period, float len, float salt) {
	float slot = floor(t / period);
	float t_in = t - slot * period;
	float start = hash(slot + salt) * (period - len);
	if (t_in < start || t_in > start + len) {
		return 0.0;
	}
	return sin((t_in - start) / len * 3.14159);
}

void vertex() {
	float env = window_env(TIME + seed, interval, shiver_len, seed) * text_glitch;
	if (env > 0.0) {
		// VERTEX.x in the phase makes the jitter ripple raggedly across glyphs.
		VERTEX += vec2(sin(TIME * speed + VERTEX.x * 0.05),
				cos(TIME * speed * 1.31 + VERTEX.x * 0.03)) * amplitude * env;
	}
}

void fragment() {
	float env = window_env(TIME + seed * 1.7, ab_interval, ab_len, seed + 13.0);
	if (env > 0.001) {
		// Stutter inside the flicker so the split feels electrical, not smooth.
		env *= 0.55 + 0.45 * hash(floor(TIME * 24.0) + seed);
		vec2 off = vec2(TEXTURE_PIXEL_SIZE.x * ab_strength * env, 0.0);
		// Font-atlas glyphs are white with coverage in alpha, so COLOR.rgb is the
		// font colour regardless of coverage: rebuild each channel from its own
		// shifted coverage sample to push red left and blue right of the glyph.
		float ga = texture(TEXTURE, UV).a;
		float ra = texture(TEXTURE, UV - off).a;
		float ba = texture(TEXTURE, UV + off).a;
		float a = max(ga, max(ra, ba));
		vec3 rgb = vec3(COLOR.r * ra, COLOR.g * ga, COLOR.b * ba) / max(a, 0.0001);
		// Preserve the label's modulate alpha (fades) where we can estimate it.
		float mod_a = ga > 0.003 ? clamp(COLOR.a / ga, 0.0, 1.0) : 1.0;
		COLOR = vec4(rgb, a * mod_a);
	}
}
