shader_type spatial;
// Ordinary transparency keeps the hollow rim intact beside shadowed lights.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
varying float visibility;
void vertex(){
 visibility=1.0-INSTANCE_CUSTOM.y;
 vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
 float pixel=2.0*abs(center.z)/(max(abs(PROJECTION_MATRIX[1][1]),0.001)*VIEWPORT_SIZE.y);
 float diameter=max(INSTANCE_CUSTOM.x,pixel*8.0);
 POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy*diameter,0.0),1.0);
}
void fragment(){
 vec2 p=UV*2.0-1.0;
 float r=length(p);
 float width=max(0.085,fwidth(r)*0.65);
 float rim=exp(-pow((r-0.76)/width,2.0))*0.085/width;
 float glint=exp(-dot(p-vec2(-0.32,-0.42),p-vec2(-0.32,-0.42))*65.0);
 float mist=pow(max(0.0,1.0-r),2.0);
 ALBEDO=COLOR.rgb*mix(vec3(0.55,0.73,0.8),vec3(0.92,1.0,1.0),clamp(rim+glint,0.0,1.0));
 ALPHA=(rim*0.7+glint*0.8+mist*0.09)*visibility*COLOR.a*(1.0-smoothstep(0.92,1.0,r));
}
