shader_type spatial;
render_mode unshaded,blend_add,depth_draw_never,cull_disabled,shadows_disabled;
uniform float opening=0.0;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
float flow_noise(vec2 p){float v=0.0,a=.5;for(int i=0;i<4;i++){v+=a*noise(p);p=mat2(vec2(1.6,1.2),vec2(-1.2,1.6))*p+3.1;a*=.5;}return v;}
void vertex(){
 // Face the camera. The gate frame turns as it opens, so a sheet fixed to the
 // aperture drifted out of it; a billboard cannot be out of alignment at all.
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 vec2 centered=(UV-vec2(0.5))*2.0;
 float radius=length(centered);
 float angle=atan(centered.y,centered.x);
 vec2 p=UV*3.0;
 vec2 drift=vec2(TIME*.10,-TIME*.14);
 vec2 warp=vec2(flow_noise(p+drift),flow_noise(p+vec2(7.3,2.1)-drift));
 float turbulence=flow_noise(p*2.0+warp*3.0-drift);
 // A white core with a soft halo, and the energy threads wound around it.
 float core=exp(-radius*radius*7.0);
 float halo=exp(-radius*radius*2.2);
 float contour=abs(sin(radius*16.0+angle*2.0-turbulence*3.0-TIME*2.8));
 float threads=exp(-contour*contour*22.0)*smoothstep(1.05,.35,radius);
 float intensity=core*(.55+opening*1.10)+halo*.22+threads*.30;
 ALBEDO=mix(vec3(.10,.42,.62),vec3(.90,.99,1.0),clamp(core*1.8+threads,0.0,1.0));
 EMISSION=ALBEDO*(1.1+opening*1.6);
 ALPHA=clamp((.30+opening*.70)*intensity,0.0,1.0)*smoothstep(1.15,.20,radius);
}
