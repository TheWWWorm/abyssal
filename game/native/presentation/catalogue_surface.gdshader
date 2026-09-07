shader_type spatial;
render_mode cull_back;
#include "res://native/presentation/ocean_background.gdshaderinc"
uniform bool ocean_haze=false;
uniform sampler2D surface_albedo : source_color,filter_linear_mipmap_anisotropic,repeat_disable;
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform float metallic_value=0.28;
uniform float roughness_value=0.62;
uniform float biology=0.0;
uniform float swim_mode=0.0;
uniform float body_length=10.0;
uniform float body_width=5.0;
varying vec3 rest_normal;
void vertex(){
 rest_normal=NORMAL;
 float tail=clamp(VERTEX.z/max(body_length*0.5,0.1),0.0,1.0);
 if(swim_mode==1.0){VERTEX.x+=sin(TIME*2.0-VERTEX.z*0.6)*tail*tail*body_length*0.035;}
 if(swim_mode==2.0){float wing=pow(clamp(abs(VERTEX.x)/max(body_width*.5,.1),0.0,1.0),2.0);VERTEX.y+=sin(TIME*1.5-abs(VERTEX.x)*.35)*wing*body_width*.08;}
 if(swim_mode==3.0){float height=max(0.0,VERTEX.y);VERTEX.x+=sin(TIME*.65+VERTEX.y*.7+VERTEX.z)*height*.06;VERTEX.z+=cos(TIME*.51+VERTEX.y*.5)*height*.035;}
 // Nautilus shell, collar and eyes stay rigid; only distal tentacles sway.
 if(swim_mode==5.0){float tip=smoothstep(2.35,4.1,-VERTEX.z);VERTEX.x+=sin(TIME*1.3-VERTEX.z*2.0)*tip*.10;}
 if(swim_mode==4.0){VERTEX.x+=sin(TIME*1.3+VERTEX.z*1.8)*tail*body_length*.025;}
}
void fragment(){
 FOG=vec4(0.0);
 vec3 color=texture(surface_albedo,UV).rgb*surface_tint.rgb;
 ALBEDO=color;
 METALLIC=metallic_value;
 float value=dot(color,vec3(.2126,.7152,.0722));
 ROUGHNESS=clamp(roughness_value+(value-.1)*.4,.24,.92);
 SPECULAR=.38;
 // Fine surface relief is derived in the actual geometric tangent frame.
 // It follows the generated paint/skin instead of drawing arbitrary panels.
 float h=value*mix(.028,.016,biology);
 vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX),r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);
 float det=dot(dx,r1);
 if(abs(det)>.000001)NORMAL=normalize(abs(det)*NORMAL-sign(det)*(dFdx(h)*r1+dFdy(h)*r2));
 BACKLIGHT=color*.12*biology;
 if(ocean_haze){
  vec3 ray=normalize((INV_VIEW_MATRIX*vec4(VERTEX,0.0)).xyz);
  FOG=ocean_fog(ray,length(VERTEX),.00020);
 }

}
