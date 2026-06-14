// A soft black bar drawn behind the big centre text (level intro title/tagline and
// the win/lose verdict). Solid in the middle, alpha fading to zero at the left/
// right ends and the top/bottom — a "black line stretched across the screen with
// blurred edges" so the verdict reads against the board without a hard box. Same
// smoothstep edge-mask idiom as button_smoke.gdshader. The node's modulate alpha
// (tweened by _fade_in/_fade_out) fades the whole bar in and out.
shader_type canvas_item;

uniform vec4 bar_color : source_color = vec4(0.0, 0.0, 0.0, 0.8);
uniform float soft_x : hint_range(0.0, 0.5) = 0.32;   // fraction faded at each horizontal end
uniform float soft_y : hint_range(0.0, 0.5) = 0.45;   // fraction faded at top/bottom

void fragment() {
	float ex = smoothstep(0.0, soft_x, UV.x) * smoothstep(0.0, soft_x, 1.0 - UV.x);
	float ey = smoothstep(0.0, soft_y, UV.y) * smoothstep(0.0, soft_y, 1.0 - UV.y);
	COLOR = vec4(bar_color.rgb, bar_color.a * ex * ey);
}
