group_uniforms Effects.Wind;
uniform sampler2D wind_noise_texture : hint_default_white, repeat_enable, filter_linear;
uniform float wind_direction_degrees : hint_range(0.0, 360.0, 0.1) = 45.0;
uniform float wind_speed : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float wind_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float wind_scale : hint_range(0.005, 1.0, 0.005) = 0.037;
uniform float wind_gust_strength : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform float wind_gust_speed : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform int wind_mode = 0;
group_uniforms;

vec2 mst_get_wind_direction() {
	// The editor angle is the source of truth: 0 degrees is +Z and angles turn
	// clockwise around the spherical Y axis. This keeps the shader and editor
	// gizmo using the same wind direction convention.
	float angle_radians = radians(wind_direction_degrees);
	return vec2(sin(angle_radians), cos(angle_radians));
}

// Small deterministic procedural helpers. These deliberately operate in world
// space so neighboring blades share a coherent air mass instead of flickering
// independently from one another.
float mst_wind_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float mst_wind_value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	float a = mst_wind_hash(cell);
	float b = mst_wind_hash(cell + vec2(1.0, 0.0));
	float c = mst_wind_hash(cell + vec2(0.0, 1.0));
	float d = mst_wind_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float mst_wind_fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += mst_wind_value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.13, 9.71);
		amplitude *= 0.5;
	}
	return value / 0.9375;
}

// A compact 3x3 Worley/cellular distance. It creates moving gust pockets
// rather than another smooth scalar texture.
float mst_wind_worley(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = vec2(
				mst_wind_hash(cell + offset),
				mst_wind_hash(cell + offset + vec2(41.7, 17.3))
			);
			nearest = min(nearest, length(offset + point - local));
		}
	}
	return nearest;
}

float mst_wind_wave(vec2 world_xz, vec2 dir, float scale, float sample_time, float seed) {
	float phase = dot(world_xz, dir) * scale * 6.28318
		- sample_time * max(wind_speed, 0.001) * 1.8 + seed * 0.35;
	float broad_wave = sin(phase);
	float harmonic = sin(phase * 0.47 + 1.7) * 0.28;
	return 0.5 + 0.5 * clamp(broad_wave * 0.72 + harmonic, -1.0, 1.0);
}

vec2 mst_build_wind_vector_at_time(vec2 world_xz, float seed, float sample_time) {
	vec2 dir = mst_get_wind_direction();
	vec2 cross_dir = vec2(-dir.y, dir.x);
	float scale = max(wind_scale, 0.005);
	float seed_offset = seed * 11.37;

	// Smooth: broad, layered traveling wavefronts with only a subtle envelope.
	if (wind_mode == 0) {
		float wave = mst_wind_wave(world_xz, dir, scale * 0.42, sample_time, seed_offset);
		float envelope = mix(0.78, 1.12, mst_wind_value_noise(world_xz * scale * 0.18 + vec2(sample_time * 0.03)));
		return dir * wave * envelope * wind_strength;
	}

	// Gusty: coherent wavefronts pass through cellular gust pockets. The
	// Worley field gives each gust a readable birth/peak/falloff shape.
	if (wind_mode == 1) {
		vec2 gust_position = world_xz * scale * 0.32
			- dir * sample_time * max(wind_gust_speed, 0.001) * 0.22;
		float cell_distance = mst_wind_worley(gust_position + vec2(seed_offset));
		float gust_front = 1.0 - smoothstep(0.18, 0.72, cell_distance);
		float wave = mst_wind_wave(world_xz, dir, scale * 0.72, sample_time, seed_offset);
		float gust_amount = mix(0.28, 1.0 + wind_gust_strength, gust_front);
		return dir * wave * gust_amount * wind_strength;
	}

	// Turbulent: retain a directional carrier, then add a curl-like field from
	// layered noise gradients so the flow bends sideways instead of merely
	// changing amplitude.
	vec2 turbulent_position = world_xz * scale * 1.55
		+ cross_dir * sample_time * max(wind_speed, 0.001) * 0.25
		+ vec2(seed_offset);
	float gradient_step = 0.08;
	float noise_x1 = mst_wind_fbm(turbulent_position + vec2(gradient_step, 0.0));
	float noise_x0 = mst_wind_fbm(turbulent_position - vec2(gradient_step, 0.0));
	float noise_y1 = mst_wind_fbm(turbulent_position + vec2(0.0, gradient_step));
	float noise_y0 = mst_wind_fbm(turbulent_position - vec2(0.0, gradient_step));
	vec2 curl = normalize(vec2(noise_y1 - noise_y0, -(noise_x1 - noise_x0)) + vec2(0.0001));
	float turbulence = mst_wind_fbm(turbulent_position * 0.65 + dir * sample_time * 0.12);
	float carrier = mst_wind_wave(world_xz, dir, scale * 0.58, sample_time, seed_offset);
	vec2 flow = dir * carrier * 0.78 + curl * (turbulence * 0.72);
	return normalize(flow + vec2(0.0001)) * clamp(length(flow), 0.0, 1.35) * wind_strength;
}

float mst_sample_wind_sway_at_time(vec2 world_xz, float seed, float sample_time) {
	return dot(mst_build_wind_vector_at_time(world_xz, seed, sample_time), mst_get_wind_direction());
}

float mst_sample_wind_sway(vec2 world_xz, float seed) {
	return mst_sample_wind_sway_at_time(world_xz, seed, TIME);
}

vec2 mst_sample_wind_vector_at_time(vec2 world_xz, float seed, float sample_time) {
	return mst_build_wind_vector_at_time(world_xz, seed, sample_time);
}

vec2 mst_sample_wind_vector(vec2 world_xz, float seed) {
	return mst_sample_wind_vector_at_time(world_xz, seed, TIME);
}
