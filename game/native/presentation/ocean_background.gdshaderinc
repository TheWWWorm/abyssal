// Shared direction-dependent water color keeps the terrain horizon seamless.
// The colour itself is ocean_radiance.gdshaderinc, drawn into a direction map
// by ocean_radiance_map.gd; looking it up costs one texture read per pixel.
global uniform float ocean_haze_gain;
global uniform sampler2D ocean_radiance_map;
#include "res://native/presentation/ocean_direction.gdshaderinc"
vec3 ocean_radiance(vec3 direction){
 return textureLod(ocean_radiance_map,ocean_direction_uv(normalize(direction)),0.0).rgb;
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
// Spatial FOG consumes linear radiance even when the Compatibility sky writes
// sRGB. Feeding sky output into FOG applies gamma twice and lights up distant
// geometry. Absorb surface contrast continuously into the surrounding water.
vec4 ocean_fog(vec3 direction,float distance_m,float density){
 return vec4(ocean_radiance(direction),1.0-exp(-max(distance_m,0.0)*density*ocean_haze_gain));
}
