// Azimuthal direction map, up (+Y) in the centre and straight down on the
// rim: the whole sphere in one square texture without a pole overhead, so the
// sun and its shafts keep their shape. Distance from the centre follows the
// angle from straight up, so the map is smooth in every direction a pilot
// sees; an octahedral map bent along two planes through the zenith, which
// showed as straight seams converging upwards in the water.
const float OCEAN_MAP_PI = 3.14159265358979;
vec2 ocean_direction_uv(vec3 d){
 d=normalize(d);
 float radius=acos(clamp(d.y,-1.0,1.0))/OCEAN_MAP_PI;
 float across=length(d.xz);
 vec2 heading=across>1e-6?d.xz/across:vec2(0.0);
 return heading*radius*.5+.5;
}
vec3 ocean_uv_direction(vec2 uv){
 vec2 f=uv*2.0-1.0;
 float radius=length(f);
 // The corners beyond the rim hold straight down, so filtering at the rim
 // blends only with the water below.
 float angle=min(radius,1.0)*OCEAN_MAP_PI;
 vec2 heading=radius>1e-6?f/radius:vec2(1.0,0.0);
 return vec3(heading.x*sin(angle),cos(angle),heading.y*sin(angle));
}
