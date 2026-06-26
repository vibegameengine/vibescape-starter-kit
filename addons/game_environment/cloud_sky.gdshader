shader_type sky;
// Volumetric clouds rendered AS the sky. The cloud model (atmosphere / density / march /
// phase / horizon fade) is a 1:1 port of clayjohn's godot-volumetric-cloud-demo (MIT) —
// see THIRDPARTY.md. The ONLY additions are: (a) a multi-layer wrapper so several decks
// (CloudLayer nodes) can stack, each with its own height/coverage/density/brightness/wind;
// (b) the visible background uses GameWorld's gradient sky instead of the Nishita
// atmosphere, so the horizon haze matches the rest of the environment.
//
// Sun comes from the scene's DirectionalLight via the built-in LIGHT0_* (no manual feed).

const int MAX_LAYERS = 4;

// --- Visible sky gradient (replicates GameWorld's ProceduralSkyMaterial) --------------
uniform vec3 sky_top_color : source_color = vec3(0.07, 0.28, 0.72);
uniform vec3 sky_horizon_color : source_color = vec3(0.84, 0.87, 0.91);
uniform vec3 ground_horizon_color : source_color = vec3(0.84, 0.87, 0.91);
uniform vec3 ground_bottom_color : source_color = vec3(0.6, 0.62, 0.64);
uniform float sky_curve = 0.1;
uniform float ground_curve = 0.02;
uniform float sky_energy = 1.0;

// --- Cloud decks (filled from CloudLayer nodes, sorted highest -> lowest) --------------
uniform int layer_count = 0;
uniform float layer_b_radius[MAX_LAYERS];
uniform float layer_t_radius[MAX_LAYERS];
uniform float layer_coverage[MAX_LAYERS];
uniform float layer_density[MAX_LAYERS];
uniform float layer_brightness[MAX_LAYERS];   // == clayjohn's `exposure`, per deck
uniform vec2 layer_wind[MAX_LAYERS];
uniform float layer_wind_speed[MAX_LAYERS];
uniform float layer_turbulence[MAX_LAYERS];
// 0 = clayjohn's directional phase (bright toward the sun, darker away); 1 = flat/uniform.
uniform float layer_spread[MAX_LAYERS];

uniform float march_steps_horizon : hint_range(16.0, 256.0) = 96.0;
uniform float march_steps_zenith : hint_range(16.0, 256.0) = 54.0;
uniform float _time_offset = 0.0;

uniform sampler3D worlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler3D perlworlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler2D weathermap : filter_linear_mipmap, repeat_enable;

// Atmosphere tint for the in-cloud lighting (clayjohn's Nishita model; NOT the visible sky).
uniform float rayleigh : hint_range(0, 64) = 2.0;
uniform vec4 rayleigh_color : source_color = vec4(0.26, 0.41, 0.58, 1.0);
uniform float mie : hint_range(0, 1) = 0.005;
uniform float mie_eccentricity : hint_range(-1, 1) = 0.8;
uniform vec4 mie_color : source_color = vec4(0.63, 0.77, 0.92, 1.0);
uniform float turbidity : hint_range(0, 1000) = 10.0;
uniform float sun_disk_scale : hint_range(0, 360) = 1.0;
uniform vec4 ground_color : source_color = vec4(1.0);

const float g_radius = 6000000.0;
const vec3 UP = vec3(0.0, 1.0, 0.0);
const float SOL_SIZE = 0.00872663806;
const float SUN_ENERGY = 1000.0;
const float rayleigh_zenith_size = 8.4e3;
const float mie_zenith_size = 1.25e3;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float remap(float v, float omin, float omax, float nmin, float nmax) {
	return nmin + (((v - omin) / (omax - omin)) * (nmax - nmin));
}

