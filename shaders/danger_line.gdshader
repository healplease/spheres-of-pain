// The bottom miss-exit bar: a slow ember pulse driven by TIME (no _process
// animation needed). Peak emission deliberately exceeds 1.0 so the glow pass
// catches the top of each pulse.
shader_type spatial;
render_mode shadows_disabled;

uniform vec3 base_col : source_color = vec3(0.30, 0.04, 0.05);
uniform vec3 glow_col : source_color = vec3(0.9, 0.08, 0.06);
// Beat phase in radians, integrated on the CPU (LevelController3D) so a changing
// blink rate stays continuous. Driving sin(TIME * rate) instead spikes wildly
// while the rate is tweened, because the large TIME amplifies the rate's change.
uniform float phase = 0.0;
uniform float glow_min = 0.35;
uniform float glow_max = 1.7;

void fragment() {
	float pulse = 0.5 + 0.5 * sin(phase);
	pulse *= pulse;   // bias toward dim, sharper flare
	ALBEDO = base_col;
	ROUGHNESS = 0.7;
	EMISSION = glow_col * mix(glow_min, glow_max, pulse);
}
