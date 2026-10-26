shader_type spatial;
// Ordinary transparency keeps the hollow rim intact beside shadowed lights.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
varying float visibility;
varying float boost_wash;
varying float cavitation;
varying float torpedo_wake;
void vertex(){
 visibility=1.0-INSTANCE_CUSTOM.y;
 boost_wash=step(2.5,INSTANCE_CUSTOM.z)*(1.0-step(3.5,INSTANCE_CUSTOM.z));
 cavitation=step(5.5,INSTANCE_CUSTOM.z);
 torpedo_wake=step(4.5,INSTANCE_CUSTOM.z);
 vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
 float pixel=2.0*abs(center.z)/(max(abs(PROJECTION_MATRIX[1][1]),0.001)*VIEWPORT_SIZE.y);
 float diameter=max(INSTANCE_CUSTOM.x,pixel*(INSTANCE_CUSTOM.z>4.5?4.5:8.0));
 POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy*diameter,0.0),1.0);
}
void fragment(){
 vec2 p=UV*2.0-1.0;
 float r=length(p);
 float width=max(0.085,fwidth(r)*0.65);
 float rim_distance=(r-0.76)/width;
 float rim=exp(-rim_distance*rim_distance)*0.085/width;
 float glint=exp(-dot(p-vec2(-0.32,-0.42),p-vec2(-0.32,-0.42))*65.0);
 float mist=pow(max(0.0,1.0-r),2.0);
 ALBEDO=COLOR.rgb*mix(vec3(0.55,0.73,0.8),vec3(0.92,1.0,1.0),clamp(rim+glint,0.0,1.0));
 float foam=exp(-r*r*3.5)*0.65;
 ALPHA=(rim*0.7+glint*0.8+mix(mist*(.09+cavitation*.3),foam,boost_wash))*visibility*COLOR.a*(1.0-smoothstep(0.92,1.0,r));
 if(torpedo_wake>.5){
  // A restrained dark outer rim survives backlighting; the wet interior
  // stays translucent instead of turning the wake into a glowing plume.
  float outer_distance=(r-.78)/max(width,.15);
  float outer=exp(-outer_distance*outer_distance);
  ALBEDO=mix(ALBEDO,vec3(.10,.24,.29),outer*.7);
  ALPHA=max(ALPHA,outer*visibility*.38)*(1.0-smoothstep(.92,1.0,r));
 }
}
