shader_type fog;
uniform float density=.008;
uniform vec3 water_albedo : source_color=vec3(.65,.76,.80);
float hash3(vec3 p){p=fract(p*.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z);}
float water_noise(vec3 p){
 vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1)),f.x),f.y),f.z);
}
void fog(){
 vec3 p=WORLD_POSITION*.055+vec3(TIME*.014,-TIME*.009,0);
 float suspended=water_noise(p)*.7+water_noise(p*2.1)*.3;
 float edge=smoothstep(0.0,.48,1.0-length(UVW*2.0-1.0));
 DENSITY=density*mix(.32,1.6,suspended)*edge;
 ALBEDO=water_albedo;
}
