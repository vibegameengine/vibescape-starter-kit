shader_type spatial;
// Volumetric clouds as a SEPARATE overlay (not the sky). Rendered on an inverted
// sky-dome that follows the camera: the same HZD raymarch, but output as a premul-
// alpha layer composited OVER the atmosphere sky and occluded by scene geometry.
// Sun comes from uniforms (a spatial shader has no LIGHT0_* sky builtins).
// Ported/adapted from clayjohn's godot-volumetric-cloud-demo (MIT). See docs/CREDITS.md.
render_mode unshaded, blend_premul_alpha, cull_front, depth_draw_never,
	shadows_disabled, fog_disabled, specular_disabled;

uniform sampler3D worlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler3D perlworlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler2D weathermap : filter_linear_mipmap, repeat_enable;

// The sun, fed by the VolumetricClouds node from the scene's DirectionalLight.
// sun_direction is the direction the light travels (points away from the sun).
uniform vec3 sun_direction = vec3(0.0, -0.5, -0.5);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_energy = 1.0;

uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_speed : hint_range(0.0, 20.0) = 1.0;
uniform float turbulence_speed : hint_range(0.0, 4.0) = 1.0;
uniform float march_steps_horizon : hint_range(16.0, 256.0) = 160.0;
uniform float march_steps_zenith : hint_range(16.0, 256.0) = 64.0;
uniform float _density : hint_range(0.01, 0.2) = 0.05;
uniform float cloud_coverage : hint_range(0.1, 1.0) = 0.4;
uniform float _time_offset : hint_range(0.0, 1000.0, 0.5) = 0.0;
uniform float rayleigh : hint_range(0, 64) = 2.0;
uniform vec4 rayleigh_color : source_color = vec4(0.26, 0.41, 0.58, 1.0);
uniform float mie : hint_range(0, 1) = 0.005;
uniform float mie_eccentricity : hint_range(-1, 1) = 0.8;
uniform vec4 mie_color : source_color = vec4(0.63, 0.77, 0.92, 1.0);
uniform float turbidity : hint_range(0, 1000) = 10.0;
uniform float sun_disk_scale : hint_range(0, 360) = 1.0;
uniform vec4 ground_color : source_color = vec4(1.0);
uniform float exposure : hint_range(0, 128) = 0.1;
uniform float sun_anisotropy : hint_range(0.0, 0.95) = 0.5;

const float g_radius = 6000000.0;
// Cloud-shell radii are uniforms so the node can raise/lower the deck ("height").
uniform float sky_b_radius = 6001500.0;
uniform float sky_t_radius = 6004000.0;
const float SOL_SIZE = 0.00872663806;
const float SUN_ENERGY = 1000.0;
const float rayleigh_zenith_size = 8.4e3;
const float mie_zenith_size = 1.25e3;
const vec3 UP = vec3(0.0, 1.0, 0.0);

varying vec3 v_dir;

float remap(float v, float omin, float omax, float nmin, float nmax) {
	return nmin + (((v - omin) / (omax - omin)) * (nmax - nmin));
}

