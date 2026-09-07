shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
varying float age;
varying float bubble;
varying float wake;
void vertex(){
	age=INSTANCE_CUSTOM.y;
	bubble=step(0.5,INSTANCE_CUSTOM.z);
	wake=step(1.5,INSTANCE_CUSTOM.z);
	vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
	float expand=mix(0.12+sqrt(age)*0.88,1.0,bubble);
	// Keep thin bubble rims sampled, including render targets with flipped Y.
	float minimum_diameter=10.0*abs(center.z)/(max(abs(PROJECTION_MATRIX[1][1]),0.001)*VIEWPORT_SIZE.y);
	float diameter=max(INSTANCE_CUSTOM.x*expand,minimum_diameter*bubble);
	POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy*diameter,0.0),1.0);
}
void fragment(){
	vec2 p=(UV-0.5)*2.0;
	float r=length(p);
	float rim_width=max(1.0/16.0,fwidth(r));
	float ring=exp(-pow((r-0.78)/rim_width,2.0))*(1.0/16.0)/rim_width;
	float core=pow(max(0.0,1.0-r),3.0);
	float rays=0.7+0.3*sin(atan(p.y,p.x)*11.0+age*7.0);
	float angular=atan(p.y,p.x);
	float splinters=pow(max(0.0,sin(angular*23.0+sin(angular*7.0))),24.0)*exp(-pow((r-age*.8)*9.0,2.0));
	float explosion=(core*1.6+splinters*.7+ring*.06*rays)*pow(1.0-age,2.0);
	float glint=exp(-dot(p-vec2(-0.28,-0.38),p-vec2(-0.28,-0.38))*90.0);
	float exhaust=(ring*mix(.09,.3,wake)+glint*.25+core*.2*wake)*(1.0-age);
	ALBEDO=COLOR.rgb;
	EMISSION=COLOR.rgb*mix(2.0,0.0,bubble);
	ALPHA=mix(explosion,exhaust,bubble)*COLOR.a;
}
