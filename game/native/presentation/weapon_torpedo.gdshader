shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
// Preserve the supplied torpedo's skin and solid mesh. Confined highlights
// keep the little hull distinct when it crosses a submarine's light cone.
uniform sampler2D albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 texture_size=vec2(1.0);
uniform mat4 source_bones[64];
varying float transmission;
void vertex(){
	mat4 bone=source_bones[int(UV2.x+.5)];
	VERTEX=(bone*vec4(VERTEX,1.0)).xyz;
	NORMAL=normalize(mat3(bone)*NORMAL);
	UV=(UV+vec2(.5))/max(texture_size,vec2(1.0));
	transmission=exp(-length((MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz)*.0008);
}
void fragment(){
	vec3 skin=texture(albedo,UV).rgb;
	float face=abs(dot(normalize(NORMAL),normalize(VIEW)));
	float edge=smoothstep(.08,.75,face);
	vec3 shaded=skin*(.12+.28*edge);
	ALBEDO=(shaded+vec3(.012,.02,.025))*transmission;
}
