shader_type spatial;
render_mode unshaded,blend_add,depth_draw_never,cull_disabled,shadows_disabled;
uniform float opening=0.0;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
float flow_noise(vec2 p){float v=0.0,a=.5;for(int i=0;i<4;i++){v+=a*noise(p);p=mat2(vec2(1.6,1.2),vec2(-1.2,1.6))*p+3.1;a*=.5;}return v;}
void fragment(){
 // UV is the triangle's two barycentric coordinates. The third follows
 // from their sum, keeping the energy halo seated inside the modeled frame.
 float edge=min(min(UV.x,UV.y),1.0-UV.x-UV.y);
 float rim=exp(-max(edge,0.0)*65.0);
 vec2 p=UV*3.0;
 vec2 drift=vec2(TIME*.10,-TIME*.14);
 vec2 warp=vec2(flow_noise(p+drift),flow_noise(p+vec2(7.3,2.1)-drift));
 float turbulence=flow_noise(p*2.0+warp*3.0-drift);
 vec2 centered=vec2(UV.x-UV.y,(UV.x+UV.y-.6667)*1.732);
 float radius=length(centered);float angle=atan(centered.y,centered.x);
 float contour=abs(sin(radius*24.0+angle*2.0-turbulence*3.0-TIME*2.8));
 float threads=exp(-contour*contour*25.0);
 float lace=pow(1.0-abs(sin(turbulence*14.0+TIME*.25)),8.0);
 float cloud=smoothstep(.25,.75,turbulence)*.12;
 // The flash sits at the centroid, where the barycentric mapping puts the
 // origin, and grows with the opening: a shut gate is a dim ember, an open one
 // is the white core a submarine goes into.
 float core=exp(-radius*radius*9.0);
 float intensity=rim*.55+threads*.30+lace*.18+cloud*.35+core*(.35+opening*.95);
 ALBEDO=mix(vec3(.10,.42,.62),vec3(.88,.99,1.0),clamp(threads+rim+core*1.4,0.0,1.0));
 EMISSION=ALBEDO*(1.1+opening*1.6);
 ALPHA=clamp((.30+opening*.70)*intensity*(.94+.06*sin(TIME*1.7)),0.0,1.0);
}
