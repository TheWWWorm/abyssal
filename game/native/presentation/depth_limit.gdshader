shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// The depth-limit barrier: a hatched panel that fades in above or below the
// submarine as it nears its shallowest or deepest safe depth. Drawn rather
// than imported: the phone game's panel is a thirty-two texel tile.
uniform vec3 tint: source_color = vec3(1.0, 0.68, 0.28);
uniform float strength = 0.0;
uniform float half_extent = 60.0;
varying vec2 local;
void vertex() { local = VERTEX.xz; }
void fragment() {
	float radius = length(local) / half_extent;
	float edge = 1.0 - smoothstep(0.2, 0.9, radius);
	// Lines thirty centimetres wide, softened by one screen pixel only,
	// so they stay crisp at every distance and angle instead of blurring.
	vec2 cell = abs(fract(local / 12.0) - 0.5) * 12.0;
	float gap = min(cell.x, cell.y);
	float aa = fwidth(gap);
	float line = 1.0 - smoothstep(0.15 - aa, 0.15 + aa, gap);
	float hatch = 0.05 + 0.95 * line;
	// The water takes it back with distance, as it does the headlight beams.
	float haze = exp(-length(VERTEX) * 0.016);
	// Nothing at the edge of its range, brighter the nearer the limit, and at
	// the limit itself twice the level the first sight of it had.
	float presence = pow(strength, 3.0) * (0.25 + 0.75 * strength);
	ALBEDO = tint * hatch * edge * presence * haze * 0.7;
	ALPHA = 1.0;
}
