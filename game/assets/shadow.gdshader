shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// The enemy's sprite texture. Its alpha defines the shadow silhouette.
// hint_default_transparent makes the shadow invisible if no texture is assigned.
uniform sampler2D sprite_texture : source_color, hint_default_transparent;

void fragment() {
	float tex_alpha = texture(sprite_texture, UV).a;

	// Remap the alpha so the sprite edge transitions gradually rather than
	// cutting off hard. A wide ramp (0.0 to 0.8) produces a soft penumbra
	// around the silhouette even with thin anti-aliased sprite edges.
	float shadow_alpha = smoothstep(0.0, 0.8, tex_alpha) * 0.42;

	ALBEDO = vec3(0.0);
	ALPHA  = shadow_alpha;
}
