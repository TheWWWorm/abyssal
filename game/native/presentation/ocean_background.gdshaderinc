// Shared direction-dependent water color keeps the terrain horizon seamless.
global uniform float ocean_light_gain;
global uniform vec3 ocean_upper_color;
global uniform float ocean_haze_gain;
global uniform vec3 ocean_water_tint;
global uniform float ocean_sun_gain;
global uniform vec3 ocean_sun_color;
global uniform float ocean_shaft_gain;
global uniform float ocean_visual_time;
float ocean_light_shaft(vec3 direction,vec3 opening,vec3 end,float width){
 // One soft ribbon on the viewing sphere. There is no repeated angular
 // pattern or division by height: looking straight up cannot fold a stripe
 // into a contour. The angular wrap is outside the ribbon's faded ends.
 vec3 normal=normalize(cross(opening,end));
 vec3 tangent=cross(normal,opening);
 float along=atan(dot(direction,tangent),dot(direction,opening));
 float length=acos(clamp(dot(opening,end),-1.0,1.0));
 float spread=mix(width*0.38,width,smoothstep(0.0,length,along));
 float side=dot(direction,normal)/spread;
 float fade=smoothstep(-0.08,0.04,along)*(1.0-smoothstep(length-0.4,length+0.12,along));
 // A fine strand inside a much softer veil, without a hard cone edge.
 return (0.65*exp(-side*side)+0.35*exp(-side*side*0.18))*fade;
}
vec3 ocean_radiance(vec3 direction){
 vec3 d=normalize(direction);
 float up=smoothstep(-0.65,1.0,d.y);
 // Regional colour belongs to the surrounding water, including below the
 // horizon. Applying it only to the upper sky hid it during ordinary dives.
 vec3 water=mix(vec3(0.004,0.012,0.018)*ocean_water_tint,ocean_upper_color,pow(up,1.6));
 vec3 sun_direction=normalize(vec3(-0.25,0.95,-0.15));
 float sun=max(dot(d,sun_direction),0.0);
 // The brightest opening is above. Its filtered light fades continuously
 // through the water column; the deepest water still belongs to local lamps.
 // Imported pale warm sunlight becomes cooler along a longer water path.
 vec3 filtered_sun=ocean_sun_color*vec3(0.30,0.55,1.0);
 water+=(filtered_sun*0.08*pow(sun,12.0)+ocean_sun_color*0.5*pow(sun,180.0))*ocean_sun_gain;
 // A broad veil and finer, uneven strands share the same sun opening.
 // Only their spread and strength drift; their origins never slide away
 // from the bright centre. Unequal spacing avoids a regular spoke pattern.
 float azimuths[8]=float[8](3.61,4.10,4.46,3.00,2.50,1.75,5.18,6.62);
 float widths[8]=float[8](0.090,0.036,0.062,0.043,0.080,0.054,0.048,0.073);
 float weights[8]=float[8](0.63,0.24,0.43,0.31,0.28,0.16,0.23,0.18);
 float scattered=0.0;
 for(int i=0;i<8;i++){
  float phase=float(i)*1.73;
  float angle=azimuths[i]+sin(ocean_visual_time*0.045+phase)*0.022;
  vec3 end=normalize(vec3(cos(angle),-0.16-0.09*sin(phase),sin(angle)));
  float strength=weights[i]*(0.88+0.12*sin(ocean_visual_time*0.071+phase));
  scattered+=strength*ocean_light_shaft(d,sun_direction,end,widths[i]);
 }
 water+=filtered_sun*0.35*scattered*ocean_shaft_gain;
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
 return vec4(ocean_radiance(direction),1.0-exp(-max(distance_m,0.0)*density*ocean_haze_gain));
}
