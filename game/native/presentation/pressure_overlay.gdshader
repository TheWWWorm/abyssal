shader_type canvas_item;
uniform float strength=0.0;
uniform vec4 warning_color : source_color=vec4(0.42,0.09,0.035,1.0);
void fragment(){
	vec2 p=abs(UV*2.0-1.0);
	float edge=smoothstep(0.5,1.0,max(p.x,p.y));
	COLOR=vec4(warning_color.rgb*0.45,edge*strength);
}
