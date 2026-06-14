// Red "smoke" injury vignette for the danger tiers. Lives on a ColorRect in the
// Dread CanvasLayer (BELOW the Ui layer), so it never covers the HUD. It is
// edge-concentrated — a radial mask that is ~0 in the centre so the play board
// stays clear — and throbs with the heartbeat: `phase` is the shared beat phase
// (radians) the bottom danger line also uses, integrated on the CPU so a changing
// BPM stays continuous. `intensity`, `edge` and `phase` are all driven from
// LevelController3D; at intensity 0 the rect is fully transparent.
shader_type canvas_item;

uniform vec3 danger_color : source_color = vec3(0.62, 0.02, 0.03);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;   // master fade (0 = invisible)
uniform float edge : hint_range(0.2, 0.9) = 0.62;       // vignette onset; lower = reaches further in
uniform float phase = 0.0;                              // beat phase (rad), shared with the danger line
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.45; // how much the beat dips the brightness
uniform float scale = 3.0;
uniform float drift = 0.06;

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
	// Radial vignette mask: 0 in the centre, rising to 1 at the corners. `edge`
	// is where it starts; 0.95 is full strength, so a lower edge reaches inward.
	float d = distance(UV, vec2(0.5));
	float vig = smoothstep(edge, 0.95, d);

	// Drifting smoke so the red reads as haze, not a flat wash.
	float t = TIME * drift;
	float n = fbm(UV * vec2(scale * 1.6, scale) + vec2(-t, -t * 1.3));
	n = fbm(UV * vec2(scale * 1.6, scale) + n * 1.2 + vec2(0.0, -t));
	float smoke = 0.55 + n * 0.7;

	// Heartbeat throb: one sharp thump per beat, biased toward dim.
	float beat = 0.5 + 0.5 * sin(phase);
	beat *= beat;
	float pulse = mix(1.0 - pulse_depth, 1.0, beat);

	float a = vig * smoke * pulse * intensity;
	COLOR = vec4(danger_color, clamp(a, 0.0, 1.0));
}
