shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform float opacity        : hint_range(0.0, 1.0) = 0.60;
uniform vec3  shadow_color                           = vec3(0.0);

// UV-space half-extent of the footprint boundary rectangle, measured from
// the quad centre.  Set from GDScript as (outline_world_size / plane_world_size) / 2.0.
// The gap between boundary_half and 0.5 (the quad edge) is the halo area.
uniform float boundary_half  : hint_range(0.0, 0.5) = 0.271;

void fragment() {
	// Remap UV to -0.5..+0.5 so the quad centre is the origin.
	vec2 uv = UV - vec2(0.5);

	// Axis-aligned rectangle SDF.
	//   sdf < 0  →  inside the boundary (transparent centre region)
	//   sdf = 0  →  exactly on the boundary line
	//   sdf > 0  →  outside — this is the halo area
	vec2  q   = abs(uv) - vec2(boundary_half);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);

	// Normalise the halo distance so the gradient always fills the full shadow area,
	// regardless of plane size.  halo_width is the UV distance from the boundary to
	// the quad edge at the cardinal midpoints.  t = 0 at the boundary, 1 at the edge.
	float halo_width  = 0.5 - boundary_half;
	float t           = sdf / max(halo_width, 0.001);

	// smoothstep gives a soft S-curve fade from full opacity at the boundary to zero
	// at the outer edge.  step(0, sdf) zeros out everything inside the boundary.
	float outer_alpha = (1.0 - smoothstep(0.0, 1.0, t)) * opacity;
	ALBEDO = shadow_color;
	ALPHA  = outer_alpha * step(0.0, sdf);
}
