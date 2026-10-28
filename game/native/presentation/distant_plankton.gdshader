shader_type spatial;
// Motion cues: faint wisps of plankton and suspended matter a few hundred
// metres out, which stay put in the open water while the snow nearby rushes
// past, so distance and speed can be judged where the water is otherwise
// empty. A few dozen soft billboards in one draw, enhanced graphics only
// (abyss.gd). Each takes the colour of the water behind it from the shared
// radiance (ocean_background.gdshaderinc), a little brighter where the
// matter catches the light, and fades into that water with distance, so the
// region's hue and the depth's darkness carry over unchanged. Drawn before
// the water column (render_priority), which hazes them like any distant hull.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://native/presentation/ocean_background.gdshaderinc"
// The camera's place in the open world and the current's drift, each reduced
// to the repeat on the CPU, so the clouds stay anchored as the origin moves.
uniform vec3 eye_phase=vec3(0.0);
uniform vec3 drift=vec3(0.0);
// The node's own place, which the instance origins are measured from.
uniform vec3 cloud_origin=vec3(0.0);
const vec3 PERIOD=vec3(960.0,360.0,960.0);
varying vec3 tint;
varying float fade;
varying flat float seed;
varying flat float aspect;
// A sine hash amplified small differences in the neighbouring noise cells
// into rectangular seams on GPU. Keep the shared corners consistent without
// a large trigonometric multiplier.
float hash(vec2 p){
	vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float noise(vec2 p){
	vec2 cell=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1.0,0.0)),f.x),mix(hash(cell+vec2(0.0,1.0)),hash(cell+vec2(1.0)),f.x),f.y);
}
void vertex(){
	seed=INSTANCE_CUSTOM.x;aspect=INSTANCE_CUSTOM.z;
	// Each cloud keeps its place in a repeating block of water round the
	// camera; it is gone (fade) well before it wraps to the other side.
	vec3 home=MODEL_MATRIX[3].xyz-cloud_origin;
	vec3 offset=mod(home+drift-eye_phase+PERIOD*0.5,PERIOD)-PERIOD*0.5;
	float reach=length(offset);
	fade=smoothstep(110.0,190.0,reach)*(1.0-smoothstep(330.0,450.0,reach))*(1.0-smoothstep(120.0,170.0,abs(offset.y)));
	tint=ocean_spatial(ocean_radiance(offset)*1.35+ocean_radiance(vec3(0.0,1.0,0.0))*0.08);
	vec3 view_center=(VIEW_MATRIX*vec4(CAMERA_POSITION_WORLD+offset,1.0)).xyz;
	// Spread wider than tall, as layers of drifting matter are.
	vec2 size=INSTANCE_CUSTOM.y*vec2(INSTANCE_CUSTOM.z,1.0);
	VERTEX=view_center+vec3(VERTEX.xy*2.0*size,0.0);
	POSITION=PROJECTION_MATRIX*vec4(VERTEX,1.0);
	// A cloud out of reach is moved outside the view, so it costs no pixels.
	if(fade<0.002)POSITION=vec4(2.0,2.0,2.0,1.0);
}
void fragment(){
	vec2 p=(UV-0.5)*2.0;
	float body=noise(p*2.3+vec2(seed*17.0,seed*5.0));
	float envelope=(1.0-smoothstep(0.15,1.0,length(p)+(body-0.5)*0.55))*(1.0-smoothstep(0.6,0.98,length(p)));
	// Specks of larger matter scattered through the cloud, thinning towards
	// its edge, a pixel or two across at this distance. The softening is
	// measured on the continuous grid, so cell borders leave no seams.
	vec2 grid=vec2(p.x*aspect,p.y)*5.0+seed*31.0;
	vec2 cell=floor(grid);
	vec2 at=fract(grid)-0.5-(vec2(hash(cell),hash(cell+7.3))-0.5)*0.7;
	float radius=0.025+0.04*hash(cell+11.7);
	float pixel=max(fwidth(grid.x),fwidth(grid.y));
	float speck=(1.0-smoothstep(radius-pixel*0.5,radius+pixel,length(at)))
		*step(1.0-envelope*0.6,hash(cell+3.1))*(0.4+0.6*hash(cell+5.9));
	// Just enough body to place the grains in the water. Bright, opaque
	// patches read as glowing objects instead of suspended matter.
	ALBEDO=tint;
	ALPHA=envelope*(0.02+speck*0.14)*fade;
}
