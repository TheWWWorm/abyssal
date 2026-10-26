shader_type spatial;
render_mode unshaded, depth_prepass_alpha, cull_disabled, shadows_disabled, fog_disabled;
uniform bool cable = false;
uniform bool pulse_glow = false;
varying vec3 local_point;
varying float kind;
varying float phase;
varying float part;
varying float line_length;
varying float active;
varying vec3 line_axis;
void vertex(){
	local_point=VERTEX;
	kind=INSTANCE_CUSTOM.r;
	phase=INSTANCE_CUSTOM.g;
	part=UV2.y;
	active=cable?1.0:(abs(UV2.x-kind)<.1?1.0:0.0);
	line_length=length(MODEL_MATRIX[1].xyz);
	line_axis=normalize((VIEW_MATRIX*MODEL_MATRIX)[1].xyz);
	vec3 center=(MODELVIEW_MATRIX*vec4(0.0,VERTEX.y,0.0,1.0)).xyz;
	float clip_w=abs((PROJECTION_MATRIX*vec4(center,1.0)).w);
	float pixel=2.0*clip_w/(max(abs(PROJECTION_MATRIX[1][1]),0.001)*VIEWPORT_SIZE.y);
	float radius=max(length(MODEL_MATRIX[0].xyz),0.0001);
	// A two-pixel tether and readable tip survive the normal chase
	// camera and headlight haze. The silhouette remains depth-tested.
	VERTEX.xz*=max(1.0,pixel*(cable?1.25:6.0)/radius);
	if(pulse_glow){
		float swell=pow(.5+.5*sin(phase*6.2831853/1.6),2.0);
		VERTEX.xz*=5.5+2.0*swell;
	}
	if(active<.5)VERTEX=vec3(0.0);
}
void fragment(){
	if(active<.5)discard;
	vec3 tint=COLOR.rgb/max(max(COLOR.r,COLOR.g),max(COLOR.b,.001));
	vec3 eye=normalize(VIEW);
	if(cable){
		// Resolve the cylinder across its axis. At the chase camera's shallow
		// angle, using the full eye vector darkened the entire line.
		vec3 across=eye-line_axis*dot(eye,line_axis);
		if(length(across)>.0001)eye=normalize(across);
	}
	float facing=abs(dot(normalize(NORMAL),eye));
	float edge=smoothstep(.10,.72,facing);
	vec3 steel=mix(vec3(.07,.12,.16),vec3(.43,.57,.63),edge);
	ALBEDO=mix(steel,tint*(.55+.35*edge),part);
	ALPHA=1.0;
	if(cable){
		// The entire rope breathes in its harpoon colour, with enough glow
		// at the trough to retain a broad, continuous silhouette.
		float along=(local_point.y+.5)*line_length;
		float braid=.94+.06*sin(along*3.0+atan(local_point.z,local_point.x)*3.0);
		steel=tint*(.25+.20*edge)*braid;
		float swell=pow(.5+.5*sin(phase*6.2831853/1.6),2.0);
		float strength=.42+.58*swell;
		if(pulse_glow){
			// A depth-tested halo keeps the pulse luminous on renderers
			// without bloom. Its centre stays coloured rather than white.
			if(!FRONT_FACING)discard;
			float core=pow(facing,18.0);
			float end_fade=smoothstep(0.0,min(2.5,line_length*.25),min(along,line_length-along));
			ALBEDO=tint*.65;
			EMISSION=tint*(1.2+4.0*core)*strength;
			ALPHA=end_fade*strength*(.62*core+.26*pow(facing,3.0));
		}else{
			ALBEDO=mix(steel,tint*(.40+.36*edge),strength*.95);
			EMISSION=tint*(.15+2.4*strength);
		}
	}
}
