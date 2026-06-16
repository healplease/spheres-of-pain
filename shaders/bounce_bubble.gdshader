shader_type spatial;

// Indestructible BOUNCE sphere: a rubbery spring-green ball that rhythmically squashes
// and pulses, so it reads as elastic — the cue that a fired sphere will ricochet off it
// instead of sticking. Keeps the self-lit fresnel rim of the obsidian family so the
// silhouette stays readable against the dark abyss.

uniform vec3 albedo_color : source_color = vec3(0.04, 0.06, 0.04);
uniform vec3 pulse_color : source_color = vec3(0.35, 1.0, 0.45);  // spring green
uniform vec3 rim_color : source_color = vec3(0.45, 0.95, 0.55);
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.30;  // rubbery sheen
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_energy : hint_range(0.0, 4.0) = 1.3;   // >1.0 so the edge blooms
uniform float specular_value : hint_range(0.0, 1.0) = 0.7;
uniform float pulse_rate : hint_range(0.0, 12.0) = 4.5;  // beats per ~second
uniform float ripple_freq : hint_range(0.0, 24.0) = 9.0; // concentric ring density
uniform float pulse_energy : hint_range(0.0, 4.0) = 1.4; // brightness of the pulse

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;  // keep the undistorted local position for the fragment ripple
	// Squash-and-stretch: the ball bulges in-plane and flattens toward the camera in
	// time with the pulse, reading as springy/elastic. Affects only this material.
	float t = 0.5 + 0.5 * sin(TIME * pulse_rate);
	VERTEX.xy *= 1.0 + 0.06 * t;
	VERTEX.z *= 1.0 - 0.05 * t;
}

void fragment() {
	ALBEDO = albedo_color;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	float beat = 0.5 + 0.5 * sin(TIME * pulse_rate);
	// Concentric ripples travelling outward from the centre — a bouncy "ping".
	float rad = length(v_local.xy);
	float ripple = 0.5 + 0.5 * sin(rad * ripple_freq - TIME * pulse_rate * 1.6);
	float glow = mix(0.25, 1.0, beat) * ripple;
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = pulse_color * glow * pulse_energy + rim_color * fresnel * rim_energy * mix(0.7, 1.3, beat);
}
