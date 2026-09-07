shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
void vertex(){
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 MODELVIEW_MATRIX=MODELVIEW_MATRIX*mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0),vec4(0,length(MODEL_MATRIX[1].xyz),0,0),vec4(0,0,length(MODEL_MATRIX[2].xyz),0),vec4(0,0,0,1));
}
void fragment(){
 vec2 p=UV*2.0-1.0;float r=length(p);
 float body=exp(-r*r*5.0)*(1.0-smoothstep(.65,1.0,r));
 float ring=0.0;
 ALBEDO=COLOR.rgb;ALPHA=(body+ring)*COLOR.a;
}
