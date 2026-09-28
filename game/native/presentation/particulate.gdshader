shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 eye;
uniform vec3 eye_phase;
uniform vec3 cloud_origin;
uniform vec3 lamp_forward;
uniform vec3 lamp_origin;
uniform float lamps_on=1.0;
uniform float boost_amount=0.0;
uniform float drift_time=0.0;
uniform float enhanced=0.0;
uniform bool snow_enabled=true;
uniform bool bioluminescence_enabled=true;
uniform float snow_density=1.0;
uniform vec3 current_offset=vec3(0.0);
uniform vec3 focus_offset=vec3(0.0);
uniform mat4 lamp_frame_a;
uniform mat4 lamp_frame_b;
uniform sampler2D lamp_occlusion_a : filter_linear, repeat_disable;
uniform sampler2D lamp_occlusion_b : filter_linear, repeat_disable;
uniform float lamp_active_a=0.0;
uniform float lamp_active_b=0.0;
uniform vec3 lamp_color_a : source_color=vec3(.72,.9,1.0);
uniform vec3 lamp_color_b : source_color=vec3(.72,.9,1.0);
uniform vec4 disturbance[10];
uniform float disturbance_strength[10];
varying float shine;
varying float bubble;
varying float mote_seed;
varying float living_glow;
varying vec3 lit_color;
varying float lit_amount;
float lamp_light(vec3 center, mat4 frame, sampler2D reach, float active){
	vec3 p=(frame*vec4(center,1.0)).xyz;
	float depth=-p.z;
	vec2 cone=p.xy/max(depth*0.249,0.001);
	float end=textureLod(reach,cone*0.5+vec2(0.5),0.0).r;
	return active*smoothstep(0.0,1.0,depth)*(1.0-smoothstep(0.7,1.0,length(cone)))
		*(1.0-smoothstep(32.0,70.0,depth))*(1.0-smoothstep(end-0.4,end+0.2,depth));
}
void vertex(){
	vec3 center=MODEL_MATRIX[3].xyz-cloud_origin;
	bubble=INSTANCE_CUSTOM.y;
	mote_seed=INSTANCE_CUSTOM.x;
	// The open ocean is mostly suspended matter, with only occasional bubbles.
	if(enhanced>0.5){bubble*=step(0.82,mote_seed);center+=current_offset;}
	// Marine snow settles slowly; bubbles rise. Both drift with a gentle current.
	center.y+=drift_time*mix(-0.18-INSTANCE_CUSTOM.x*0.2,0.75+INSTANCE_CUSTOM.x*0.5,bubble);
	center.x+=sin(drift_time*0.35+INSTANCE_CUSTOM.x*30.0)*(0.35+bubble*0.2);
	center.z+=sin(drift_time*0.21+INSTANCE_CUSTOM.x*17.0)*0.3;
	vec3 focus=eye+focus_offset;
	center=focus+mod(center-eye_phase-focus_offset+vec3(45.0),vec3(90.0))-vec3(45.0);
	vec3 delta=center-eye;
	float distance=length(delta);
	vec3 from_lamp=center-lamp_origin;
	float lamp_distance=length(from_lamp);
	float cone=smoothstep(0.88,0.97,dot(from_lamp/max(lamp_distance,0.001),lamp_forward))*(1.0-smoothstep(4.0,80.0,lamp_distance))*lamps_on;
	// Fade to zero before the 90 m wrapping cell changes. Ordered smoothstep
	// edges are defined consistently by WebGL and native shader compilers.
	shine=(mix(0.55,0.85,bubble)+cone*0.2)*(1.0-smoothstep(26.0,42.0,distance))*smoothstep(3.0,8.0,distance);
	living_glow=0.0;
	lit_color=vec3(1.0);lit_amount=0.0;
	if(enhanced>0.5){
		float light_a=lamp_light(center,lamp_frame_a,lamp_occlusion_a,lamp_active_a);
		float light_b=lamp_light(center,lamp_frame_b,lamp_occlusion_b,lamp_active_b);
		float light=max(light_a,light_b);
		lit_color=(lamp_color_a*light_a+lamp_color_b*light_b)/max(light_a+light_b,0.001);
		lit_amount=light*2.8/(0.085+light*2.8);
		for(int i=0;i<10;i++){
			float age=max(0.0,drift_time-disturbance[i].w);
			float near_hull=1.0-smoothstep(3.0,13.0,length(center-disturbance[i].xyz));
			living_glow=max(living_glow,near_hull*exp(-age*1.3)*disturbance_strength[i]);
		}
		living_glow*=bioluminescence_enabled ? 1.0-bubble : 0.0;
		float density=1.0-smoothstep(snow_density/1.3-0.04,snow_density/1.3,fract(mote_seed*17.37+0.19));
		float suspended=snow_enabled ? 1.0 : bubble;
		shine=((0.085+light*2.8)*suspended+living_glow*3.5)*density*(1.0-smoothstep(26.0,42.0,length(center-focus)))*smoothstep(3.0,8.0,distance);
	}
	vec3 view_center=(VIEW_MATRIX*vec4(center,1.0)).xyz;
	vec2 radial=length(view_center.xy)>0.001?normalize(view_center.xy):vec2(0.0,1.0);
	vec2 across=vec2(-radial.y,radial.x);
	vec2 streak=across*VERTEX.x+radial*VERTEX.y*(1.0+boost_amount*(1.0-bubble)*12.0);
	// Give a dim mote enough pixel coverage to avoid subpixel flashing.
	// Projection maps NDC width 2 to the viewport width. The old factor 2.4
	// produced a 1.2-pixel quad, whose circular mask could miss all four pixels.
	// Render targets may flip projection Y; its sign must not disable the floor.
	float snow_pixels=mix(3.0,5.0,smoothstep(0.0,0.5,living_glow));
	float pixel_size=2.0*mix(snow_pixels,9.0,bubble)*abs(view_center.z)/(max(abs(PROJECTION_MATRIX[1][1]),0.001)*VIEWPORT_SIZE.y);
	float radius=INSTANCE_CUSTOM.z;
	if(enhanced>0.5 && INSTANCE_CUSTOM.y>0.5 && bubble<0.5){radius=0.03+mote_seed*0.045;}
	VERTEX=view_center+vec3(streak*max(radius,pixel_size),0.0);
	POSITION=PROJECTION_MATRIX*vec4(VERTEX,1.0);
}
void fragment(){
	vec2 p=(UV-0.5)*2.0;
	float r=length(p);
	float dust=pow(max(0.0,1.0-r),2.5);
	vec2 flake=p*vec2(0.85+mote_seed*0.3,1.15-mote_seed*0.2);
	dust*=0.65+0.35*cos(flake.x*5.0+flake.y*3.0+mote_seed*6.28);
	float rim_width=max(0.09,fwidth(r)*0.65);
	float rim=exp(-pow((r-0.76)/rim_width,2.0))*0.09/rim_width;
	float glint=exp(-dot(p-vec2(-0.28,-0.38),p-vec2(-0.28,-0.38))*95.0);
	float a=mix(dust*0.65,rim*0.6+glint*0.7+dust*0.018,bubble);
	a+=exp(-r*r*5.0)*living_glow*.18;
	ALBEDO=mix(vec3(0.50,0.70,0.76),vec3(0.76,0.91,0.94),bubble);
	ALBEDO=mix(ALBEDO,lit_color,lit_amount);
	ALBEDO=mix(ALBEDO,vec3(0.14,0.88,0.76),clamp(living_glow*2.0,0.0,1.0));
	ALPHA=clamp(a*shine*(1.0-smoothstep(0.92,1.0,r)),0.0,0.9);
}
