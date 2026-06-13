shader_type spatial;

// Obsidian sphere with a self-lit fresnel edge. The black bubbles are nearly the
// colour of the abyss behind them, so a light-dependent rim (StandardMaterial3D.rim)
// vanishes in the dark. This drives EMISSION off a view-angle fresnel instead, so the
// silhouette glows on its own regardless of scene lighting — and because rim_energy
// pushes the edge above 1.0 it trips the environment's additive glow and blooms,
// reading clearly against the black background while the face of the sphere stays dark.

uniform vec3 albedo_color : source_color = vec3(0.03, 0.03, 0.04);
uniform vec3 rim_color : source_color = vec3(0.46, 0.5, 0.72); // cold steel-violet
uniform float metallic_value : hint_range(0.0, 1.0) = 0.05;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.42;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;    // higher = tighter edge band
uniform float rim_energy : hint_range(0.0, 4.0) = 1.9;   // >1.0 so the edge blooms
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	ALBEDO = albedo_color;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	// View-angle fresnel: ~0 facing the camera, ~1 at the grazing silhouette.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color * fresnel * rim_energy;
}
