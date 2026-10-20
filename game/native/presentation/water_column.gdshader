shader_type spatial;
// The water between the camera and what it sees, from the Deeper project's
// water column (Apache-2.0, same author): drifting banks of suspended matter
// integrated along each pixel's ray up to the scene, so ships, stations and
// creatures stand in a volume of water rather than behind a flat haze. One
// full-screen quad, drawn before the transparent effects, enhanced graphics
// with volumetric light only (abyss.gd).
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
#include "res://native/presentation/ocean_background.gdshaderinc"
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D density_texture : repeat_enable, filter_linear;
uniform float visual_time;
uniform float density_gain = .0015;
uniform vec3 water_color = vec3(.24,.40,.37);
uniform float depth_fade = 1.;
// The open world's anchor reduced to the density's repeat on the CPU, so the
// banks stay put when the world origin moves.
uniform vec3 phase;
const float REACH = 1100.;
const vec3 SCALE = vec3(.0017,.0045,.0017);
void vertex(){POSITION=vec4(VERTEX.xy,1.,1.);}
void fragment(){
 float depth=texture(scene_depth,SCREEN_UV).r;
 vec4 view=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.-1.,depth,1.);
 vec3 endpoint=view.xyz/view.w;
 vec3 ray=normalize((INV_VIEW_MATRIX*vec4(normalize(endpoint),0.)).xyz);
 float reach=min(length(endpoint),REACH);
 float segment=reach/20.;
 float optical=0.;
 // A small fixed sub-step offset hides slice bands without temporal noise.
 float jitter=fract(52.9829189*fract(dot(FRAGCOORD.xy,vec2(.06711056,.00583715))));
 vec3 current=vec3(visual_time*.00019,0.,visual_time*.00007);
 for(int i=0;i<20;i++){
  vec3 at=CAMERA_POSITION_WORLD+ray*(float(i)+.25+jitter*.5)*segment;
  vec3 p=(at+phase)*SCALE+current;
  float wide=textureLod(density_texture,p,0.).r;
  // A whole multiple of the repeat, so the phase carries over unchanged.
  float thread=textureLod(density_texture,p*3.+vec3(.2,.6,.1),0.).r;
  float bank=pow(smoothstep(.28,.73,wide*.72+thread*.28),1.8);
  optical+=bank*density_gain*segment;
 }
 vec3 background=ocean_radiance(ray);
 float overhead=pow(max(dot(ray,normalize(vec3(-.25,.95,-.15))),0.),3.);
 ALBEDO=background*.78+water_color*(.018+overhead*.032)*depth_fade;
 ALPHA=1.-exp(-optical);
}
