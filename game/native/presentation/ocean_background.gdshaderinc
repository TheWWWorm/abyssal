// Shared direction-dependent water color keeps the terrain horizon seamless.
// Enhanced water uses the cached direction map. Classic's small analytic
// profile is evaluated at screen resolution, also for surface fog: enlarging
// the 256-pixel map made its sun and layer boundaries coarse at 4K.
global uniform float ocean_haze_gain;
global uniform sampler2D ocean_radiance_map;
#include "res://native/presentation/ocean_direction.gdshaderinc"
#include "res://native/presentation/ocean_classic.gdshaderinc"
vec3 ocean_radiance(vec3 direction){
 if(ocean_classic_sky>0.5)return ocean_classic_radiance(normalize(direction));
 return textureLod(ocean_radiance_map,ocean_direction_uv(direction),0.0).rgb;
}
vec3 ocean_background(vec3 direction){
 vec3 water=ocean_radiance(direction);
 // Compatibility writes sRGB directly; Forward+ tonemaps linear radiance.
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 water=max(water,vec3(0.0));
 water=mix(water*12.92,1.055*pow(water,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),water));
 #endif
 return water;
}
// The colour an unshaded spatial material writes to show radiance as the
// water around it is shown. Forward+ tonemaps the sky and the material alike.
// Compatibility shows the sky's sRGB as it is written, but takes a
// material's colour as sRGB, decodes it, tonemaps it (ACES at abyss.gd's
// exposure) and encodes it again (measured at 1.15: 0.2 shows as 0.18, 0.4
// as 0.54), so a particle in the water's own colour came out far darker than
// the water. There the curve is inverted per channel.
vec3 ocean_spatial(vec3 radiance){
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 // Godot's ACES fit; its output is divided by that of white (1.0) after
 // the curve's exposure bias of 1.8.
 vec3 t=clamp(radiance,vec3(0.0),vec3(1.2))*0.78108;
 vec3 a=1.0-0.983729*t;vec3 b=0.0245786-0.432951*t;vec3 c=-(0.000090537+0.238081*t);
 vec3 level=(-b+sqrt(b*b-4.0*a*c))/(2.0*a)/(1.8*1.15);
 return mix(level*12.92,1.055*pow(level,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),level));
 #else
 return radiance;
 #endif
}
// Spatial FOG consumes linear radiance even when the Compatibility sky writes
// sRGB. Feeding sky output into FOG applies gamma twice and lights up distant
// geometry. Absorb surface contrast continuously into the surrounding water.
vec4 ocean_fog(vec3 direction,float distance_m,float density){
 return vec4(ocean_radiance(direction),1.0-exp(-max(distance_m,0.0)*density*ocean_haze_gain));
}
