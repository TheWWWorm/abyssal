shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color=vec4(1.0);
uniform sampler2D albedo_map : source_color;
uniform bool textured=false;
uniform vec3 emission_color : source_color=vec3(0.0);
uniform float roughness_value=.5;
uniform float metallic_value=.3;
uniform vec4 clip_plane;
varying vec3 world_vertex;
void vertex(){world_vertex=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if(dot(clip_plane.xyz,world_vertex)+clip_plane.w<0.0)discard;
 ALBEDO=tint.rgb*(textured?texture(albedo_map,UV).rgb:vec3(1.0));
 EMISSION=emission_color;ROUGHNESS=roughness_value;METALLIC=metallic_value;
}
