shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Analytic projectile shapes, filtered to remain readable during motion.
varying float family;
varying float phase;
void vertex(){
 family=INSTANCE_CUSTOM.z;phase=INSTANCE_CUSTOM.w;
 vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
 vec3 velocity=(VIEW_MATRIX*MODEL_MATRIX*vec4(0.0,0.0,1.0,0.0)).xyz;
 float projected=length(velocity.xy);
 vec2 along=projected>0.001?velocity.xy/projected:vec2(0.0,1.0);
 vec2 across=vec2(-along.y,along.x);
 float pixel_size=2.0*abs(center.z)/(max(abs(PROJECTION_MATRIX[1][1]),.001)*VIEWPORT_SIZE.y);
 vec2 offset=along*VERTEX.x*max(INSTANCE_CUSTOM.x*max(projected,0.14),pixel_size*6.0)+across*VERTEX.y*max(INSTANCE_CUSTOM.y,pixel_size*4.0);
 POSITION=PROJECTION_MATRIX*vec4(center+vec3(offset,0.0),1.0);
}
float hash(float p){return fract(sin(p*127.1)*43758.5453);}
void fragment(){
 vec2 p=UV*2.0-1.0;
 float envelope=smoothstep(-1.0,-.72,p.x)*(1.0-smoothstep(.72,1.0,p.x));
 float thin=mix(.045,.095,step(1.5,family));
 float filtered=max(thin,fwidth(p.y)*.6);
 float core=exp(-pow(p.y/filtered,2.0)*2.0)*envelope*thin/filtered;
 float glow=exp(-pow(p.y/.24,2.0)*2.0)*envelope*.13;
 float nose=exp(-dot((p-vec2(.74,0))*vec2(22,12),(p-vec2(.74,0))*vec2(22,12)));
 float wakes=0.0;
 for(int i=0;i<9;i++){
  float f=float(i);float x=-.88+f*.17;
  float wander=sin(f*17.3+phase*3.0)*.20*(.9-x);
  vec2 q=(p-vec2(x,wander))*vec2(35.0,19.0);
  float radius=length(q);
  wakes+=exp(-pow((radius-.8)*3.0,2.0))*.10*(1.0-(x+1.0)*.5);
 }
 float ion=step(1.5,family)*pow(max(0.0,cos(p.x*29.0-phase*12.0)),18.0)*exp(-pow(p.y/.3,2.0)*2.0)*.28*envelope;
 ALBEDO=COLOR.rgb;
 EMISSION=ALBEDO*.7;
 ALPHA=clamp((core+glow+nose*.55+ion+wakes)*COLOR.a,0.0,1.0);
}
