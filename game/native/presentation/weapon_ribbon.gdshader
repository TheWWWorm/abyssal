shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// A travelling coil segment or short impact filament. Coloured coverage and
// a dark edge remain readable against lit water, without an additive flare.
varying float trail;
varying float visibility;
varying float visual_time;
varying float style;
varying float line_length;
void vertex(){
	trail=INSTANCE_CUSTOM.x;
	visual_time=INSTANCE_CUSTOM.y;
	style=INSTANCE_CUSTOM.z;
	line_length=length(MODEL_MATRIX[1].xyz);
	vec3 center=(MODELVIEW_MATRIX*vec4(0.0,VERTEX.y,0.0,1.0)).xyz;
	vec2 axis=MODELVIEW_MATRIX[1].xy;
	float projected=length(axis);
	vec2 along=projected>.0001?axis/projected:vec2(0.0,1.0);
	vec2 across=vec2(-along.y,along.x);
	float clip_w=abs((PROJECTION_MATRIX*vec4(center,1.0)).w);
	float pixel=2.0*clip_w/(max(abs(PROJECTION_MATRIX[1][1]),.001)*VIEWPORT_SIZE.y);
	float radius=length(MODEL_MATRIX[0].xyz);
	float filtered=max(radius,pixel*1.25);
	visibility=exp(-length(center)*.0008);
	center.xy+=across*VERTEX.x*2.0*filtered;
	center.xy+=along*VERTEX.y*max(0.0,pixel*2.0-projected);
	POSITION=PROJECTION_MATRIX*vec4(center,1.0);
}
float square(float x){return x*x;}
void fragment(){
	float sx=UV.x*2.0-1.0;
	float x=abs(sx);
	float edge=1.0-smoothstep(.62,.96,x);
	float core=exp(-x*x*14.0);
	float ends=smoothstep(0.0,.025,UV.y)*(1.0-smoothstep(.975,1.0,UV.y));
	float taper=mix(1.0,pow(clamp(1.0-UV.y,0.0,1.0),1.25),clamp(trail,0.0,1.0));
	if(style>.5 && trail<.5){
		float curl=style>1.5?sin(UV.y*line_length*.7-visual_time*8.0)*.24:.30;
		float rails=max(exp(-square((sx-curl)*9.0)),exp(-square((sx+curl)*9.0)));
		core=max(core*.55,rails*.85);
	}
	vec3 tint=COLOR.rgb/max(max(COLOR.r,COLOR.g),max(COLOR.b,.001));
	vec3 hot=mix(tint,vec3(.80,.92,.98),.22);
	ALBEDO=mix(tint*.14,hot,core)*visibility;
	ALPHA=(.64+core*.31)*edge*ends*taper*COLOR.a;
}
