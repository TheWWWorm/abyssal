shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
// A distant station's windows and lamps as soft glows (station_glow.gd).
// Each instance sits on the hull: its origin is the window patch or lamp, its
// scale the glow's size in metres, COLOR the light (alpha its strength) and
// INSTANCE_CUSTOM the wall's outward normal, w = 1 for a lamp, which shines
// every way. The glow fades in with distance, keeps a few pixels on screen,
// and dims through the water like the hull it is on: the direct core by the
// full haze, the scattered halo around it by less. It is seen only as much
// as its place on the hull is: the scene's depth is read at its centre and
// around it, so a window behind another module or round the far side of its
// own adds nothing, not even the edge of its glow past the silhouette.
global uniform float ocean_haze_gain;
global uniform float ocean_station_warmth;
uniform float fade_begin=380.0;
uniform float fade_end=1500.0;
uniform float haze=0.0015;
uniform float min_pixels=2.5;
uniform float max_pixels=7.0;
uniform float core_gain=1.6;
uniform float halo_gain=0.3;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
varying vec3 core_light;
varying vec3 halo_light;
varying flat vec3 occlusion;
varying flat vec2 occlusion_reach;
// Whether the scene at a point on screen is no nearer than the depth that
// still counts as the glow's own wall. Depth buffer values are compared
// directly; both renderers store reversed depth, nearer being larger.
float open(vec2 uv, float limit){
 return step(textureLod(depth_texture,uv,0.0).r,limit);
}
// How much of the glow's place on the hull is in sight: its screen position
// and limiting depth (at), and the spacing of the outer taps (reach).
float visibility(vec3 at, vec2 reach){
 float seen=open(at.xy,at.z)*0.4;
 seen+=open(at.xy+vec2(reach.x,0.0),at.z)*0.15;
 seen+=open(at.xy-vec2(reach.x,0.0),at.z)*0.15;
 seen+=open(at.xy+vec2(0.0,reach.y),at.z)*0.15;
 seen+=open(at.xy-vec2(0.0,reach.y),at.z)*0.15;
 return seen;
}
void vertex(){
 vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
 float distance=max(length(center),0.001);
 float facing=1.0;
 if(INSTANCE_CUSTOM.w<0.5){
  vec3 normal=normalize(mat3(VIEW_MATRIX)*(mat3(MODEL_MATRIX)*INSTANCE_CUSTOM.xyz));
  facing=smoothstep(-0.05,0.35,dot(normal,-center/distance));
 }
 float shown=smoothstep(fade_begin,fade_end,distance)*(1.0-smoothstep(7000.0,9600.0,distance))*facing*COLOR.a;
 vec3 tint=COLOR.rgb;
 // Windows take the warm station lights choice as the hull's windows do.
 if(INSTANCE_CUSTOM.w<0.5){tint*=mix(vec3(1.0),vec3(1.0,0.83,0.56),ocean_station_warmth);}
 float density=haze*ocean_haze_gain;
 core_light=tint*shown*core_gain*exp(-distance*density);
 halo_light=tint*shown*halo_gain*exp(-distance*density*0.5);
 // Metres per pixel at this distance; the glow keeps between min_pixels and
 // max_pixels of radius whatever its size in metres. The renderers flip the
 // projection's Y for their render targets, so its sign is not the lens's.
 float pixel=2.0*distance/(abs(PROJECTION_MATRIX[1][1])*VIEWPORT_SIZE.y);
 // Light scattered on its way spreads the glow wider the more water it crosses.
 float radius=clamp(length(MODEL_MATRIX[0].xyz)*(1.0+distance*density*0.2),min_pixels*pixel,max_pixels*pixel);
 vec4 clip=PROJECTION_MATRIX*vec4(center,1.0);
 // Five taps across the inner glow; a wall within a little of the window's
 // own depth counts as the window's.
 vec4 edge=PROJECTION_MATRIX*vec4(0.0,0.0,center.z+1.5+distance*0.003,1.0);
 float limit=edge.z/edge.w;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 // OpenGL's clip depth runs from -1; its depth buffer from 0.
 limit=limit*0.5+0.5;
 #endif
 occlusion=vec3(clip.xy/max(clip.w,0.0001)*0.5+0.5,limit);
 occlusion_reach=vec2(radius*0.4/pixel)/VIEWPORT_SIZE;
 #if CURRENT_RENDERER != RENDERER_COMPATIBILITY
 // Read here, once a glow, so a hidden one costs no pixels at all. The
 // Compatibility renderer has no depth in the vertex stage; it reads it
 // per pixel instead.
 if(shown>0.0 && clip.w>0.0){
  float seen=visibility(occlusion,occlusion_reach);
  shown*=seen;core_light*=seen;halo_light*=seen;
 }
 #endif
 if(shown<=0.0 || clip.w<=0.0){radius=0.0;}
 POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy*2.0*radius,0.0),1.0);
}
void fragment(){
 vec2 p=UV*2.0-1.0;float r2=dot(p,p);
 float rim=1.0-smoothstep(0.5,1.0,r2);
 vec3 light=core_light*exp(-r2*16.0)+halo_light*exp(-r2*3.5)*rim;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 light*=visibility(occlusion,occlusion_reach);
 #endif
 // As lamp_point.gdshader: additive blending scales by alpha, so the colour
 // is divided by the coverage it is given.
 float cover=clamp(max(light.r,max(light.g,light.b)),0.001,1.0);
 ALBEDO=light/cover;
 ALPHA=cover;
}
