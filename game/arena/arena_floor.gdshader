// arena_floor.gdshader
// Renders a randomly-cropped, blurred section of the floor source image.
//
// At runtime Arena.gd picks a random crop_offset so each run shows a different
// patch of the texture. The crop covers 8% of the total image area (a square
// window whose side length is sqrt(0.08) ≈ 0.283 of the full texture).
//
// blur_step controls the blur kernel tap spacing in full-texture UV units.
// For the expected ~1080px source image, the default 0.008 gives a ~9px radius
// per tap. Halve it for a 512px image; double it for a 2048px image.

shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D floor_texture : source_color, filter_linear_mipmap, repeat_disable;

// Set by Arena.gd at scene load — not changed after that.
uniform vec2  crop_offset = vec2(0.2, 0.2);  // top-left corner of the crop window (UV space)
uniform float crop_size   = 0.283;            // side length of the crop window (UV space)

// Increase for more blur, decrease for sharper. Applied in full-texture UV space.
uniform float blur_step = 0.008;

void fragment() {
	// Remap the mesh UV (0..1) to the selected crop region of the full texture.
	vec2 uv = crop_offset + UV * crop_size;

	// 5×5 box blur — 25 equally-weighted samples.
	// The larger kernel smooths fine detail (ant trails, small pebbles) so the
	// floor reads clearly as background and doesn't compete with game objects.
	vec4 color = vec4(0.0);
	for (int xi = -2; xi <= 2; xi++) {
		for (int yi = -2; yi <= 2; yi++) {
			color += texture(floor_texture, uv + vec2(float(xi), float(yi)) * blur_step);
		}
	}
	ALBEDO = (color / 25.0).rgb;
}
