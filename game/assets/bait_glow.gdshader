// Radial glow used by the Bait Station fire animation.
// The quad is sized to cover the trap footprint.  When the trap pulses,
// opacity is tweened from 0 → 1 → 0 by _play_bait_animation().
// The gradient fades from fully opaque at the centre to fully transparent
// at the quad edge, so the glow bleeds naturally without a hard boundary.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform float opacity : hint_range(0.0, 1.0) = 0.0;
uniform vec3  glow_color = vec3(0.90, 0.06, 0.06);

void fragment() {
	// Shift UV so (0, 0) is the quad centre and ±0.5 are the edges.
	vec2  uv   = UV - vec2(0.5);
	float dist = length(uv) * 2.0;   // 0 at centre; ~0.707 at mid-edge; 1.0+ at corner

	// Hold full brightness across the inner 40% of the radius, then fade to zero.
	float alpha = opacity * (1.0 - smoothstep(0.40, 1.0, dist));

	ALBEDO = glow_color;
	ALPHA  = alpha;
}
