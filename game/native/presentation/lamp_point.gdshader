shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A station or mine lamp as a point of light: the original's crossed
// thirty-two texel sprite is replaced by a billboard the size of that
// sprite, with a white-hot centre that the bloom picks up and a soft halo
// in the lamp's colour, both thinned by the water between it and the eye.
uniform vec4 tint : source_color=vec4(1.0,0.3,0.3,1.0);
uniform float radius=5.0;
uniform float visibility=1.0;
uniform float haze=0.0015;
varying float fade;
void vertex(){
 vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
 float distance=length(center);
 fade=exp(-distance*haze)*visibility;
 // The disc is drawn a little in front of the lamp, towards the eye, so a
 // lamp set on a wall is not cut in half by that wall at a grazing angle.
 float lift=min(radius*0.9,distance*0.5);
 POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy*radius*2.0,lift),1.0);
}
void fragment(){
 vec2 p=UV*2.0-1.0;float r2=dot(p,p);
 float rim=1.0-smoothstep(0.55,1.0,r2);
 float halo=exp(-r2*4.5)*rim;
 float core=exp(-r2*45.0);
 ALBEDO=(tint.rgb*halo*0.55+mix(tint.rgb,vec3(1.0),0.85)*core*1.6)*fade;
 ALPHA=1.0;
}
