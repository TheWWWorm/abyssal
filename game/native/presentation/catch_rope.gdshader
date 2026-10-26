shader_type canvas_item;
render_mode unshaded;
uniform vec2 canvas_size=vec2(340.0,64.0);
uniform vec2 line_start=vec2(43.0,24.0);
uniform vec2 head=vec2(288.0,24.0);
uniform float head_scale=1.0;
uniform int teeth=1;
uniform float phase=0.0;
uniform vec4 tint : source_color=vec4(.9,.77,.1,1.0);
float segment_distance(vec2 p,vec2 a,vec2 b){
 vec2 ab=b-a;
 float t=clamp(dot(p-a,ab)/max(dot(ab,ab),.0001),0.0,1.0);
 return length(p-a-ab*t);
}
void fragment(){
 vec2 p=UV*canvas_size;
 float distance=segment_distance(p,line_start,head);
 for(int i=0;i<3;i++){
  if(i>=teeth)break;
  vec2 root=head-vec2(float(i)*5.0,0.0)*head_scale;
  distance=min(distance,segment_distance(p,root,root+vec2(-6.0,7.0)*head_scale));
 }
 float swell=pow(.5+.5*sin(phase*6.2831853/1.6),2.0);
 float strength=.42+.58*swell;
 float width=3.2+1.3*swell;
 float falloff=distance/width;
 float halo=exp(-falloff*falloff)*strength*.78;
 float aa=max(fwidth(distance),.35);
 float core=1.0-smoothstep(.75-aa,1.1+aa,distance);
 vec3 lit=mix(tint.rgb,tint.rgb*.65+vec3(.35),core*(.45+.35*strength));
 COLOR=vec4(lit,max(halo,core*(.65+.35*strength)));
}
