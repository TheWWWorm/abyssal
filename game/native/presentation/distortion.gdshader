shader_type spatial;
// Refraction of the water around a detonation's pressure wave and in the
// stream behind a propeller (combat_effects.gd). Each pooled quad bends the
// scene behind it by the slope of an analytic height field: an expanding,
// damped ring for a shock (kind 0, camera facing), or drifting ripples along
// a stream (kind 1, turned about its axis towards the camera). Enhanced
// graphics only; the pool is hidden, so nothing samples the screen, while no
// effect is alive. Drawn first among the transparent surfaces (render
// priority set by the pool), so the water column, bubbles and flashes stay
// sharp over it and only the solid scene bends.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
// The environment's exposure (combat_effects.gd). Compatibility applies it,
// with its sRGB encoding, to everything it draws, and its copied screen comes
// back brighter by the exposure to the power 1/2.4: measured at exposures of
// 1.15 and 1.6, so the bent water keeps its colour there.
uniform float scene_exposure=1.0;
varying flat float kind;
varying flat float age;
varying flat float strength;
varying flat float phase;
// Length over width of a stream, so its ripples keep their spacing in metres.
varying flat float aspect;
varying float eye_depth;

float height(vec2 q, vec4 shape){
	// shape: kind, age, phase, aspect.
	float t=shape.y,turn=shape.z;
	if(shape.x<0.5){
		// A pressure front: one crest with a shallow trough behind it,
		// slowing as it spreads and dying away well before the quad's edge.
		float r=length(q);
		float front=mix(.12,.9,1.0-(1.0-t)*(1.0-t));
		float width=mix(.03,.07,t);
		float x=(r-front)/width;
		float uneven=1.0+.16*sin(q.x*7.0+turn)*sin(q.y*6.0-turn*1.3);
		return exp(-x*x)*cos(x*2.4)*width*uneven*(1.0-smoothstep(.9,1.0,r));
	}
	// q.y is 1 at the outlet and -1 where the stream has died away.
	float body=exp(-q.x*q.x*2.5)*smoothstep(-1.0,-.3,q.y)*(1.0-smoothstep(.7,1.0,q.y));
	float k=max(shape.w,1.0);
	float ripple=sin(q.y*k*3.1+turn+q.x*1.7)*.6+sin(q.y*k*5.3+turn*1.37-q.x*2.3)*.4;
	// Steeper along a long stream in quad units, the same in metres.
	return body*ripple;
}

float scene_distance(vec2 uv, mat4 inverse_projection){
	float depth=texture(scene_depth,uv).r;
	vec3 ndc=vec3(uv*2.0-1.0,depth);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z=depth*2.0-1.0;
	#endif
	vec4 view=inverse_projection*vec4(ndc,1.0);
	return -view.z/view.w;
}

void vertex(){
	kind=INSTANCE_CUSTOM.x;age=clamp(INSTANCE_CUSTOM.y,0.0,1.0);strength=INSTANCE_CUSTOM.z;phase=INSTANCE_CUSTOM.w;
	vec3 origin=MODEL_MATRIX[3].xyz;
	float width=length(MODEL_MATRIX[0].xyz);
	vec3 world;
	aspect=1.0;
	if(kind<0.5){
		world=origin+(INV_VIEW_MATRIX[0].xyz*VERTEX.x+INV_VIEW_MATRIX[1].xyz*VERTEX.y)*width;
	}else{
		// The stream's axis as seen across the view. Looked at end on, it
		// keeps at least its own width, a small round shimmer at the outlet.
		vec3 eye=normalize(CAMERA_POSITION_WORLD-origin);
		vec3 axis=MODEL_MATRIX[1].xyz;
		vec3 along=axis-eye*dot(axis,eye);
		float span=length(along);
		vec3 direction=span>.0001?along/span:INV_VIEW_MATRIX[1].xyz;
		vec3 side=normalize(cross(direction,eye));
		along=direction*max(span,width);
		aspect=max(span,width)/max(width,.0001);
		world=origin+along*VERTEX.y+side*VERTEX.x*width;
	}
	VERTEX=(VIEW_MATRIX*vec4(world,1.0)).xyz;
	eye_depth=-VERTEX.z;
}

void fragment(){
	vec2 q=vec2(UV.x*2.0-1.0,1.0-UV.y*2.0);
	// Quad units per screen pixel, taken before any fragment is discarded.
	vec2 jx=dFdx(q),jy=dFdy(q);
	float rate=max(max(length(jx),length(jy)),.000001);
	float radius=1.0/rate;
	// Away from a shock's thin front nothing bends: most of its quad stops here.
	float front=mix(.12,.9,1.0-(1.0-age)*(1.0-age));
	if(kind<0.5&&abs(length(q)-front)>mix(.03,.07,age)*3.5){discard;}
	// At most a few pixels however close the quad: a large shock bends a
	// thin band, never the whole view, and fades out as it nears the view's
	// edges; so does a stream the camera is about to enter.
	// The slopes peak near 2.5 (ring) and 4 (stream): about 5 and 3 pixels.
	float reach=kind<0.5?min(.025*radius,2.0):min(.12*radius,.8);
	float span=kind<0.5?front*radius:radius*4.0;
	float cover=1.0-smoothstep(.35,.7,span/VIEWPORT_SIZE.y);
	float fade=strength*cover*smoothstep(2.0,8.0,eye_depth);
	if(fade<.002){discard;}
	// The slope of the field, carried from quad units to screen pixels.
	float e=.01;
	vec4 shape=vec4(kind,age,phase,aspect);
	float h=height(q,shape);
	vec2 slope=vec2(height(q+vec2(e,0.0),shape)-h,height(q+vec2(0.0,e),shape)-h)/e;
	vec2 offset=vec2(dot(slope,jx),dot(slope,jy))/rate*reach*fade;
	// The compressed water at a shock's crest is a shade lighter, so the
	// front reads faintly even over open water with nothing behind to bend.
	float crest=kind<0.5?max(h/mix(.03,.07,age),0.0)*fade:0.0;
	if(dot(offset,offset)<.0004&&crest<.01){discard;}
	// Fade where the quad cuts into the scene, instead of a hard seam.
	float behind=clamp((scene_distance(SCREEN_UV,INV_PROJECTION_MATRIX)-eye_depth)/(kind<0.5?4.0:1.0),0.0,1.0);
	offset*=behind;crest*=behind;
	vec2 uv=SCREEN_UV+offset/VIEWPORT_SIZE;
	// Never pull in a hull or rock that stands in front of the wave.
	if(scene_distance(uv,INV_PROJECTION_MATRIX)<eye_depth){uv=SCREEN_UV;}
	ALBEDO=textureLod(screen,uv,0.0).rgb*(1.0+crest*.06);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO/=pow(max(scene_exposure,.0001),1.0/2.4);
	#endif
	ALPHA=clamp(max(length(offset)*1.5,crest*4.0),0.0,1.0);
}
