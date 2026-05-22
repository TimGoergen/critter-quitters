// Draws a smooth silver outline around the gear icon silhouette.
// Applied as a ShaderMaterial on the gear TextureRect in HUD.gd.
//
// 16 evenly-spaced samples around a circle avoid the blocky 8-direction
// bias of the original version.  Compositing via col.a (rather than a hard
// threshold) preserves the SVG's existing antialiased edges so the outline
// blends as smoothly as the original black gear did.

shader_type canvas_item;

uniform vec4  outline_color : source_color = vec4(0.68, 0.68, 0.68, 1.0);
uniform float outline_width : hint_range(0.1, 6.0) = 0.7;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	// Accumulate the maximum alpha found among 16 points around the outline ring.
	float a     = 0.0;
	float pi2   = 6.28318530;
	for (int i = 0; i < 16; i++) {
		float angle  = (float(i) / 16.0) * pi2;
		vec2  offset = vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * outline_width;
		a = max(a, texture(TEXTURE, UV + offset).a);
	}

	// Composite the outline behind the original pixel.
	// Multiplying by (1.0 - col.a) means the outline fades where the icon is
	// already opaque — the SVG's antialiased edge pixels blend through naturally.
	float outline_a = a * (1.0 - col.a);
	COLOR.rgb = mix(outline_color.rgb, col.rgb, col.a);
	COLOR.a   = max(col.a, outline_a);
}