float henyey_greenstein(float cos_theta, float g) {
	const float k = 0.0795774715459;
	return k * (1.0 - g * g) / (pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

// clayjohn's Nishita atmosphere, used ONLY to tint the cloud lighting. The final `* exposure`
// is dropped here; per-deck brightness is applied to the marched result instead (identical
// math, since the lighting is linear in this output).
vec3 atmosphere(vec3 eye_dir) {
	float zenith_angle = clamp(dot(UP, normalize(LIGHT0_DIRECTION)), -1.0, 1.0);
	float sun_energy = max(0.0, 1.0 - exp(-((PI * 0.5) - acos(zenith_angle)))) * SUN_ENERGY * LIGHT0_ENERGY;
	float sun_fade = 1.0 - clamp(1.0 - exp(LIGHT0_DIRECTION.y), 0.0, 1.0);
	float rayleigh_coefficient = rayleigh - (1.0 * (1.0 - sun_fade));
	vec3 rayleigh_beta = rayleigh_coefficient * rayleigh_color.rgb * 0.0001;
	vec3 mie_beta = turbidity * mie * mie_color.rgb * 0.000434;
	float zenith = acos(max(0.0, dot(UP, eye_dir)));
	float optical_mass = 1.0 / (cos(zenith) + 0.15 * pow(93.885 - degrees(zenith), -1.253));
	float rayleigh_scatter = rayleigh_zenith_size * optical_mass;
	float mie_scatter = mie_zenith_size * optical_mass;
	vec3 extinction = exp(-(rayleigh_beta * rayleigh_scatter + mie_beta * mie_scatter));
	float cos_theta = dot(eye_dir, normalize(LIGHT0_DIRECTION));
	float rayleigh_phase = (3.0 / (16.0 * PI)) * (1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));
	vec3 betaRTheta = rayleigh_beta * rayleigh_phase;
	float mie_phase = henyey_greenstein(cos_theta, mie_eccentricity);
	vec3 betaMTheta = mie_beta * mie_phase;
	vec3 Lin = pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * (1.0 - extinction), vec3(1.5));
	Lin *= mix(vec3(1.0), pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * extinction, vec3(0.5)), clamp(pow(1.0 - zenith_angle, 5.0), 0.0, 1.0));
	Lin *= mix(ground_color.rgb, vec3(1.0), smoothstep(-0.1, 0.1, dot(UP, eye_dir)));
	float sunAngularDiameterCos = cos(SOL_SIZE * sun_disk_scale);
	float sunAngularDiameterCos2 = cos(SOL_SIZE * sun_disk_scale * 0.5);
	float sundisk = smoothstep(sunAngularDiameterCos, sunAngularDiameterCos2, cos_theta);
	vec3 L0 = (sun_energy * 1900.0 * extinction) * sundisk * LIGHT0_COLOR;
	vec3 color = (Lin + L0) * 0.04;
	return pow(color, vec3(1.0 / (1.2 + (1.2 * sun_fade))));
}

float GetHeightFractionForPoint(float inPos, float b_rad, float t_rad) {
	return clamp((inPos - b_rad) / (t_rad - b_rad), 0.0, 1.0);
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
	vec4 cg = mixGradients(cloudType);
	return smoothstep(cg.x, cg.y, heightFrac) - smoothstep(cg.z, cg.w, heightFrac);
}

float intersectSphere(vec3 pos, vec3 dir, float r) {
	float a = dot(dir, dir);
	float b = 2.0 * dot(dir, pos);
	float c = dot(pos, pos) - (r * r);
	float d = sqrt((b * b) - 4.0 * a * c);
	return max(-b - d, -b + d) / (2.0 * a);
}

