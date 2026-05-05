shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform float opacity        : hint_range(0.0, 1.0) = 0.50;
uniform vec3  shadow_color                           = vec3(0.0);

// Where the footprint boundary sits in UV space, as a half-extent from centre.
// GDScript sets this as (outline_world_size / plane_world_size) / 2.0 so the
// shadow ring aligns exactly with the drawn footprint outline.
uniform float boundary_half  : hint_range(0.0, 0.5) = 0.396;

// UV-space distance over which the shadow fades to zero after the boundary.
// Larger values give a softer, wider halo beyond the outline.
uniform float outer_spread   : hint_range(0.01, 0.5) = 0.10;

void fragment() {
	// Remap UV to -0.5..+0.5 so the quad centre is the origin.
	vec2 uv = UV - vec2(0.5);

	// Axis-aligned rectangle signed distance function.
	//   sdf < 0  →  inside the boundary (the trap centre region)
	//   sdf = 0  →  exactly on the boundary line
	//   sdf > 0  →  outside the boundary
	vec2  q   = abs(uv) - vec2(boundary_half);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);

	// Inside the boundary: fully transparent — no shadow at the trap centre.
	// Outside the boundary: fades from full opacity at the line to zero.
	// step(0.0, sdf) is 1.0 when outside (sdf >= 0) and 0.0 when inside.
	float outer_alpha = (1.0 - smoothstep(0.0, outer_spread, sdf)) * opacity;
	ALBEDO = shadow_color;
	ALPHA  = outer_alpha * step(0.0, sdf);
}
