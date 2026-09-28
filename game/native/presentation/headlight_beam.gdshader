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
varying vec3 cam_local;
varying mat3 view_to_local;
const int STEPS=16;

// The part of [t_in,t_out] that lies between the lens plane and the end plane.
bool clip_slab(vec3 o, vec3 d, inout float t_in, inout float t_out){
 if(abs(d.z)<1e-6){return o.z<=0.0&&o.z>=-beam_length;}
 float t0=(0.0-o.z)/d.z,t1=(-beam_length-o.z)/d.z;
 t_in=max(t_in,min(t0,t1));t_out=min(t_out,max(t0,t1));
 return t_out>t_in;
}

void vertex(){
 // Work in the camera-relative frame. Subtracting world positions after
 // interpolation loses precision as the vessel travels across the map.
 mat4 inverse_frame=inverse(MODELVIEW_MATRIX);
 cam_local=inverse_frame[3].xyz;
 view_to_local=mat3(inverse_frame);
}

void fragment(){
 // One camera ray per pixel, independent of the cone's raster triangles.
 vec4 near_point=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,1.0,1.0);
 near_point.xyz/=near_point.w;
 bool orthographic=PROJECTION_MATRIX[3][3]>.5;
 vec3 eye=orthographic?vec3(near_point.xy,0.0):vec3(0.0);
 vec3 view_ray=orthographic?vec3(0.0,0.0,-1.0):normalize(near_point.xyz);
 vec3 o=cam_local+view_to_local*eye;
 vec3 d=normalize(view_to_local*view_ray);
 float k2=half_tangent*half_tangent;
 // Inside the double cone x²+y²<k²z²; the slab keeps the nappe behind the lens.
 float a=d.x*d.x+d.y*d.y-k2*d.z*d.z;
 float b=2.0*(o.x*d.x+o.y*d.y-k2*o.z*d.z);
 float c=o.x*o.x+o.y*o.y-k2*o.z*o.z;
 float disc=b*b-4.0*a*c;
 float t_in=length(near_point.xyz-eye),t_out=1e9;
 if(!clip_slab(o,d,t_in,t_out)){discard;}
 if(abs(a)<1e-7){
  // Along the surface direction: one crossing.
  if(abs(b)<1e-7){if(c>0.0){discard;}}
  else{float t=-c/b;if(b>0.0){t_out=min(t_out,t);}else{t_in=max(t_in,t);}}
 }else if(disc<0.0){
  if(a>0.0){discard;}
 }else{
  // Avoid cancellation for rays nearly parallel to the cone wall.
  float q=-.5*(b+(b<0.0?-1.0:1.0)*sqrt(disc));
  float t0=q/a,t1=abs(q)>1e-7?c/q:-b/(2.0*a);
  float lo=min(t0,t1),hi=max(t0,t1);
  if(a>0.0){t_in=max(t_in,lo);t_out=min(t_out,hi);}
  else{
   // The finite, forward-only slab intersects only one nappe. Never let
   // the second root move the start behind a camera already in the beam.
   if(min(t_out,lo)>t_in){t_out=min(t_out,lo);}
   else{t_in=max(t_in,hi);}
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
 t_out=min(t_out,dot(scene.xyz-eye,view_ray));
 if(t_out<=t_in){discard;}
 // Path integral of the light the water scatters towards the camera: the
 // lamp's inverse-square falloff and absorption along the beam, a soft-edged
 // spot profile, and a forward-peaked phase function, so the beam is faint
 // looked at from behind the lamps and bright looked into, as light in
 // water is. Short paths in front of a wall stay faint; the wall itself is
 // lit by the real spotlight. Integrate in atan(depth/4) to put samples
 // where the inverse-square light changes fastest, near the lens. Fixed
 // midpoints avoid the checkerboard from jittering eight long intervals.
 float span=t_out-t_in;
 float angle_in=atan(-(o.z+d.z*t_in)/4.0);
 float angle_out=atan(-(o.z+d.z*t_out)/4.0);
 float light=0.0;
 for(int i=0;i<STEPS;i++){
  float fraction=(float(i)+.5)/float(STEPS);
  float t=t_in+fraction*span;
  float weight=span/float(STEPS);
  if(abs(d.z)>.01){
   float tangent=tan(mix(angle_in,angle_out,fraction));
   t=(-4.0*tangent-o.z)/d.z;
   weight=-4.0*(angle_out-angle_in)*(1.0+tangent*tangent)/(d.z*float(STEPS));
  }
  vec3 p=o+d*t;
  if(clip_enabled&&dot(clip_plane.xyz,(MODEL_MATRIX*vec4(p,1.0)).xyz)+clip_plane.w<0.0)continue;
  float along=-p.z;
  float across=length(p.xy)/max(half_tangent*along,1e-3);
  float radial=pow(clamp(1.0-across*across,0.0,1.0),2.0);
  float falloff=exp(-along/(beam_length*.85))/(along*along+16.0);
  vec2 direction_uv=p.xy/max(half_tangent*along,1e-3)*.5+.5;
  float reach=texture(occlusion,clamp(direction_uv,0.0,1.0)).r;
  float lit=1.0-smoothstep(reach-.6,reach+.6,along);
  light+=radial*falloff*lit*(1.0-smoothstep(beam_length*.8,beam_length,along))*weight;
 }
 light*=26.0;
 // Henyey-Greenstein, g=.15: the scattering angle is between the light
 // travelling down -Z and the path back to the camera, -d.
 float g=.15;
 float phase=(1.0-g*g)/pow(1.0+g*g-2.0*g*d.z,1.5);
 light*=phase;
 // Suspended particles provide movement. Modulating the entire integral
 // from one midpoint creates false sheets when a wall shortens the path.
 // A soft knee, so a look straight down the beam is not white.
 light=light/(1.0+light);
 light*=1.0-smoothstep(fade_begin,fade_begin+fade_length,length(cam_local));
 ALBEDO=tint*energy*light;
 ALPHA=1.0;
}
