shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

void fragment() {
	// Remap UV from 0..1 to -1..1 so the origin is the centre of the quad.
	vec2 uv   = UV * 2.0 - 1.0;
	float dist = length(uv);

	// Full opacity at the centre, fading smoothly to transparent at the edge.
	// The 0.25 inner threshold keeps the darkest zone small so the shadow looks
	// soft rather than painted-on.
	float alpha = (1.0 - smoothstep(0.25, 1.0, dist)) * 0.50;

	ALBEDO = vec3(0.0);
	ALPHA  = alpha;
}
