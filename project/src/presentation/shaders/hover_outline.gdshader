shader_type canvas_item;
// Shaded world prop & NPC Gongbi gilt-jade hover outline shader (PROJECT.md Interface Contract #2).
// Samples built-in TEXTURE directly inside fragment() for 100% compatibility across both OpenGL3 and headless Dummy renderers.

uniform float outline_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float outline_width : hint_range(0.5, 6.0) = 2.4;
uniform vec4 outline_color : source_color = vec4(0.88, 0.74, 0.42, 0.96);
uniform vec4 accent_jade_color : source_color = vec4(0.52, 0.82, 0.71, 1.0);
uniform float solid_alpha_threshold : hint_range(0.10, 0.80) = 0.42;
uniform bool use_uv_border_clamp = true;

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex_col = texture(TEXTURE, UV);
	float strength = clamp(outline_intensity, 0.0, 1.0);
	if (strength <= 0.001) {
		COLOR = tex_col * v_modulate;
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		float lo = solid_alpha_threshold - 0.08;
		float hi = solid_alpha_threshold + 0.12;
		float self_solid = smoothstep(lo, hi, tex_col.a);

		float max_nb = 0.0;
		float min_nb = 1.0;
		vec2 dirs[8] = vec2[8](
			vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
			vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071), vec2(0.7071, -0.7071), vec2(-0.7071, -0.7071)
		);
		for (int i = 0; i < 8; i++) {
			vec2 uv1 = UV + dirs[i] * px;
			float s1 = 0.0;
			if (!use_uv_border_clamp || (uv1.x >= 0.0 && uv1.x <= 1.0 && uv1.y >= 0.0 && uv1.y <= 1.0)) {
				s1 = smoothstep(lo, hi, texture(TEXTURE, uv1).a);
			}
			max_nb = max(max_nb, s1);
			min_nb = min(min_nb, s1);
		}
		for (int j = 0; j < 4; j++) {
			vec2 uvh = UV + dirs[j] * (px * 0.55);
			float s_half = 0.0;
			if (!use_uv_border_clamp || (uvh.x >= 0.0 && uvh.x <= 1.0 && uvh.y >= 0.0 && uvh.y <= 1.0)) {
				s_half = smoothstep(lo, hi, texture(TEXTURE, uvh).a);
			}
			max_nb = max(max_nb, s_half);
		}

		float outer_ring = clamp(max_nb - self_solid, 0.0, 1.0);
		float inner_rim = self_solid * clamp(0.65 - min_nb, 0.0, 1.0) * 0.58;
		float rim_mix = clamp(1.0 - UV.y, 0.0, 1.0);
		vec3 rim_rgb = mix(outline_color.rgb, accent_jade_color.rgb, 0.24 * rim_mix) * v_modulate.rgb;

		vec3 lifted_base = (tex_col.rgb + outline_color.rgb * (0.08 * strength * self_solid)) * v_modulate.rgb;
		float halo_a = outer_ring * outline_color.a * strength;
		float base_a = tex_col.a;
		float out_a = clamp(max(base_a, halo_a), 0.0, 1.0);

		vec3 comp_rgb = mix(rim_rgb, lifted_base, self_solid);
		comp_rgb = mix(comp_rgb, rim_rgb, inner_rim * strength);
		if (self_solid <= 0.01 && halo_a <= 0.01) {
			comp_rgb = tex_col.rgb * v_modulate.rgb;
		}
		COLOR = vec4(clamp(comp_rgb, vec3(0.0), vec3(1.0)), out_a * v_modulate.a);
	}
}
