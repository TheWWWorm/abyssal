shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 pigment : source_color=vec4(1.0,.5,.03,1.0);
uniform float phase=0.0;
uniform float rear_limit=1000.0;
uniform vec3 flight_origin=vec3(0.0);
uniform vec3 flight_rear=vec3(0.0,0.0,1.0);
varying vec3 world_position;
varying vec3 line_axis;
varying float along;
void vertex(){
 along=VERTEX.y+.5;
 line_axis=normalize((VIEW_MATRIX*MODEL_MATRIX)[1].xyz);
 vec3 center=(MODELVIEW_MATRIX*vec4(0.0,VERTEX.y,0.0,1.0)).xyz;
 float clip_w=abs((PROJECTION_MATRIX*vec4(center,1.0)).w);
 float pixel=2.0*clip_w/(max(abs(PROJECTION_MATRIX[1][1]),.001)*VIEWPORT_SIZE.y);
 float swell=pow(.5+.5*sin(phase*6.2831853/1.6),2.0);
 float radius=max(length(MODEL_MATRIX[0].xyz),.0001);
 VERTEX.xz*=max(2.0,pixel*(2.8+1.2*swell)/radius);
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 if(!FRONT_FACING)discard;
 if(rear_limit<999.0 && dot(world_position-flight_origin,flight_rear)>rear_limit)discard;
 vec3 tint=pigment.rgb/max(max(pigment.r,pigment.g),max(pigment.b,.001));
 vec3 eye=normalize(VIEW);
 vec3 across=eye-line_axis*dot(eye,line_axis);
 if(length(across)>.0001)eye=normalize(across);
 float facing=abs(dot(normalize(NORMAL),eye));
 float swell=pow(.5+.5*sin(phase*6.2831853/1.6),2.0);
 float strength=.42+.58*swell;
 float core=pow(facing,16.0);
 float end_fade=smoothstep(0.0,.16,min(along,1.0-along));
 ALBEDO=tint*.6;
 EMISSION=tint*(.8+1.4*core)*strength;
 ALPHA=end_fade*strength*(.32*pow(facing,3.0)+.30*core);
}
