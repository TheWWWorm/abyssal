shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Keep the imported silhouettes, animation and pigments. A composited coloured
// body stays legible against a headlight cone; additive layers washed it out.
uniform mat4 source_bones[64];
uniform vec3 effect_center;
uniform vec3 effect_extent = vec3(1.0);
uniform vec4 pigment : source_color = vec4(0.1,0.8,1.0,1.0);
uniform int long_axis = 2;
uniform bool disc = false;
uniform bool subtractive = false;
uniform int family = 0;
uniform float visual_time = 0.0;
varying vec3 local_point;
varying vec3 local_ray;
varying float transmission;
float square(float x) { return x*x; }
void vertex() {
	local_point = (VERTEX-effect_center)/max(effect_extent,vec3(0.01));
	mat4 bone=source_bones[int(UV2.x+0.5)];
	local_ray=vec3(0.0,0.0,1.0);
	if(abs(determinant(mat3(bone)))>0.000001){
		vec3 eye=(inverse(MODELVIEW_MATRIX*bone)*vec4(0.0,0.0,0.0,1.0)).xyz;
		local_ray=(eye-VERTEX)/max(effect_extent,vec3(0.01));
	}
	VERTEX=(bone*vec4(VERTEX,1.0)).xyz;
	vec3 n=mat3(bone)*NORMAL;
	NORMAL=length(n)>0.0001?normalize(n):vec3(0.0,1.0,0.0);
	transmission=exp(-length((MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz)*0.0008);
}
void fragment() {
	vec3 p=local_point;
	float axial=long_axis==0?p.x:(long_axis==1?p.y:p.z);
	vec2 cross_section=long_axis==0?p.yz:(long_axis==1?p.xz:p.xy);
	vec2 cross_ray=long_axis==0?local_ray.yz:(long_axis==1?local_ray.xz:local_ray.xy);
	vec2 closest=cross_section-cross_ray*dot(cross_section,cross_ray)/max(dot(cross_ray,cross_ray),0.001);
	float radius=length(closest);
	float axial_ray=long_axis==0?local_ray.x:(long_axis==1?local_ray.y:local_ray.z);
	float end_on=smoothstep(0.90,0.995,abs(axial_ray)/max(length(local_ray),0.001));
	float ends=mix(1.0-smoothstep(0.70,1.0,abs(axial)),1.0,end_on);
	vec3 tint=pigment.rgb/max(max(pigment.r,pigment.g),max(pigment.b,0.001));
	vec3 hot=mix(tint,vec3(0.80,0.92,0.98),0.28);
	float aa=max(fwidth(radius),0.015);
	float body=1.0-smoothstep(0.45-aa,0.58+aa,radius);
	float core=exp(-square(radius/0.22)*2.0);
	vec3 colour=mix(tint*0.25,hot,core);
	float alpha=body*ends*0.92;
	if(family==1){
		// One continuous rail dart, not a bright head plus a second tracer.
		// These are closed hexagonal rods. Masking their outer faces as if
		// they were billboard planes cuts the middle out at chase angles.
		float face=abs(dot(normalize(NORMAL),normalize(VIEW)));
		float ridge=.55+.35*(1.0-abs(axial));
		colour=mix(tint*.22,hot,clamp(face*.48+ridge*.45,0.0,1.0));
		alpha=(1.0-smoothstep(.96,1.0,abs(axial)))*.94;
	}
	if(family==2){
		// Eclipse: a hollow containment envelope, with its own central spine.
		vec2 across=vec2(-cross_ray.y,cross_ray.x)/max(length(cross_ray),0.001);
		float lateral=dot(cross_section,across);
		float shell=0.19+0.36*(1.0-axial*axial);
		float ripple=sin(axial*19.0-visual_time*8.0)*0.045;
		float width=max(fwidth(lateral)*1.2,0.055);
		float edges=exp(-square((abs(lateral)-shell-ripple)/width));
		float spine=exp(-square(lateral/0.08));
		float field=max(edges,spine*.7);
		colour=mix(tint*.15,hot,field*.9);
		alpha=mix((field*.88+.08)*ends,body*.9,end_on);
	}
	if(long_axis==1 && !disc){
		// Mass accelerators launch a dense flared round. Keep its square
		// end and narrow shaft, with a confined field along the ridges.
		float face=abs(dot(normalize(NORMAL),normalize(VIEW)));
		float rim=smoothstep(.76,.92,abs(axial));
		float ridge=pow(abs(sin(atan(p.z+.00001,p.x+.00001)*2.0)),8.0);
		float field=max(rim*.75,ridge*.65);
		vec3 shell=mix(vec3(.10,.16,.21),tint*.35,.6);
		colour=mix(shell*(.65+face*.35),hot,field);
		alpha=.95;
	}
	if(disc){
		// Fusion rounds retain the broad disc and open concentric rings.
		float r=length(p.xz);
		float a=atan(p.z+0.00001,p.x+0.00001);
		float width=max(fwidth(r)*1.1,0.028);
		float rim=1.0-smoothstep(.065,.065+width,abs(r-.74));
		float inner=1.0-smoothstep(.025,.025+width,abs(r-.44));
		float cuts=.55+.45*square(sin(a*3.0-visual_time*5.0));
		float hub=exp(-r*r*38.0);
		float rings=max(rim,inner*cuts);
		colour=mix(tint*.18,hot,max(rings*.85,hub));
		alpha=(max(rings,hub)*.94+.035)*(1.0-smoothstep(.88,1.0,r));
	}
	ALBEDO=colour*transmission;
	ALPHA=clamp(alpha,0.0,.97)*(subtractive?0.0:1.0);
}
