shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// The enemy's sprite texture. Its alpha defines the shadow silhouette shape.
uniform sampler2D sprite_texture : source_color;

// Movement direction as (world_dx, world_dz).  Used to rotate the UV so the
// shadow silhouette stays aligned with the ant's facing direction.
// PlaneMesh UV has V pointing along +Z world by default; rotating by the angle
// from +Z to the movement direction brings V in line with the ant's "up" axis.
uniform vec2 facing_dir = vec2(0.0, 1.0);

void fragment() {
	// atan(y=dx, x=dz) → angle from +Z to movement direction (CCW).
	// Negated because rotating the sample UV by +θ makes the texture appear rotated
	// by −θ, so we must negate to get the texture facing the movement direction.
	float angle = -atan(facing_dir.x, facing_dir.y);
	float ca    = cos(angle);
	float sa    = sin(angle);

	// Rotate UV around the quad centre so the sprite samples match the ant facing.
	vec2 uv  = UV - 0.5;
	vec2 ruv = vec2(ca * uv.x - sa * uv.y, sa * uv.x + ca * uv.y) + 0.5;

	float tex_alpha = texture(sprite_texture, ruv).a;

	// Radial fade centred on the shadow quad. dist = 0 at centre, 1 at the
	// quad edge midpoints. Multiplying by this makes the shadow darkest directly
	// under the entity and fades it to zero at the sprite silhouette boundary.
	float dist      = length(ruv - 0.5) * 2.0;
	float edge_fade = 1.0 - smoothstep(0.0, 1.0, dist);

	float shadow_alpha = smoothstep(0.0, 0.8, tex_alpha) * edge_fade * 0.65;

	ALBEDO = vec3(0.0);
	ALPHA  = shadow_alpha;
}
