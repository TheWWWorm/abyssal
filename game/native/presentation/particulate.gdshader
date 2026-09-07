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
varying float shine;
varying float bubble;
varying float mote_seed;
void vertex(){
	vec3 center=MODEL_MATRIX[3].xyz-cloud_origin;
	bubble=INSTANCE_CUSTOM.y;
	mote_seed=INSTANCE_CUSTOM.x;
	// Marine snow settles slowly; bubbles rise. Both drift with a gentle current.
	center.y+=drift_time*mix(-0.18-INSTANCE_CUSTOM.x*0.2,0.75+INSTANCE_CUSTOM.x*0.5,bubble);
	center.x+=sin(drift_time*0.35+INSTANCE_CUSTOM.x*30.0)*(0.35+bubble*0.2);
	center.z+=sin(drift_time*0.21+INSTANCE_CUSTOM.x*17.0)*0.3;
	center=eye+mod(center-eye_phase+vec3(45.0),vec3(90.0))-vec3(45.0);
	vec3 delta=center-eye;
	float distance=length(delta);
	vec3 from_lamp=center-lamp_origin;
	float lamp_distance=length(from_lamp);
	float cone=smoothstep(0.88,0.97,dot(from_lamp/max(lamp_distance,0.001),lamp_forward))*(1.0-smoothstep(4.0,80.0,lamp_distance))*lamps_on;
	// Fade to zero before the 90 m wrapping cell changes. Ordered smoothstep
	// edges are defined consistently by WebGL and native shader compilers.
	shine=(mix(0.55,0.85,bubble)+cone*0.2)*(1.0-smoothstep(26.0,42.0,distance))*smoothstep(3.0,8.0,distance);
	vec3 view_center=(VIEW_MATRIX*vec4(center,1.0)).xyz;
	vec2 radial=length(view_center.xy)>0.001?normalize(view_center.xy):vec2(0.0,1.0);
	vec2 across=vec2(-radial.y,radial.x);
	vec2 streak=across*VERTEX.x+radial*VERTEX.y*(1.0+boost_amount*(1.0-bubble)*12.0);
	// Give a dim mote enough pixel coverage to avoid subpixel flashing.
	// Projection maps NDC width 2 to the viewport width. The old factor 2.4
	// produced a 1.2-pixel quad, whose circular mask could miss all four pixels.
	// Render targets may flip projection Y; its sign must not disable the floor.
	float pixel_size=2.0*mix(3.0,9.0,bubble)*abs(view_center.z)/(max(abs(PROJECTION_MATRIX[1][1]),0.001)*VIEWPORT_SIZE.y);
	VERTEX=view_center+vec3(streak*max(INSTANCE_CUSTOM.z,pixel_size),0.0);
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
	ALBEDO=mix(vec3(0.50,0.70,0.76),vec3(0.76,0.91,0.94),bubble);
	ALPHA=a*shine*(1.0-smoothstep(0.92,1.0,r));
}
