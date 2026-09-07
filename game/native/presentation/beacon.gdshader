shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color=vec4(1.0,0.72,0.4,1.0);
varying float visibility;
void vertex(){
 vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
 float distance=length(center);
 visibility=exp(-distance*0.002)*(1.0-smoothstep(260.0,700.0,distance));
 POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy,0.0),1.0);
}
void fragment(){
 vec2 p=UV*2.0-1.0;float radius=dot(p,p);
 float halo=exp(-radius*7.0);float core=exp(-radius*100.0);
 ALBEDO=mix(tint.rgb,vec3(1.0),core);
 ALPHA=(halo*0.32+core*0.65)*visibility*(1.0-smoothstep(0.65,1.0,radius));
}
