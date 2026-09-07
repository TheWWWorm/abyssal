shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void fragment(){
	ALBEDO=COLOR.rgb;
	EMISSION=COLOR.rgb*2.0;
	ALPHA=COLOR.a;
}