float henyey_greenstein(float cos_theta, float g) {
	const float k = 0.0795774715459;
	return k * (1.0 - g * g) / (pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

float GetHeightFractionForPoint(float inPosition) {
	float height_fraction = (inPosition - sky_b_radius) / (sky_t_radius - sky_b_radius);
	return clamp(height_fraction, 0.0, 1.0);
}

float intersectSphere(vec3 pos, vec3 dir, float r) {
	float a = dot(dir, dir);
	float b = 2.0 * dot(dir, pos);
	float c = dot(pos, pos) - (r * r);
	float d = sqrt((b * b) - 4.0 * a * c);
	float p = -b - d;
	float p2 = -b + d;
	return max(p, p2) / (2.0 * a);
}

vec3 atmosphere(vec3 eye_dir) {
	float zenith_angle = clamp(dot(UP, normalize(sun_direction)), -1.0, 1.0);
	float sun_e = max(0.0, 1.0 - exp(-((PI * 0.5) - acos(zenith_angle)))) * SUN_ENERGY * sun_energy;
	float sun_fade = 1.0 - clamp(1.0 - exp(sun_direction.y), 0.0, 1.0);
	float rayleigh_coefficient = rayleigh - (1.0 * (1.0 - sun_fade));
	vec3 rayleigh_beta = rayleigh_coefficient * rayleigh_color.rgb * 0.0001;
	vec3 mie_beta = turbidity * mie * mie_color.rgb * 0.000434;
	float zenith = acos(max(0.0, dot(UP, eye_dir)));
	float optical_mass = 1.0 / (cos(zenith) + 0.15 * pow(93.885 - degrees(zenith), -1.253));
	float rayleigh_scatter = rayleigh_zenith_size * optical_mass;
	float mie_scatter = mie_zenith_size * optical_mass;
	vec3 extinction = exp(-(rayleigh_beta * rayleigh_scatter + mie_beta * mie_scatter));
	float cos_theta = dot(eye_dir, normalize(sun_direction));
	float rayleigh_phase = (3.0 / (16.0 * PI)) * (1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));
	vec3 betaRTheta = rayleigh_beta * rayleigh_phase;
	float mie_phase = henyey_greenstein(cos_theta, mie_eccentricity);
	vec3 betaMTheta = mie_beta * mie_phase;
	vec3 Lin = pow(sun_e * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * (1.0 - extinction), vec3(1.5));
	Lin *= mix(vec3(1.0), pow(sun_e * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * extinction, vec3(0.5)), clamp(pow(1.0 - zenith_angle, 5.0), 0.0, 1.0));
	Lin *= mix(ground_color.rgb, vec3(1.0), smoothstep(-0.1, 0.1, dot(UP, eye_dir)));
	float sunAngularDiameterCos = cos(SOL_SIZE * sun_disk_scale);
	float sunAngularDiameterCos2 = cos(SOL_SIZE * sun_disk_scale * 0.5);
	float sundisk = smoothstep(sunAngularDiameterCos, sunAngularDiameterCos2, cos_theta);
	vec3 L0 = (sun_e * 1900.0 * extinction) * sundisk * sun_color;
	vec3 color = (Lin + L0) * 0.04;
	color = pow(color, vec3(1.0 / (1.2 + (1.2 * sun_fade))));
	color *= exposure;
	return color;
}

vec4 mixGradients(float cloudType) {
	const vec4 STRATUS_GRADIENT = vec4(0.02, 0.05, 0.09, 0.11);
	const vec4 STRATOCUMULUS_GRADIENT = vec4(0.02, 0.2, 0.48, 0.625);
	const vec4 CUMULUS_GRADIENT = vec4(0.01, 0.0625, 0.78, 1.0);
	float stratus = 1.0 - clamp(cloudType * 2.0, 0.0, 1.0);
	float stratocumulus = 1.0 - abs(cloudType - 0.5) * 2.0;
	float cumulus = clamp(cloudType - 0.5, 0.0, 1.0) * 2.0;
	return STRATUS_GRADIENT * stratus + STRATOCUMULUS_GRADIENT * stratocumulus + CUMULUS_GRADIENT * cumulus;
}

float densityHeightGradient(float heightFrac, float cloudType) {
	vec4 cloudGradient = mixGradients(cloudType);
	return smoothstep(cloudGradient.x, cloudGradient.y, heightFrac) - smoothstep(cloudGradient.z, cloudGradient.w, heightFrac);
}

float density(vec3 pip, vec3 weather, float mip) {
	float time = TIME;
	vec3 p = pip;
	float height_fraction = GetHeightFractionForPoint(length(p));
	p.xz += time * 20.0 * normalize(wind_direction) * wind_speed * 0.6;

	vec4 n = textureLod(perlworlnoise, p.xyz * 0.00008, mip - 2.0);
	float fbm = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;

	float g = densityHeightGradient(height_fraction, weather.r);
	float base_cloud = remap(n.r, -(1.0 - fbm), 1.0, 0.0, 1.0);
	float weather_coverage = cloud_coverage * weather.b;
	base_cloud = remap(base_cloud * g, 1.0 - (weather_coverage), 1.0, 0.0, 1.0);
	base_cloud *= weather_coverage;

	p.xz -= time * normalize(wind_direction) * 40.0 * turbulence_speed;
	p.y -= time * 40.0 * turbulence_speed;
	vec3 hn = textureLod(worlnoise, p * 0.001, mip).rgb;
	float hfbm = hn.r * 0.625 + hn.g * 0.25 + hn.b * 0.125;
	hfbm = mix(hfbm, 1.0 - hfbm, clamp(height_fraction * 4.0, 0.0, 1.0));
	float detail = clamp(1.0 - mip * 0.2, 0.15, 1.0);
	base_cloud = remap(base_cloud, hfbm * 0.4 * height_fraction * detail, 1.0, 0.0, 1.0);

	base_cloud = clamp(base_cloud, 0.0, 1.0);
	// Edge band-limit (anti-shimmer): soften the near-binary silhouette so it spans a
	// few rays instead of snapping — deterministic, no derivatives.
	base_cloud = smoothstep(0.0, 0.18, base_cloud) * base_cloud;

	return pow(base_cloud, (1.0 - height_fraction) * 0.8 + 0.5);
}

vec4 march(vec3 pos, vec3 dir_step, int depth) {
	const vec3 RANDOM_VECTORS[6] = {
		vec3(0.38051305, 0.92453449, -0.02111345),
		vec3(-0.50625799, -0.03590792, -0.86163418),
		vec3(-0.32509218, -0.94557439, 0.01428793),
		vec3(0.09026238, -0.27376545, 0.95755165),
		vec3(0.28128598, 0.42443639, -0.86065785),
		vec3(-0.16852403, 0.14748697, 0.97460106)};

	float T = 1.0;
	float alpha = 0.0;
	float ss = length(dir_step);
	vec3 dir = normalize(dir_step);
	float lod = clamp(log2(ss / 60.0), 0.0, 5.0);
	vec3 p = pos;

	float t_dist = sky_t_radius - sky_b_radius;
	float lss = (t_dist / 36.0);
	vec3 ldir = normalize(sun_direction);
	vec3 L = vec3(0.0);
	float costheta = dot(ldir, dir);

	vec3 atmosphere_sun = atmosphere(sun_direction) * ss * 0.030;
	vec3 atmosphere_ambient = atmosphere(normalize(vec3(1.0, 1.0, 0.0)));
	vec3 atmosphere_ground = atmosphere(normalize(vec3(1.0, -1.0, 0.0)));

	const float weather_scale = 0.00006;
	float time = TIME * 0.001 + 0.005 * _time_offset;
	vec2 weather_pos = time * normalize(wind_direction) * wind_speed;

	for (int i = 0; i < depth; i++) {
		p += dir * ss;
		vec3 weather_sample = textureLod(weathermap, p.xz * weather_scale + 0.5 + weather_pos, 0.0).xyz;
		float height_fraction = GetHeightFractionForPoint(length(p));

		float t = density(p, weather_sample, lod);
		float dt = exp(-_density * t * ss);
		T *= dt;

		if (T < 0.01) {
			break;
		}

		if (t > 0.0) {
			vec3 lp = p;
			float cd = 0.0;
			for (int j = 0; j < 6; j++) {
				lp += (ldir + RANDOM_VECTORS[j] * float(j)) * lss;
				vec3 lweather = textureLod(weathermap, lp.xz * weather_scale + 0.5 + weather_pos, 0.0).xyz;
				float lt = density(lp, lweather, float(j));
				cd += lt;
			}

			lp = p + ldir * 18.0 * lss;
			float lheight_fraction = GetHeightFractionForPoint(length(lp));
			vec3 lweather = textureLod(weathermap, lp.xz * weather_scale + 0.5, 0.0).xyz;
			float lt = pow(density(lp, lweather, 5.0), (1.0 - lheight_fraction) * 0.8 + 0.5);
			cd += lt;

			vec3 sun_lum = vec3(0.0);
			float ms_a = 1.0;
			float ms_b = 1.0;
			float ms_c = 1.0;
			for (int o = 0; o < 3; o++) {
				float beers = exp(-_density * cd * lss * ms_a);
				float oph = max(henyey_greenstein(costheta, sun_anisotropy * ms_c),
					henyey_greenstein(costheta, -0.2 * ms_c));
				sun_lum += ms_b * beers * oph * atmosphere_sun * 0.7;
				ms_a *= 0.45;
				ms_b *= 0.55;
				ms_c *= 0.5;
			}

			vec3 ambient = mix(atmosphere_ground, vec3(1.0),
				smoothstep(0.0, 1.0, height_fraction)) * _density * 13.0 *
				mix(atmosphere_ambient, vec3(1.0), 0.6) * max(-sun_direction.y, 0.9);

			alpha += (1.0 - dt) * (1.0 - alpha);
			L += (ambient + sun_lum * alpha) * T * t;
		}
	}
	return clamp(vec4(L, alpha), 0.0, 1.0);
}

void vertex() {
	// Direction from the camera through this dome vertex (the dome follows the camera).
	v_dir = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	vec3 dir = normalize(v_dir);
	if (dir.y <= 0.0) {
		ALBEDO = vec3(0.0);
		ALPHA = 0.0;
	} else {
		vec3 camPos = vec3(0.0, g_radius, 0.0);
		vec3 start = camPos + dir * intersectSphere(camPos, dir, sky_b_radius);
		vec3 end = camPos + dir * intersectSphere(camPos, dir, sky_t_radius);
		float shelldist = length(end - start);

		float steps = mix(march_steps_horizon, march_steps_zenith,
			clamp(dir.y, 0.0, 1.0));
		vec3 raystep = dir * shelldist / steps;
		vec4 volume = march(start, raystep, int(steps));

		// Fade the layer out at the very horizon so its edge isn't a hard line.
		float fade = 1.0 - smoothstep(0.82, 1.0, 1.0 - dir.y);
		// volume.xyz is premultiplied by coverage already (matches the old sky composite).
		ALBEDO = volume.xyz * fade;
		ALPHA = volume.a * fade;
	}
}
