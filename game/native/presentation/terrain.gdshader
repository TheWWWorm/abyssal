shader_type spatial;
render_mode cull_disabled;
#include "res://native/presentation/ocean_background.gdshaderinc"
varying float slope;
uniform bool sediment_enabled=false;
uniform sampler2D sediment_albedo : source_color,filter_linear_mipmap_anisotropic,repeat_disable;
uniform float sediment_scale=4.0;
uniform vec4 sediment_tint : source_color=vec4(1.0);
float noise(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float smooth_noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(noise(i),noise(i+vec2(1,0)),f.x),mix(noise(i+vec2(0,1)),noise(i+vec2(1,1)),f.x),f.y);}
// Only the unlit swatch is sampled. Mirror seams, then vary scale/orientation
// across broad patches so mineral flecks do not form a visible tile grid.
vec2 swatch(vec2 p){return vec2(.025,.60)+(1.0-abs(fract(p*.5)*2.0-1.0))*vec2(.95,.375);}
void vertex(){slope=1.0-clamp(NORMAL.y,0.0,1.0);}
void fragment(){
 ROUGHNESS=.91;SPECULAR=.28;ALBEDO=vec3(.09,.11,.12);
 if(sediment_enabled){
  vec2 q=UV*sediment_scale;
  vec3 detail=texture(sediment_albedo,swatch(q)).rgb;
  vec3 broad=texture(sediment_albedo,swatch(mat2(vec2(.8,.6),vec2(-.6,.8))*q*.31+vec2(.27,.53))).rgb;
  float patch=smooth_noise(UV*.21);
  ALBEDO=mix(detail,broad,.20)*sediment_tint.rgb*mix(vec3(.88,.94,1.0),vec3(1.18,1.08,.98),patch);
  ROUGHNESS=mix(.92,.75,smoothstep(.08,.46,slope));
  float height=dot(detail,vec3(.333333))*.12;
  vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX),r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);
  float det=dot(dx,r1);
  if(abs(det)>.000001)NORMAL=normalize(abs(det)*NORMAL-sign(det)*(dFdx(height)*r1+dFdy(height)*r2));
 }
 vec3 direction=normalize((INV_VIEW_MATRIX*vec4(VERTEX,0.0)).xyz);
 FOG=ocean_fog(direction,length(VERTEX),.0045);

}
