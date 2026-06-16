shader_type spatial;

// Indestructible SPIN sphere: an obsidian core (like the black bubble, so it reads as
// unbreakable) overlaid with a glowing spiral that rotates over time — a clear visual
// cue that this sphere churns the colours around it. Same self-lit fresnel rim as the
// obsidian bubble so the silhouette stays readable against the dark abyss.

uniform vec3 albedo_color : source_color = vec3(0.03, 0.04, 0.05);
uniform vec3 swirl_color : source_color = vec3(0.18, 0.85, 1.0);  // electric cyan arms
uniform vec3 rim_color : source_color = vec3(0.30, 0.72, 0.88);   // cold cyan rim
uniform float metallic_value : hint_range(0.0, 1.0) = 0.05;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.42;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_energy : hint_range(0.0, 4.0) = 1.4;   // >1.0 so the edge blooms
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;
uniform float swirl_arms : hint_range(1.0, 8.0) = 3.0;   // number of spiral arms
uniform float swirl_twist : hint_range(0.0, 20.0) = 7.0; // how tightly the arms coil
uniform float swirl_speed : hint_range(0.0, 12.0) = 4.0; // rotation speed
uniform float swirl_energy : hint_range(0.0, 4.0) = 1.6; // brightness of the arms

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;  // object-space position; the board plane is XY, normal toward Z
}

void fragment() {
	ALBEDO = albedo_color;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	// Face-on swirl about the board normal: atan gives the polar angle, the radius*twist
	// term curves the arms into a spiral, and -TIME*speed spins the whole thing.
	float ang = atan(v_local.y, v_local.x);
	float rad = length(v_local.xy);
	float spiral = sin(ang * swirl_arms + rad * swirl_twist - TIME * swirl_speed);
	float band = smoothstep(0.55, 1.0, spiral);  // bright arms, dark gaps
	// View-angle fresnel edge, like the obsidian bubble, so the silhouette glows on its own.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = swirl_color * band * swirl_energy + rim_color * fresnel * rim_energy;
}
