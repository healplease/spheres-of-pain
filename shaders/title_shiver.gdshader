// Occasional tremor for the title label: most of the time perfectly still,
// then once per `interval` window (at a random moment inside it) the glyphs
// shudder for a fraction of a second. Vertex-only — glyph rendering untouched.
shader_type canvas_item;

uniform float interval = 15.0;       // seconds per shiver window (one shiver each)
uniform float shiver_len = 1.5;     // how long a shiver lasts
uniform float amplitude = 2.0;      // pixels
uniform float speed = 70.0;         // tremor frequency

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	float slot = floor(TIME / interval);
	float t_in = TIME - slot * interval;
	float start = hash(slot) * (interval - shiver_len);
	if (t_in > start && t_in < start + shiver_len) {
		float k = (t_in - start) / shiver_len;
		float env = sin(k * 3.14159);   // ease in and out of the tremor
		// VERTEX.x in the phase makes the jitter ripple raggedly across glyphs.
		VERTEX += vec2(sin(TIME * speed + VERTEX.x * 0.05),
				cos(TIME * speed * 1.31 + VERTEX.x * 0.03)) * amplitude * env;
	}
}
