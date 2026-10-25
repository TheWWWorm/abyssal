// Classic water keeps the original clear colour, subtractive lower sky and
// unlit opening. Its continuous profile replaces the phone's coarse rings;
// evaluate it at each pixel so 4K does not magnify a small direction texture.
global uniform float ocean_light_gain;
// Classic: the imported region colour scaled by depth, in sRGB. Enhanced:
// linear water colour overhead, toned to the same region and depth curve.
global uniform vec3 ocean_upper_color;
global uniform float ocean_classic_sky;
global uniform vec3 ocean_water_tint;
const vec3 OCEAN_OPENING=vec3(-0.25,0.95,-0.15);

vec3 ocean_srgb_to_linear(vec3 c){
 return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));
}
float ocean_ramp_segment(float a,float b,float slope_a,float slope_b,float t){
 // Monotone Hermite tangents join the source ring heights without a crease.
 float t2=t*t,t3=t2*t;
 return (2.0*t3-3.0*t2+1.0)*a+(t3-2.0*t2+t)*slope_a+(-2.0*t3+3.0*t2)*b+(t3-t2)*slope_b;
}
vec3 ocean_soft_floor(vec3 value){
 // Keep black below the original subtractive ramp, rounding only the last
 // few byte values where hard clipping made coloured contour boundaries.
 const float width=0.035;
 vec3 lower=max(value-width,vec3(0.0)),upper=max(value+width,vec3(0.0));
 return (upper*upper-lower*lower)/(4.0*width);
}
vec3 ocean_skybox(vec3 d){
 // Original sky ring elevations and ramp rows, with smooth interpolation
 // between them. The upper region hue and dark lower hemisphere remain.
 float e=degrees(asin(clamp(d.y,-1.0,1.0)));
 float row=e<-54.0?ocean_ramp_segment(1.0,9.0,0.0,9.904762,(e+90.0)/36.0):
  e<-18.0?ocean_ramp_segment(9.0,22.0,9.904762,14.733333,(e+54.0)/36.0):
  e<18.0?ocean_ramp_segment(22.0,39.0,14.733333,19.55,(e+18.0)/36.0):
  ocean_ramp_segment(39.0,62.0,19.55,0.0,clamp((e-18.0)/36.0,0.0,1.0));
 vec3 cut=vec3(vec2(clamp(256.0-8.0*(row-31.0),0.0,255.0)),clamp(248.0-8.0*row,0.0,255.0))/255.0;
 vec3 water=ocean_soft_floor(ocean_upper_color-cut);
 // A compact bright core inside a faint wide halo retains the original's
 // white opening without bleaching a broad disc of the regional colour.
 // This smooth falloff is a presentation adaptation, not the source mesh.
 float away=degrees(acos(clamp(dot(d,normalize(OCEAN_OPENING)),-1.0,1.0)));
 float core=exp(-pow(away/4.5,2.0));
 float halo=exp(-pow(away/13.0,2.0));
 float glow=0.85*core+0.13*halo;
 return clamp(1.0-(1.0-water)*(1.0-glow),vec3(0.0),vec3(1.0));
}
vec3 ocean_classic_radiance(vec3 d){
 return ocean_srgb_to_linear(ocean_skybox(d))*ocean_water_tint*ocean_light_gain;
}
