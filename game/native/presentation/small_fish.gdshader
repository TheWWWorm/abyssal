shader_type spatial;
// Small fish (small_fish.gd): every fish of every slot in one draw. The
// script moves each slot's centre and makes it flee the hull; here each fish
// keeps a loose place in its school, or swims its own way in a loose group,
// beats its tail and takes its species' build and markings. Fish very close
// to the hull also dart aside on their own. They are lit like any hull, so
// in the deep they are seen mostly as they cross the headlights, and a fish
// out of reach, in a block of water without one or about to meet a station,
// dissolves (presence).
render_mode cull_disabled;
// One row per slot: the centre measured from the camera and its presence;
// its velocity in metres a second and its radius; its species, time shift,
// alarm and the distance it fades out by; its size and colour variant.
uniform highp sampler2D school_data : filter_nearest;
uniform vec3 hull=vec3(0.0,-1000.0,0.0);
// The hull's velocity in metres a second.
uniform vec3 hull_motion=vec3(0.0);
uniform float clock=0.0;
// Fish within SHY metres of a hull edge away from it; fish near the path of
// a moving hull dart aside. Neither pushes them ahead of it.
const float SHY=6.0;
const float ASIDE=5.0;
varying float presence;
varying flat float species;
varying flat float variant;
varying float fin;
varying vec3 shape;

