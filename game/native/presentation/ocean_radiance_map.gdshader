shader_type canvas_item;
render_mode unshaded, blend_disabled;
#include "res://native/presentation/ocean_radiance.gdshaderinc"
void fragment(){
 COLOR=vec4(ocean_radiance_exact(ocean_uv_direction(UV)),1.0);
}
