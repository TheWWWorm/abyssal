shader_type spatial;
// The visible cone of a headlight: the lamp's light picked up by the water
// between the lens and whatever it falls on. The mesh is a closed cone with
// its apex at the lens, drawn back faces only and without a depth test; each
// pixel intersects its own line of sight with the cone exactly, cuts it at
// the first surface the scene depth reports, and integrates the light along
// what is left. The beam keeps its shape from any camera, including from
// inside it, and never shows the slab or the sampling as slices.
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color=vec3(.72,.9,1.0);
uniform float energy=.7;
uniform float beam_length=70.0;
uniform float half_tangent=.249;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// How far the light gets along each direction of the cone (u,v across the
// cone in units of its radius) before a wall: cast from the lens by the scene.
uniform sampler2D occlusion : filter_linear, repeat_disable;
// The gate or hangar plane the hull is clipped by while passing through.
uniform bool clip_enabled=false;
uniform vec4 clip_plane=vec4(0.0);
// Another vessel's beam fades with the camera's distance from its lens, as
// its lamp does; the player's never fades.
uniform float fade_begin=100000.0;
uniform float fade_length=100.0;
varying vec3 pos_local;
varying vec3 cam_local;
const int STEPS=8;

float hash3(vec3 p){p=fract(p*.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z);}
float water_noise(vec3 p){
 vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1)),f.x),f.y),f.z);
}

// The part of [t_in,t_out] that lies between the lens plane and the end plane.
bool clip_slab(vec3 o, vec3 d, inout float t_in, inout float t_out){
 if(abs(d.z)<1e-6){return o.z<=0.0&&o.z>=-beam_length;}
 float t0=(0.0-o.z)/d.z,t1=(-beam_length-o.z)/d.z;
 t_in=max(t_in,min(t0,t1));t_out=min(t_out,max(t0,t1));
 return t_out>t_in;
}

void vertex(){
 pos_local=VERTEX;
 cam_local=(inverse(MODEL_MATRIX)*vec4(CAMERA_POSITION_WORLD,1.0)).xyz;
}

void fragment(){
 vec3 o=cam_local;
 vec3 d=normalize(pos_local-cam_local);
 float k2=half_tangent*half_tangent;
 // Inside the double cone x²+y²<k²z²; the slab keeps the nappe behind the lens.
 float a=d.x*d.x+d.y*d.y-k2*d.z*d.z;
 float b=2.0*(o.x*d.x+o.y*d.y-k2*o.z*d.z);
 float c=o.x*o.x+o.y*o.y-k2*o.z*o.z;
 float disc=b*b-4.0*a*c;
 float t_in=0.0,t_out=1e9;
 if(abs(a)<1e-7){
  // Along the surface direction: one crossing.
  if(abs(b)<1e-7){if(c>0.0){discard;}}
  else{float t=-c/b;if(b>0.0){t_out=min(t_out,t);}else{t_in=max(t_in,t);}}
 }else if(disc<0.0){
  if(a>0.0){discard;}
 }else{
  float root=sqrt(disc);
  float t0=(-b-root)/(2.0*a),t1=(-b+root)/(2.0*a);
  float lo=min(t0,t1),hi=max(t0,t1);
  if(a>0.0){t_in=max(t_in,lo);t_out=min(t_out,hi);}
  else{
   // Inside before the first crossing or after the second: the nearer part.
   float near_in=0.0,near_out=lo,far_in=hi,far_out=1e9;
   if(clip_slab(o,d,near_in,near_out)){t_in=near_in;t_out=near_out;}
   else{t_in=far_in;t_out=far_out;}
  }
 }
 if(!clip_slab(o,d,t_in,t_out)){discard;}
 // Nothing behind the first surface on this pixel is lit water.
 float depth=texture(depth_texture,SCREEN_UV).r;
 vec3 ndc=vec3(SCREEN_UV*2.0-1.0,depth);
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 ndc.z=depth*2.0-1.0;
 #endif
 vec4 scene=INV_PROJECTION_MATRIX*vec4(ndc,1.0);scene.xyz/=scene.w;
 t_out=min(t_out,length(scene.xyz));
 if(t_out<=t_in){discard;}
 // Path integral of the light the water scatters towards the camera: the
 // lamp's inverse-square falloff and absorption along the beam, a soft-edged
 // spot profile, and a forward-peaked phase function, so the beam is faint
 // looked at from behind the lamps and bright looked into, as light in
 // water is. Short paths in front of a wall stay faint; the wall itself is
 // lit by the real spotlight. A per-pixel offset hides the sampling.
 float jitter=fract(52.9829189*fract(dot(FRAGCOORD.xy,vec2(.06711056,.00583715))));
 float span=t_out-t_in;
 float light=0.0;
 for(int i=0;i<STEPS;i++){
  vec3 p=o+d*(t_in+(float(i)+jitter)/float(STEPS)*span);
  if(clip_enabled&&dot(clip_plane.xyz,(MODEL_MATRIX*vec4(p,1.0)).xyz)+clip_plane.w<0.0)continue;
  float along=-p.z;
  float across=length(p.xy)/max(half_tangent*along,1e-3);
  float radial=pow(clamp(1.0-across*across,0.0,1.0),2.0);
  float falloff=exp(-along/(beam_length*.85))/(along*along+16.0);
  vec2 direction_uv=p.xy/max(half_tangent*along,1e-3)*.5+.5;
  float reach=texture(occlusion,clamp(direction_uv,0.0,1.0)).r;
  float lit=1.0-smoothstep(reach-.6,reach+.6,along);
  light+=radial*falloff*lit*(1.0-smoothstep(beam_length*.8,beam_length,along));
 }
 light*=span/float(STEPS)*26.0;
 // Henyey-Greenstein, g=.15: the scattering angle is between the light
 // travelling down -Z and the path back to the camera, -d.
 float g=.15;
 float phase=(1.0-g*g)/pow(1.0+g*g-2.0*g*d.z,1.5);
 light*=phase;
 vec3 middle=(MODEL_MATRIX*vec4(o+d*(t_in+t_out)*.5,1.0)).xyz;
 light*=mix(.85,1.15,water_noise(middle*.35+vec3(TIME*.05,-TIME*.03,TIME*.02)));
 // A soft knee, so a look straight down the beam is not white.
 light=light/(1.0+light);
 light*=1.0-smoothstep(fade_begin,fade_begin+fade_length,length(cam_local));
 ALBEDO=tint*energy*light;
 ALPHA=1.0;
}
