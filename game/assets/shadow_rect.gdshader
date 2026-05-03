shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

void fragment() {
	// Signed-distance function for a rounded rectangle.
	// UV is remapped to -1..+1 so the centre of the quad is the origin.
	vec2 uv = UV * 2.0 - 1.0;

	float corner_r = 0.30;
	vec2  q        = abs(uv) - (1.0 - corner_r);
	float dist     = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_r;

	// Negative dist = inside the rounded rect; positive = outside.
	float alpha = (1.0 - smoothstep(-0.10, 0.25, dist)) * 0.60;

	ALBEDO = vec3(0.0);
	ALPHA  = alpha;
}
