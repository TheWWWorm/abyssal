shader_type spatial;
render_mode unshaded, depth_prepass_alpha, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 pigment : source_color=vec4(1.0,.5,.03,1.0);
uniform int part=6;
uniform bool harpoon=false;
uniform float phase=0.0;
uniform float rear_limit=1000.0;
uniform vec3 flight_origin=vec3(0.0);
uniform vec3 flight_rear=vec3(0.0,0.0,1.0);
varying vec3 p;
varying vec3 world_position;
void vertex(){p=VERTEX;world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if(rear_limit<999.0 && dot(world_position-flight_origin,flight_rear)>rear_limit)discard;
 float facing=abs(dot(normalize(NORMAL),normalize(VIEW)));
 vec3 tint=pigment.rgb/max(max(pigment.r,pigment.g),max(pigment.b,.001));
 ALBEDO=tint*(.23+.52*facing);
 if(part==7){ALBEDO=tint*(.045+.12*facing);}
 if(part==1){
  float band=smoothstep(.03,.07,abs(fract(p.z*1.9)-.5));
  vec3 steel=mix(vec3(.035,.075,.10),vec3(.36,.48,.52),.24+.62*facing);
  ALBEDO=steel*(.4+.3*band)+pow(facing,24.0)*.072;
 }
 if(harpoon){
  float swell=pow(.5+.5*sin(phase*6.2831853/1.6),2.0);
  float strength=.42+.58*swell;
  EMISSION=tint*(.18+1.5*strength)*(part==7?.35:1.0);
 }
 ALPHA=1.0;
 // The depth prepass stops the water beam at the physical projectile.
 // Its colour pass follows the water haze, retaining the small silhouette.
}