float density(vec3 pip, vec3 weather, float mip, float b_rad, float t_rad,
		float coverage, vec2 wdir, float wspd, float turb) {
	float time = TIME;
	vec3 p = pip;
	float height_fraction = GetHeightFractionForPoint(length(p), b_rad, t_rad);
	p.xz += time * 20.0 * normalize(wdir) * wspd * 0.6;
	vec4 n = textureLod(perlworlnoise, p.xyz * 0.00008, mip - 2.0);
	float fbm = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;
	float g = densityHeightGradient(height_fraction, weather.r);
	float base_cloud = remap(n.r, -(1.0 - fbm), 1.0, 0.0, 1.0);
	float weather_coverage = coverage * weather.b;
	base_cloud = remap(base_cloud * g, 1.0 - weather_coverage, 1.0, 0.0, 1.0);
	base_cloud *= weather_coverage;
	p.xz -= time * normalize(wdir) * 40.0 * turb;
	p.y -= time * 40.0 * turb;
	vec3 hn = textureLod(worlnoise, p * 0.001, mip).rgb;
	float hfbm = hn.r * 0.625 + hn.g * 0.25 + hn.b * 0.125;
	hfbm = mix(hfbm, 1.0 - hfbm, clamp(height_fraction * 4.0, 0.0, 1.0));
	base_cloud = remap(base_cloud, hfbm * 0.4 * height_fraction, 1.0, 0.0, 1.0);
	return pow(clamp(base_cloud, 0.0, 1.0), (1.0 - height_fraction) * 0.8 + 0.5);
}

vec4 march(vec3 pos, vec3 dir_step, int depth, float b_rad, float t_rad, float coverage,
		float den, float bri, vec2 wdir, float wspd, float turb, float spread) {
	const vec3 RV[6] = {vec3(0.38051305, 0.92453449, -0.02111345), vec3(-0.50625799, -0.03590792, -0.86163418),
		vec3(-0.32509218, -0.94557439, 0.01428793), vec3(0.09026238, -0.27376545, 0.95755165),
		vec3(0.28128598, 0.42443639, -0.86065785), vec3(-0.16852403, 0.14748697, 0.97460106)};
	float T = 1.0;
	float alpha = 0.0;
	float ss = length(dir_step);
	vec3 dir = normalize(dir_step);
	vec3 p = pos + dir * hash(pos * 10.0) * ss;
	float lss = (t_rad - b_rad) / 36.0;
	vec3 ldir = normalize(LIGHT0_DIRECTION);
	vec3 L = vec3(0.0);
	float costheta = dot(ldir, dir);
	// clayjohn's multi-lobe phase, but `spread` flattens it: 0 = directional (bright toward
	// the sun, darker away); 1 = isotropic (evenly lit clouds).
	float k = 1.0 - clamp(spread, 0.0, 1.0);
	float phase = max(max(henyey_greenstein(costheta, 0.6 * k),
		henyey_greenstein(costheta, (0.4 - 1.4 * ldir.y) * k)), henyey_greenstein(costheta, -0.2 * k));

	vec3 atmosphere_sun = atmosphere(LIGHT0_DIRECTION) * LIGHT0_ENERGY * ss * 0.1;
	vec3 atmosphere_ambient = atmosphere(normalize(vec3(1.0, 1.0, 0.0)));
	vec3 atmosphere_ground = atmosphere(normalize(vec3(1.0, -1.0, 0.0)));

	const float wscale = 0.00006;
	float time = TIME * 0.001 + 0.005 * _time_offset;
	vec2 wpos = time * normalize(wdir) * wspd;

	for (int i = 0; i < depth; i++) {
		p += dir * ss;
		vec3 weather_sample = texture(weathermap, p.xz * wscale + 0.5 + wpos).xyz;
		float height_fraction = GetHeightFractionForPoint(length(p), b_rad, t_rad);
		float t = density(p, weather_sample, 0.0, b_rad, t_rad, coverage, wdir, wspd, turb);
		float dt = exp(-den * t * ss);
		T *= dt;
		if (t > 0.0) {
			vec3 lp = p;
			float cd = 0.0;
			for (int j = 0; j < 6; j++) {
				lp += (ldir + RV[j] * float(j)) * lss;
				vec3 lweather = texture(weathermap, lp.xz * wscale + 0.5 + wpos).xyz;
				cd += density(lp, lweather, float(j), b_rad, t_rad, coverage, wdir, wspd, turb);
			}
			lp = p + ldir * 18.0 * lss;
			float lheight_fraction = GetHeightFractionForPoint(length(lp), b_rad, t_rad);
			vec3 lweather = texture(weathermap, lp.xz * wscale + 0.5).xyz;
			cd += pow(density(lp, lweather, 5.0, b_rad, t_rad, coverage, wdir, wspd, turb), (1.0 - lheight_fraction) * 0.8 + 0.5);

			float beers = exp(-den * cd * lss);
			float beers2 = exp(-den * cd * lss * 0.25) * 0.7;
			float beers_total = max(beers, beers2);

			vec3 ambient = mix(atmosphere_ground, vec3(1.0), smoothstep(0.0, 1.0, height_fraction)) *
				den * mix(atmosphere_ambient, vec3(1.0), 0.4) * LIGHT0_DIRECTION.y;
			alpha += (1.0 - dt) * (1.0 - alpha);
			L += (ambient + beers_total * atmosphere_sun * phase * alpha) * T * t;
		}
	}
	return clamp(vec4(L * bri, alpha), 0.0, 1.0);
}

