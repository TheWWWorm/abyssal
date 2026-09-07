shader_type sky;
#include "res://native/presentation/ocean_background.gdshaderinc"
void sky(){
 COLOR=ocean_background(EYEDIR);
 // GLES approximates the sky's sRGB round trip. Feed the background through
 // the linear custom-fog input so deep shadows match spatial ocean fog.
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 FOG=vec4(ocean_radiance(EYEDIR),1.0);
 #endif
}
