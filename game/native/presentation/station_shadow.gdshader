shader_type spatial;
render_mode unshaded, cull_disabled;

uniform mat4 source_bones[64];
uniform sampler2D albedo_crisp : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D albedo_smooth : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 texture_size = vec2(1.0);
uniform bool smoothed = false;
uniform float hangar_open = 0.0;
uniform float stream_visibility = 1.0;

void vertex() {
	mat4 bone = source_bones[int(UV2.x + 0.5)];
	VERTEX = (bone * vec4(VERTEX, 1.0)).xyz;
	// Keep normal bias identical to the visible material, including shears.
	vec3 n = mat3(bone) * NORMAL;
	if (abs(determinant(mat3(bone))) > 0.000001) { n = transpose(inverse(mat3(bone))) * NORMAL; }
	NORMAL = length(n) > 0.00001 ? normalize(n) : vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// Match the visible material's side-sliding door and palette cutouts.
	#ifdef HANGAR_DOOR
	bool panel = UV.x > 49.5 && UV.x < 59.5 && UV.y > 98.5 && UV.y < 108.5;
	if (panel && hangar_open > 0.0 && abs(UV.y - 103.5) < 5.0 * hangar_open) { discard; }
	#endif
	float threshold = fract(52.9829189 * fract(dot(floor(FRAGCOORD.xy), vec2(0.06711056, 0.00583715))));
	if (stream_visibility <= threshold) { discard; }
	#ifdef PALETTE_CUTOUT
		vec2 uv = UV;
		#ifdef HANGAR_DOOR
		if (panel) { uv.y -= sign(UV.y - 103.5) * 5.0 * hangar_open; }
		float snap = 0.5;
		#else
		float snap = 0.0001;
		#endif
		vec4 color;
		if (smoothed) { color = texture(albedo_smooth, (uv + vec2(0.5)) / texture_size); }
		else { color = texture(albedo_crisp, (floor(uv + vec2(snap)) + vec2(0.5)) / texture_size); }
		if (color.a < 0.5 || all(greaterThanEqual(color.rgb, vec3(0.97)))) { discard; }
	#endif
}
