shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 pigment : source_color=vec4(0.1,0.7,1.0,1.0);
uniform int part=0;
uniform int family=0;
uniform float phase=0.0;
uniform float opacity=1.0;
uniform float rear_limit=1000.0;
uniform vec3 flight_origin=vec3(0.0);
uniform vec3 flight_rear=vec3(0.0,0.0,1.0);
varying vec3 p;
varying vec3 world_position;
float sq(float x){return x*x;}
float hash(vec3 x){return fract(sin(dot(x,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 x){vec3 i=floor(x);vec3 f=fract(x);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){
 p=VERTEX;
 if(part==5){float ripple=sin(VERTEX.x*5.1+phase*5.0)*sin(VERTEX.y*4.7-phase*3.1)*sin(VERTEX.z*4.3+phase*2.0);VERTEX*=1.0+.085*ripple;}
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 if(rear_limit<999.0 && dot(world_position-flight_origin,flight_rear)>rear_limit)discard;
 vec3 tint=pigment.rgb/max(max(pigment.r,pigment.g),max(pigment.b,.001));
 tint=pow(tint,vec3(1.8));
 float facing=abs(dot(normalize(NORMAL),normalize(VIEW)));
 vec3 warm=mix(tint,vec3(.76,.88,.94),.08);
 float rim=pow(1.0-facing,2.0);
 float grain=noise(p*2.6+vec3(0,0,phase*-5.0));
 float veins=pow(.5+.5*sin(p.z*8.0+grain*9.0-phase*12.0),5.0);
 ALBEDO=mix(tint*.12,warm,.45+facing*.40);ALPHA=.98;
 if(part==0){ALBEDO=mix(tint*.18,warm,.35+.45*facing+.20*veins);}
 if(part==1){
  float band=smoothstep(.03,.07,abs(fract(p.z*1.9)-.5));
  vec3 steel=mix(vec3(.035,.075,.10),vec3(.36,.48,.52),.24+.62*facing);
  float glint=pow(facing,24.0)*.18;
  ALBEDO=steel*(.4+.3*band)+glint*.4;
 }
 if(part==2){ALBEDO=mix(tint*.12,warm,.4+.5*facing);ALPHA=.92;}
 if(part==4){
  float angle=atan(p.y+.00001,p.x+.00001);
  float ribbons=pow(.5+.5*sin(angle*(family==1?3.0:2.0)+p.z*2.3-phase*8.0+grain*2.0),10.0);
  float fade=1.0-smoothstep(1.0,9.0,p.z);
  ALBEDO=mix(tint*.12,warm,ribbons*.75+.15);
  ALPHA=(.10+ .58*ribbons)*fade*(.3+.7*rim);
 }
 if(part==5){
  float turbulent=noise(p*2.2+vec3(phase*.7,-phase*.4,phase*.5));
  float wave=.5+.5*sin(turbulent*13.0+p.z*4.0-phase*3.0);
  float aa=max(fwidth(wave),.03);
  float filament=smoothstep(.62-aa,.92+aa,wave);
  ALBEDO=mix(tint*.055,warm,filament*.8+rim*.12);
  ALPHA=.72+rim*.22;
 }
 ALPHA*=opacity;
}
