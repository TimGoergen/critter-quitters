shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform float opacity      : hint_range(0.0, 1.0) = 0.35;
uniform vec3  shadow_color                         = vec3(0.0);

void fragment() {
	vec2  uv   = UV - 0.5;
	float dist = length(uv) * 2.0;
	// Solid core fading to transparent at the edge — a classic blob shadow.
	float alpha = (1.0 - smoothstep(0.35, 1.0, dist)) * opacity;
	ALBEDO = shadow_color;
	ALPHA  = alpha;
}
