shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://native/presentation/ocean_background.gdshaderinc"
uniform bool debris=false;
varying float age;
varying float seed;
varying vec3 water_direction;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){
	vec2 cell=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1.0,0.0)),f.x),mix(hash(cell+vec2(0.0,1.0)),hash(cell+vec2(1.0)),f.x),f.y);
}
void vertex(){
	age=INSTANCE_CUSTOM.y;seed=INSTANCE_CUSTOM.z;
	water_direction=MODEL_MATRIX[3].xyz-CAMERA_POSITION_WORLD;
	if(!debris){
		MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
		VERTEX.xy*=INSTANCE_CUSTOM.x;
		MODELVIEW_NORMAL_MATRIX=mat3(MODELVIEW_MATRIX);
	}
}
void fragment(){
	ALBEDO=COLOR.rgb;ROUGHNESS=0.88;SPECULAR=0.16;
	ALPHA=COLOR.a;
	if(!debris){
		vec2 p=UV*2.0-1.0;
		float billow=noise(p*4.0+vec2(seed,age*.11));
		float fine=noise(p*13.0+vec2(-age*.08,seed));
		float edge=1.0-smoothstep(0.25,1.0,length(p)+(billow-.5)*.24);
		ALPHA*=edge*(.45+billow*.4+fine*.15);
		// Fine, pale suspended bubbles catch a lamp without becoming a fireball.
		ALBEDO*=.85+fine*.3;
	}
	FOG=ocean_fog(water_direction,length(water_direction),.0017);
}
