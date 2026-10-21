// The water's colour in every direction: the original's region sky, then
// the enhanced presentation's regional tint, filtered sunlight and shafts.
// ocean_radiance_map.gd evaluates this once per texel of a small direction
// map; the sky, the haze of every surface and the terrain read that map
// instead of evaluating eight shafts per pixel.
global uniform float ocean_light_gain;
// Classic (ocean_classic_sky 1): the phone's clear colour (cy.b and cy.c),
// the prevalent alga's colour scaled by depth, as sRGB bytes over 255.
// Enhanced (0): the linear colour of the open water overhead, the same
// alga's hue toned into the water colour and dimmed by the same depth curve.
global uniform vec3 ocean_upper_color;
global uniform float ocean_classic_sky;
// The Water colour setting: how much of the region's hue the open water
// takes (abyss.gd region_strength; .6 by default).
global uniform float ocean_region_strength;
global uniform vec3 ocean_water_tint;
global uniform float ocean_sun_gain;
global uniform vec3 ocean_sun_color;
global uniform float ocean_shaft_gain;
global uniform float ocean_visual_time;
#include "res://native/presentation/ocean_direction.gdshaderinc"
// The camera's position in the open world (the region anchor added), in
// each noise lattice's cells and already reduced to OCEAN_CELLS on the CPU
// (abyss.gd OCEAN_LATTICES): the water's light columns and banks stay where
// they are in the sea as the ship moves through them, and no lattice is
// handed the millions of metres a float cannot hash.
global uniform vec3 ocean_veil_phase;
global uniform vec3 ocean_veil_fine_phase;
global uniform vec3 ocean_bank_phase;
global uniform vec3 ocean_column_phase;
global uniform vec3 ocean_column_fine_phase;
// The noise repeats after this many cells along each axis, tens of
// kilometres of open water.
const float OCEAN_CELLS=256.;
// Gradient noise with a quintic fade, about 0..1: value noise showed its
// grid as sudden steps where light columns crossed, and gradient noise has
// no such corners.
vec3 ocean_hash33(vec3 p){
 p=fract(p*vec3(.1031,.1030,.0973));p+=dot(p,p.yxz+33.33);
 return fract((p.xxy+p.yxx)*p.zyx)*2.-1.;
}
float ocean_corner(vec3 i,vec3 f,vec3 o){
 return dot(ocean_hash33(mod(i+o,OCEAN_CELLS)),f-o);
}
float ocean_noise3(vec3 p){
 vec3 i=floor(p),f=fract(p);
 vec3 u=f*f*f*(f*(f*6.-15.)+10.);
 float a=ocean_corner(i,f,vec3(0,0,0)),b=ocean_corner(i,f,vec3(1,0,0));
 float c=ocean_corner(i,f,vec3(0,1,0)),e=ocean_corner(i,f,vec3(1,1,0));
 float g=ocean_corner(i,f,vec3(0,0,1)),h=ocean_corner(i,f,vec3(1,0,1));
 float k=ocean_corner(i,f,vec3(0,1,1)),l=ocean_corner(i,f,vec3(1,1,1));
 float n=mix(mix(mix(a,b,u.x),mix(c,e,u.x),u.y),mix(mix(g,h,u.x),mix(k,l,u.x),u.y),u.z);
 return clamp(n*.9+.5,0.,1.);
}
vec3 ocean_srgb_to_linear(vec3 c){
 return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));
}
const vec3 OCEAN_OPENING=vec3(-0.25,0.95,-0.15);
// How much the veil's banks lighten and darken the enhanced water.
const float OCEAN_VEIL=0.45;
vec3 ocean_skybox(vec3 d){
 // The phone clears to the region colour, then draws the skybox mesh round
 // the camera, unlit, from skybox.bmp. Its lower rings subtract the texture's
 // right-hand ramp, its cap adds the left-hand grey ramp. The rings sit at
 // -90, -54, -18, 18 and about 54 degrees of elevation and address rows 1, 9,
 // 22, 39 and 62 of the ramp. A near-white is subtracted from the bottom, so
 // it is black; at the horizon only the colour's blue survives (the yellow
 // there takes red and green away), and the region's own hue shows above it.
 float e=degrees(asin(clamp(d.y,-1.0,1.0)));
 float row=e<-54.0?mix(1.0,9.0,(e+90.0)/36.0):e<-18.0?mix(9.0,22.0,(e+54.0)/36.0):e<18.0?mix(22.0,39.0,(e+18.0)/36.0):mix(39.0,62.0,min((e-18.0)/36.0,1.0));
 vec3 cut=vec3(vec2(clamp(256.0-8.0*(row-31.0),0.0,255.0)),clamp(248.0-8.0*row,0.0,255.0))/255.0;
 // The cap is a cone tilted off the zenith: near white at its apex (row 46),
 // dark at its rim (row 16), about twenty degrees out. It is unlit, so the
 // opening stays visible after the deep water has turned the rest black.
 float away=degrees(acos(clamp(dot(d,normalize(OCEAN_OPENING)),-1.0,1.0)));
 float glow=away<20.0?(8.0+240.0*(1.0-away/20.0))/255.0:0.0;
 return min(max(ocean_upper_color-cut,vec3(0.0))+glow,vec3(1.0));
}
vec3 ocean_layered_water(vec3 d,float sun){
 // The enhanced water, in the Deeper project's three tones: dark below, a
 // middle water at the horizon and the lit water overhead. As on the phone,
 // where a navy horizon lies under the region's colour, the alga's hue
 // gathers overhead; level and below the water keeps its own blue-green at
 // the same brightness, darkening into cool depths.
 float lum=dot(ocean_upper_color,vec3(0.2126,0.7152,0.0722));
 vec3 plain=lum*vec3(0.2957,1.0753,2.2581);
 vec3 upper=ocean_upper_color;
 // The horizon keeps the water's own navy, as the phone's skybox left only
 // the region colour's blue there: more of a warm hue greyed it into mauve.
 vec3 middle=mix(plain,ocean_upper_color,0.2)*vec3(0.30,0.36,0.55);
 vec3 deep=plain*vec3(0.05,0.06,0.1);
 vec3 water=mix(deep,middle,smoothstep(-0.95,0.1,d.y));
 water=mix(water,upper,pow(smoothstep(-0.7,0.9,d.y),2.5));
 // The opening's glow, softer and wider than the phone's cone.
 return water+upper*(0.35*pow(sun,5.0)+0.25*pow(sun,24.0));
}
vec3 ocean_radiance_exact(vec3 direction){
 vec3 d=normalize(direction);
 vec3 sun_direction=normalize(OCEAN_OPENING);
 float sun=max(dot(d,sun_direction),0.0);
 vec3 water;
 if(ocean_classic_sky>0.5)water=ocean_srgb_to_linear(ocean_skybox(d));
 else{
  water=ocean_layered_water(d,sun);
  // Deeper's veil: broad lighter and darker banks hundreds of metres away
  // at independent scales, so the open water has depth instead of one
  // even gradient.
  vec3 drift=vec3(ocean_visual_time*.19,-ocean_visual_time*.025,ocean_visual_time*.09);
  vec3 p=(drift+d*650.)*vec3(.0019,.0009,.0019);
  float veil=smoothstep(.27,.78,ocean_noise3(ocean_veil_phase+p+vec3(3.2,8.5,1.))*.7+ocean_noise3(ocean_veil_fine_phase+p*2.63+vec3(7.8,1.4,6.2))*.3);
  float bank=ocean_noise3(ocean_bank_phase+(drift*.4+d*1500.)*vec3(.0007,.0021,.0007));
  water*=mix(1.,.48+veil*.67+bank*.23,OCEAN_VEIL*(1.-.6*smoothstep(.6,.95,d.y)));
 }
 water*=ocean_water_tint;
 // The brightest opening is above. Its filtered light fades continuously
 // through the water column; the deepest water still belongs to local lamps.
 // Imported pale warm sunlight becomes cooler along a longer water path,
 // and takes on some of the region's hue: a fixed blue-white over a warm
 // region's water greyed it into mauve.
 float hue_lum=max(dot(ocean_upper_color,vec3(0.2126,0.7152,0.0722)),1e-4);
 vec3 filtered_sun=ocean_sun_color*ocean_upper_color/hue_lum*0.5;
 water+=(filtered_sun*0.08*pow(sun,12.0)+ocean_sun_color*0.5*pow(sun,180.0))*ocean_sun_gain;
 // Light columns, from Deeper's water: value noise anchored in the sea about
 // a kilometre out, ten times longer upright than across, so soft
 // uneven columns of filtered light stand in the water and pass by as the
 // ship travels, drifting slowly with the current.
 vec3 current=vec3(ocean_visual_time*.19,-ocean_visual_time*.025,ocean_visual_time*.09);
 vec3 column=(current+d*1050.)*vec3(.0034,.00032,.0034);
 // Broad falloff and no fine octave: the columns' sides fade over many
 // metres instead of ending on a visible line.
 float filaments=smoothstep(.3,.95,ocean_noise3(ocean_column_phase+column)*.8+ocean_noise3(ocean_column_fine_phase+column*vec3(1.9,.5,1.9)+vec3(4.1,2.3,7.7))*.2);
 filaments*=filaments;
 // Seen from below a column is only its cross-section, a blotch; straight
 // up the opening's glow carries the light instead.
 float upright=smoothstep(-.3,.6,d.y)*(1.-smoothstep(.72,.97,d.y));
 water+=(filtered_sun*0.16+ocean_upper_color*0.48)*filaments*upright*ocean_shaft_gain;
 return water*ocean_light_gain;
}