vec4 march_layer(vec3 dir, int i) {
	float b = layer_b_radius[i];
	float t = layer_t_radius[i];
	vec3 cam = vec3(0.0, g_radius, 0.0);
	vec3 start = cam + dir * intersectSphere(cam, dir, b);
	vec3 end = cam + dir * intersectSphere(cam, dir, t);
	float shelldist = length(end - start);
	float steps = mix(march_steps_horizon, march_steps_zenith, clamp(dir.y, 0.0, 1.0));
	vec3 rstep = dir * shelldist / steps;
	return march(start, rstep, int(steps), b, t, layer_coverage[i], layer_density[i],
		layer_brightness[i], layer_wind[i], layer_wind_speed[i], layer_turbulence[i], layer_spread[i]);
}

vec3 gradient_sky(vec3 dir) {
	float v_angle = acos(clamp(dir.y, -1.0, 1.0));
	vec3 col;
	if (dir.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		col = mix(sky_horizon_color, sky_top_color,
			clamp(1.0 - pow(1.0 - c, 1.0 / max(sky_curve, 0.001)), 0.0, 1.0));
	} else {
		float c = 1.0 - (PI - v_angle) / (PI * 0.5);
		col = mix(ground_horizon_color, ground_bottom_color,
			clamp(1.0 - pow(1.0 - c, 1.0 / max(ground_curve, 0.001)), 0.0, 1.0));
	}
	return col * sky_energy;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 background = gradient_sky(dir);
	// Soft sun on the visible sky (LIGHT0_DIRECTION points toward the sun): a soft-edged
	// core + a gentle halo, kept modest so it doesn't bloom-wash the horizon haze.
	float sd = dot(dir, normalize(LIGHT0_DIRECTION));
	float sun_core = smoothstep(0.9972, 0.9996, sd);
	float sun_halo = pow(max(sd, 0.0), 360.0);
	background += LIGHT0_COLOR * LIGHT0_ENERGY * (sun_core * 3.0 + sun_halo * 0.5);

	vec3 c = background;
	if (dir.y > 0.0) {
		for (int i = 0; i < layer_count; i++) {
			vec4 v = march_layer(dir, i);
			c = c * (1.0 - v.a) + v.rgb;  // v.rgb is premultiplied
		}
		// clayjohn's horizon fade: blend clouds back to the sky as they near the horizon,
		// so decks never pile up / blow out along the horizon line.
		c = mix(clamp(c, vec3(0.0), vec3(1.0)), clamp(background, vec3(0.0), vec3(1.0)),
			smoothstep(0.6, 1.0, 1.0 - dir.y));
	}
	COLOR = c;
}
