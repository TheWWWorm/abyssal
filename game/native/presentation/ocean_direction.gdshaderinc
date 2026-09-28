// Octahedral direction map, up (+Y) in the centre: the whole sphere in one
// square texture without a pole, so the sun and its shafts overhead keep
// their shape. The lower hemisphere folds into the corners.
vec2 ocean_direction_uv(vec3 d){
 d/=abs(d.x)+abs(d.y)+abs(d.z);
 vec2 p=d.xz;
 if(d.y<0.0){p=(1.0-abs(d.zx))*vec2(d.x>=0.0?1.0:-1.0,d.z>=0.0?1.0:-1.0);}
 return p*.5+.5;
}
vec3 ocean_uv_direction(vec2 uv){
 vec2 f=uv*2.0-1.0;
 vec3 d=vec3(f.x,1.0-abs(f.x)-abs(f.y),f.y);
 float t=max(-d.y,0.0);
 d.x+=d.x>=0.0?-t:t;d.z+=d.z>=0.0?-t:t;
 return normalize(d);
}
