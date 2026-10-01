shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Only arithmetic every WebGL translation agrees on: no two-argument atan and
// no pow() of a signed base. Browsers on Windows run WebGL through Direct3D,
// where those paths filled the whole quad with the burst's colour.
varying float age;
varying float bubble;
varying float wake;
void vertex(){
	age=clamp(INSTANCE_CUSTOM.y,0.0,1.0);
	bubble=step(0.5,INSTANCE_CUSTOM.z);
	wake=step(1.5,INSTANCE_CUSTOM.z);
	vec3 center=(VIEW_MATRIX*MODEL_MATRIX[3]).xyz;
	float expand=mix(0.12+sqrt(age)*0.88,1.0,bubble);
	// Keep thin bubble rims sampled, including render targets with flipped Y.
	float minimum_diameter=10.0*abs(center.z)/(max(abs(PROJECTION_MATRIX[1][1]),0.001)*VIEWPORT_SIZE.y);
	float diameter=max(INSTANCE_CUSTOM.x*expand,minimum_diameter*bubble);
	POSITION=PROJECTION_MATRIX*vec4(center+vec3(VERTEX.xy*diameter,0.0),1.0);
}
vec2 turn(vec2 a,vec2 b){return vec2(a.x*b.x-a.y*b.y,a.x*b.y+a.y*b.x);}
void fragment(){
	vec2 p=(UV-0.5)*2.0;
	float r=length(p);
	// Powers of the unit direction give cos/sin of multiples of its angle.
	vec2 z1=p/max(r,0.0001);
	vec2 z2=turn(z1,z1);vec2 z4=turn(z2,z2);vec2 z8=turn(z4,z4);vec2 z16=turn(z8,z8);
	vec2 z7=turn(turn(z4,z2),z1);
	vec2 z11=turn(turn(z8,z2),z1);
	vec2 z23=turn(turn(z16,z4),turn(z2,z1));
	float rim_width=max(1.0/16.0,fwidth(r));
	float rim=(r-0.78)/rim_width;
	float ring=exp(-rim*rim)*(1.0/16.0)/rim_width;
	float hollow=max(0.0,1.0-r);
	float core=hollow*hollow*hollow;
	// sin(11a+7age) and sin(23a+sin(7a)), by angle addition.
	float rays=0.7+0.3*(z11.y*cos(age*7.0)+z11.x*sin(age*7.0));
	float warp=z7.y;
	float spoke=max(0.0,z23.y*cos(warp)+z23.x*sin(warp));
	float spoke2=spoke*spoke;float spoke4=spoke2*spoke2;float spoke8=spoke4*spoke4;
	float front=(r-age*.8)*9.0;
	float splinters=spoke8*spoke8*spoke8*exp(-front*front);
	float fade=1.0-age;
	float explosion=(core*1.6+splinters*.7+ring*.06*rays)*fade*fade;
	vec2 g=p-vec2(-0.28,-0.38);
	float glint=exp(-dot(g,g)*90.0);
	float exhaust=(ring*mix(.09,.3,wake)+glint*.25+core*.2*wake)*fade;
	float alpha=mix(explosion,exhaust,bubble)*COLOR.a;
	ALBEDO=COLOR.rgb;
	EMISSION=COLOR.rgb*mix(2.0,0.0,bubble);
	// Bounded, and a value that is not a number is dropped, not drawn.
	ALPHA=alpha>0.0?min(alpha,2.5):0.0;
}
