shader_type canvas_item;
// Stage C shaded wet bluestone road shader (intentionally WITHOUT render_mode unshaded
// so CanvasModulate ambient rain mood and warm/cool PointLight2D reflections illuminate roads).

uniform float wetness : hint_range(0.0, 1.0) = 0.74;
uniform float ripple_speed : hint_range(0.0, 2.0) = 1.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.34;
uniform vec4 sky_sheen_color : source_color = vec4(0.66, 0.75, 0.77, 1.0);

varying vec2 v_world_pos;
varying vec4 v_modulate;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float rain_ripple_field(vec2 wp, float t) {
	vec2 cell_uv = wp / 86.0;
	vec2 cell_id = floor(cell_uv);
	vec2 local = fract(cell_uv) - 0.5;
	float acc = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 cid = cell_id + vec2(float(dx), float(dy));
			float rnd = hash21(cid);
			vec2 center = vec2(hash21(cid + 7.13), hash21(cid + 19.41)) - 0.5;
			vec2 diff = local - vec2(float(dx), float(dy)) - center * 0.52;
			diff.y *= 1.55; // Isometric foreshortening
			float dist = length(diff);
			float phase = fract(t * 0.62 + rnd);
			float radius = phase * 0.58;
			float ring = exp(-abs(dist - radius) * 34.0) * (1.0 - phase) * smoothstep(0.62, 0.06, dist);
			acc += ring;
		}
	}
	return clamp(acc, 0.0, 1.0);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 base_rgb = tex.rgb * v_modulate.rgb;

	// Low-frequency shallow water film across worn bluestone depressions
	float n_coarse = value_noise(v_world_pos * 0.0085);
	float n_fine = value_noise(v_world_pos * 0.029 + vec2(4.2, -3.1));
	float puddle_mask = smoothstep(0.38, 0.76, n_coarse * 0.72 + n_fine * 0.28) * wetness;

	// Darken wet porous stone slightly, then add misty sky glaze & raindrop concentric rings
	vec3 darkened = base_rgb * mix(1.0, 0.87, puddle_mask * 0.65);
	float anim_t = TIME * ripple_speed;
	float ripples = (ripple_speed > 0.001) ? rain_ripple_field(v_world_pos, anim_t) : (rain_ripple_field(v_world_pos, 1.35) * 0.35);

	vec3 glazed = mix(darkened, sky_sheen_color.rgb * 0.74, puddle_mask * 0.22);
	glazed += sky_sheen_color.rgb * (ripples * ripple_strength * (0.35 + 0.65 * puddle_mask) * 0.16);

	COLOR = vec4(clamp(glazed, vec3(0.0), vec3(0.92)), tex.a * v_modulate.a);
}

void light() {
	float n_puddle = smoothstep(0.36, 0.78, value_noise(v_world_pos * 0.0085)) * wetness;
	float wet_boost = 1.0 + n_puddle * 0.48;
	vec3 lit = COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * wet_boost;
	// Subtle warm/cool water-film specular lift on wet bluestone slabs
	vec3 spec = LIGHT_COLOR.rgb * (LIGHT_ENERGY * n_puddle * 0.11);
	LIGHT = vec4(clamp(lit + spec, vec3(0.0), vec3(0.94)), LIGHT_COLOR.a);
}
