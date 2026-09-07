// Shared direction-dependent water color keeps the terrain horizon seamless.
global uniform float ocean_light_gain;
global uniform vec3 ocean_upper_color;
vec3 ocean_radiance(vec3 direction){
 vec3 d=normalize(direction);
 float up=smoothstep(-0.65,1.0,d.y);
 vec3 water=mix(vec3(0.004,0.012,0.018),ocean_upper_color,pow(up,1.6));
 vec3 sun_direction=normalize(vec3(-0.25,0.95,-0.15));
 float sun=max(dot(d,sun_direction),0.0);
 // A soft overhead sun remains a visible orientation cue through the water.
 // Its warm core and broad cool halo share the same depth attenuation as fog.
 water+=vec3(0.035,0.065,0.08)*pow(sun,12.0);
 water+=vec3(0.65,0.48,0.28)*pow(sun,180.0);
 return water*ocean_light_gain;
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
 return vec4(ocean_radiance(direction),1.0-exp(-max(distance_m,0.0)*density));
}
