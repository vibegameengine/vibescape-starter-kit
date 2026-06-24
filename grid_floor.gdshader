shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Unreal-style blueprint grid floor.
// Grid math is the "Pristine Grid" by Ben Golus (derivative-based AA, moire-safe):
//   https://bgolus.medium.com/the-best-darn-grid-shader-yet-727f9278b9d8
// UVs are taken from WORLD XZ so the grid is world-locked like UE's WorldGridMaterial,
// independent of mesh UVs or plane size.

uniform vec3 base_color : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 line_color : source_color = vec3(0.62, 0.64, 0.70);
uniform vec3 major_line_color : source_color = vec3(0.80, 0.82, 0.88);
uniform float fine_cell = 1.0;     // metres per fine cell
uniform float major_cell = 10.0;   // metres per major cell
uniform float fine_width : hint_range(0.0, 0.5) = 0.015;
uniform float major_width : hint_range(0.0, 0.5) = 0.022;
uniform float floor_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float floor_metallic : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Returns line coverage in [0,1] for a unit-period grid at `uv`, `line_width` per axis.
float pristine_grid(vec2 uv, vec2 line_width) {
	vec4 uvDDXY = vec4(dFdx(uv), dFdy(uv));
	vec2 uvDeriv = vec2(length(uvDDXY.xz), length(uvDDXY.yw));
	bvec2 invertLine = bvec2(line_width.x > 0.5, line_width.y > 0.5);
	vec2 targetWidth = vec2(
		invertLine.x ? 1.0 - line_width.x : line_width.x,
		invertLine.y ? 1.0 - line_width.y : line_width.y);
	vec2 drawWidth = clamp(targetWidth, uvDeriv, vec2(0.5));
	vec2 lineAA = uvDeriv * 1.5;
	vec2 gridUV = abs(fract(uv) * 2.0 - 1.0);
	gridUV.x = invertLine.x ? gridUV.x : 1.0 - gridUV.x;
	gridUV.y = invertLine.y ? gridUV.y : 1.0 - gridUV.y;
	vec2 grid2 = smoothstep(drawWidth + lineAA, drawWidth - lineAA, gridUV);
	grid2 *= clamp(targetWidth / drawWidth, 0.0, 1.0);
	grid2 = mix(grid2, targetWidth, clamp(uvDeriv * 2.0 - 1.0, 0.0, 1.0));
	grid2.x = invertLine.x ? 1.0 - grid2.x : grid2.x;
	grid2.y = invertLine.y ? 1.0 - grid2.y : grid2.y;
	return mix(grid2.x, 1.0, grid2.y);
}

void fragment() {
	vec2 uv_fine = world_pos.xz / fine_cell;
	vec2 uv_major = world_pos.xz / major_cell;
	float g_fine = pristine_grid(uv_fine, vec2(fine_width));
	float g_major = pristine_grid(uv_major, vec2(major_width));

	vec3 col = base_color;
	col = mix(col, line_color, g_fine);
	col = mix(col, major_line_color, g_major);

	ALBEDO = col;
	ROUGHNESS = floor_roughness;
	METALLIC = floor_metallic;
}