float hash(float p){
	p=fract(p*.1031);p*=p+33.33;p*=p+p;
	return fract(p);
}
vec3 hash3(float p){
	return vec3(hash(p*17.17+1.3),hash(p*31.31+7.1),hash(p*53.53+3.7));
}
// Height and width of each species' body against the one-metre mesh.
vec2 build(int kind){
	if(kind==1)return vec2(1.7,.75);
	if(kind==2)return vec2(.45,.7);
	if(kind==3)return vec2(1.15,1.5);
	if(kind==4)return vec2(2.0,.6);
	if(kind==5)return vec2(1.1,1.0);
	if(kind==6)return vec2(.9,.9);
	if(kind==7)return vec2(.85,1.0);
	return vec2(.8,.9);
}
void vertex(){
	int s=int(INSTANCE_CUSTOM.x+.5);
	float seed=INSTANCE_CUSTOM.y;
	float own=INSTANCE_CUSTOM.w;
	vec4 place=texelFetch(school_data,ivec2(0,s),0);
	vec4 course=texelFetch(school_data,ivec2(1,s),0);
	vec4 look=texelFetch(school_data,ivec2(2,s),0);
	vec4 extra=texelFetch(school_data,ivec2(3,s),0);
	float size=INSTANCE_CUSTOM.z*extra.x;
	float alarm=look.z;
	vec3 heading=course.xyz;
	float speed=length(heading);
	vec3 ahead=speed>.01?heading/speed:vec3(0.0,0.0,1.0);
	vec3 across=normalize(cross(vec3(0.0,1.0,0.0),ahead)+vec3(.0001,0.0,0.0));
	vec3 above=cross(ahead,across);
	// A place in a lens-shaped school, longer than it is wide, flatter than
	// both, evenly filled; an alarmed school closes up.
	float radius=course.w*(1.0-.3*alarm*(1.0-own));
	vec3 spot=hash3(seed)*2.0-1.0;
	spot=normalize(spot+vec3(.0001))*pow(hash(seed*7.77+.5),.333);
	vec3 centre=place.xyz+(across*spot.x*.8+above*spot.y*mix(.35,.3,own)+ahead*spot.z)*radius;
	// Each fish strays about its place: a little in a school, widely and
	// each its own way in a group.
	float t=clock+look.y;
	vec3 rate=vec3(.31,.43,.37)*(.7+.6*hash3(seed*3.3))*mix(1.0,.6,own);
	vec3 phase=hash3(seed*5.5)*6.2832;
	vec3 reach=mix(vec3(.6,.25,.6)*(.4+radius*.15),vec3(2.5,.6,2.5),own);
	centre+=reach*sin(rate*t+phase);
	vec3 velocity=heading*(1.0-.6*own*(1.0-alarm))+reach*rate*cos(rate*t+phase);
	vec3 away=centre-hull;
	float apart=max(length(away),.001);
	float pace=length(hull_motion);
	float shy=(1.0-smoothstep(2.5,SHY,apart))*(1.0-.75*smoothstep(1.0,5.0,pace));
	centre+=away/apart*shy*2.0;
	vec3 path=pace>.01?hull_motion/pace:vec3(0.0,0.0,1.0);
	float ahead_of=dot(away,path);
	vec3 side=away-path*ahead_of;
	// A fish right on the path picks a side of its own.
	side+=across*(hash(seed*2.9)-.5)*.02;
	float aside=max(length(side),.001);
	float warning=8.0+min(pace*.3,24.0);
	float dart=smoothstep(1.0,5.0,pace)*(1.0-smoothstep(1.5,ASIDE,aside))*smoothstep(-14.0,-2.0,ahead_of)*(1.0-smoothstep(warning*.6,warning,ahead_of));
	centre+=side/aside*dart*3.0;
	float fright=max(max(shy,dart),alarm*.6);
	velocity=mix(velocity,(away/apart*shy+side/aside*dart*2.0)*max(speed,1.5)*2.0,min(max(shy,dart),.85));
	// Nor do they swim into the camera.
	float near=max(length(centre),.001);
	centre+=centre/near*(1.0-smoothstep(1.5,4.0,near))*2.5;
	// Fish keep nearly level, whichever way they turn.
	vec3 forward=normalize(velocity+vec3(0.0,0.0,.0001));
	forward=normalize(vec3(forward.x,clamp(forward.y,-.5,.5),forward.z));
	vec3 right=normalize(cross(vec3(0.0,1.0,0.0),forward)+vec3(.0001,0.0,0.0));
	mat3 frame=mat3(right,cross(forward,right),forward);
	// The tail beats faster with speed and fright; the head barely moves.
	int kind=int(look.x+.5);
	vec2 body_build=build(kind);
	float along=COLOR.r;
	float tempo=(5.0+length(velocity)*3.0+fright*14.0)*(.85+.3*hash(seed*9.1));
	vec3 body=VERTEX*vec3(body_build.y,body_build.x,1.0);
	body.x+=sin(t*tempo+seed*6.2832-along*4.5)*along*along*.16*(1.0+fright);
	shape=VERTEX;fin=COLOR.g;species=look.x;variant=extra.y;
	presence=place.w*(1.0-smoothstep(look.w*.68,look.w,length(centre)));
	VERTEX=centre+frame*(body*size);
	NORMAL=frame*normalize(NORMAL/vec3(body_build.y,body_build.x,1.0));
	// A fish that is not there collapses to a point and draws nothing.
	if(presence<.003)VERTEX=vec3(0.0);
}
void fragment(){
	// Dissolve with a fixed screen pattern, which temporal antialiasing
	// smooths into a fade, so the fish stay opaque and depth-sorted.
	float pattern=fract(52.9829189*fract(dot(FRAGCOORD.xy,vec2(.06711056,.00583715))));
	if(pattern>presence)discard;
	// Dark back, light belly, tinted fins; a small dark eye; then each
	// species' markings.
	vec3 back=vec3(.14,.24,.32);vec3 belly=vec3(.80,.82,.84);vec3 fins=vec3(.55,.60,.62);float sheen=.8;
	int kind=int(species+.5);
	if(kind==1){back=vec3(.42,.44,.40);belly=vec3(.86,.84,.78);fins=vec3(.85,.70,.20);sheen=.6;}
	else if(kind==2){back=vec3(.08,.30,.32);belly=vec3(.70,.82,.80);fins=vec3(.20,.45,.45);sheen=.7;}
	else if(kind==3){back=vec3(.24,.20,.12);belly=vec3(.58,.50,.34);fins=vec3(.32,.26,.15);sheen=.15;}
	else if(kind==4){back=vec3(.88,.76,.22);belly=vec3(.95,.92,.80);fins=vec3(.92,.80,.25);sheen=.2;}
	else if(kind==5){back=vec3(.50,.08,.06);belly=vec3(.85,.40,.30);fins=vec3(.70,.20,.12);sheen=.3;}
	else if(kind==6){back=vec3(.06,.12,.35);belly=vec3(.55,.16,.20);fins=vec3(.20,.25,.50);sheen=.4;}
	else if(kind==7){back=vec3(.05,.06,.08);belly=vec3(.25,.27,.30);fins=vec3(.10,.10,.12);sheen=.5;}
	float height=shape.y/max(.02,.125*sin(3.1416*clamp((.5-shape.z)/.8,.05,1.0)));
	vec3 colour=mix(belly,back,smoothstep(-.3,.45,height));
	vec3 glow=vec3(0.0);
	if(kind==3)colour*=.8+.25*sin(shape.z*40.0)*sin(shape.y*55.0+shape.z*13.0);
	if(kind==4)colour=mix(colour,vec3(.04),step(.55,fract(shape.z*5.0+.2))*step(shape.z,.3)*.9);
	if(kind==6)glow=vec3(.10,.60,.90)*(1.0-smoothstep(.08,.22,abs(height-.15)))*step(shape.z,.42);
	if(kind==7)glow=vec3(.10,.50,.70)*step(height,-.35)*step(fract(shape.z*14.0),.35);
	colour=mix(colour,fins,fin);
	glow*=1.0-fin;
	// Each school or fish is a little warmer or cooler than the next.
	colour*=mix(vec3(.88,.95,1.08),vec3(1.10,1.0,.86),variant);
	float eye=1.0-smoothstep(.012,.02,length(vec2(shape.z-.39,shape.y-.025)));
	colour*=1.0-.85*eye*(1.0-fin);
	ALBEDO=colour;
	METALLIC=sheen*(1.0-fin);
	ROUGHNESS=mix(.32,.65,fin);
	// Scales catch what little light there is, so a school glints at the
	// edge of sight instead of vanishing into the water.
	float rim=1.0-clamp(abs(dot(NORMAL,VIEW)),0.0,1.0);
	EMISSION=(colour*.12+vec3(.16,.2,.22)*rim*rim)*(1.0-.6*fin)+glow;
}
