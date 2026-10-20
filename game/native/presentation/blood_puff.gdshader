shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Stand-in for the fischtod blood cloud when a JAR's cache has no such model:
// a dark red puff over the water, from fx.bmp's cloud when it is there.
uniform sampler2D cloud : source_color, filter_linear, repeat_disable;
uniform bool cloud_enabled = false;
// Offset and size of the cloud in the atlas, in texture coordinates.
uniform vec4 cloud_region = vec4(0.75, 0.75, 0.25, 0.25);
varying float age;
void vertex(){
	age=clamp(INSTANCE_CUSTOM.y,0.0,1.0);
	vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
	float diameter=INSTANCE_CUSTOM.x*(0.6+0.4*sqrt(age));
	POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy*diameter,0.0),1.0);
}
void fragment(){
	vec2 p=(UV-0.5)*2.0;
	float shape=max(0.0,1.0-dot(p,p));
	if(cloud_enabled){
		vec3 texel=texture(cloud,cloud_region.xy+UV*cloud_region.zw).rgb;
		shape=min(1.0,max(texel.r,max(texel.g,texel.b))*3.0)*step(0.0,1.0-dot(p,p));
	}
	ALBEDO=COLOR.rgb;
	ALPHA=clamp(shape*(1.0-age*age)*COLOR.a*0.85,0.0,1.0);
}
