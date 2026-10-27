shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec4 pigment : source_color=vec4(.2,.7,.65,1.0);
uniform int tier=0;
uniform float rear_limit=1000.0;
uniform vec3 flight_origin=vec3(0.0);
uniform vec3 flight_rear=vec3(0.0,0.0,1.0);
varying vec3 p;
varying vec3 local_normal;
varying vec3 eye_direction;
varying vec3 world_position;

float hash(vec3 q){return fract(sin(dot(q,vec3(127.1,311.7,74.7)))*43758.5453);}
float grain(vec3 q){
 vec3 i=floor(q);vec3 f=fract(q);f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float round_box(vec2 q, vec2 half_size, float radius){
 vec2 d=abs(q)-half_size+vec2(radius);
 return length(max(d,vec2(0)))+min(max(d.x,d.y),0.0)-radius;
}
void vertex(){
 p=VERTEX;local_normal=NORMAL;
 eye_direction=(inverse(MODELVIEW_MATRIX)*vec4(0,0,0,1)).xyz-VERTEX;
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 if(rear_limit<999.0 && dot(world_position-flight_origin,flight_rear)>rear_limit)discard;
 float part=round(COLOR.r*8.0);
 vec3 n=normalize(local_normal);vec3 v=normalize(eye_direction);
 float facing=max(dot(n,v),0.0);
 float top=max(dot(n,normalize(vec3(.25,.85,-.35))),0.0);
 float footprint=max(length(dFdx(p)),length(dFdy(p)));
 float fine=1.0-smoothstep(.018,.085,footprint);
 float cloud=grain(p*vec3(4.0,4.0,2.5));
 float wear=grain(p*vec3(35.0,35.0,10.0));
 vec3 paint=mix(vec3(.26,.30,.31),pigment.rgb*.44,.20);
 vec3 surface=paint*(.76+.40*cloud);
 float gloss=.10;float polish=18.0;
 float aa=max(fwidth(p.z),.004);
 float angle=atan(p.y,p.x);
 if(part<.5){
  // A smooth pressure casing with broad material changes and restrained
  // wear. All detail is surface treatment; the hydrodynamic outline stays.
  float nose=1.0-smoothstep(-6.50,-6.45,p.z);
  surface=mix(surface,vec3(.09,.105,.115)*(.72+.48*cloud),nose);
  gloss=mix(gloss,.045,nose);polish=mix(polish,10.0,nose);
  float drive=smoothstep(-1.48,-1.12,p.z);
  surface=mix(surface,vec3(.115,.14,.155)*(.80+.30*cloud),drive);
  gloss=mix(gloss,.18,drive);
  // One faded identification band is wide enough to read in play.
  float band=1.0-smoothstep(.13,.14+aa,abs(p.z+5.93));
  vec3 marking=mix(vec3(.43,.39,.27),pigment.rgb*.52,.45);
  surface=mix(surface,marking*(.83+.25*cloud),band*.72);
  float seam_distance=min(abs(p.z+6.46),min(abs(p.z+5.73),abs(p.z+1.88)));
  float seam=1.0-smoothstep(.007,.015+aa,seam_distance);
  surface*=1.0-seam*.63;
  float lip=(1.0-smoothstep(.003,.008+aa,abs(seam_distance-.025)))*.012/(.012+aa);
  surface+=vec3(.13,.16,.17)*lip;
  // Two flush service covers, one on either side, with a single inset latch.
  vec2 cover_a=vec2(angle*.56,p.z+3.35);
  vec2 cover_b=vec2(atan(p.y,-p.x)*.56,p.z+4.20);
  float cover=min(round_box(cover_a,vec2(.23,.48),.05),round_box(cover_b,vec2(.23,.48),.05));
  // Filter the continuous distance, not the discontinuous angular chart.
  float edge_aa=max(fwidth(cover),.003);
  float inset=1.0-smoothstep(0.0,edge_aa,cover);
  float outline=1.0-smoothstep(.004,.012+edge_aa,abs(cover));
  surface=mix(surface,surface*.78,inset*.6);surface*=1.0-outline*.40;
  float latch=min(round_box(cover_a-vec2(0,.32),vec2(.075,.018),.01),round_box(cover_b-vec2(0,.32),vec2(.075,.018),.01));
  surface=mix(surface,vec3(.10,.12,.125),1.0-smoothstep(0.0,max(fwidth(latch),.003),latch));
  // Filter close wear away before it can sparkle at gameplay distances.
  float scuff=smoothstep(.65,.81,wear)*fine*(seam*.5+outline*.35+.14);
  surface=mix(surface,vec3(.34,.37,.36),scuff*.65);
 }else if(part<2.5){
  surface=vec3(.32,.245,.145)*(.78+.38*cloud);gloss=.23;polish=28.0;
 }else if(part<3.5){
  surface=paint*(.78+.32*cloud);gloss=.10;
 }else{
  surface=vec3(.28,.32,.33)*(.80+.30*cloud);gloss=.22;polish=30.0;
 }
 float brushed=(wear-.5)*.10*fine;
 vec3 half_vector=normalize(v+normalize(vec3(.25,.85,-.35)));
 float highlight=pow(max(dot(n,half_vector),0.0),polish+brushed*20.0)*gloss;
 float rim=pow(1.0-facing,3.0)*.025;
 ALBEDO=surface*(.60+.60*top+.10*facing)+vec3(.72,.83,.88)*highlight+vec3(.45,.62,.70)*rim;
 // Closed opaque geometry writes depth; no transparency or luminous paint.
}
