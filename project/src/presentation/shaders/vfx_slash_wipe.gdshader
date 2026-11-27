shader_type canvas_item;
render_mode unshaded, blend_mix;

// Driven strictly from GDScript combat_delta (zero built-in TIME so Space Tactical Pause & Hitstop freeze 100%).
uniform float sweep_progress : hint_range(0.0, 1.0) = 0.5;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Crescent textures sweep from UV.y = 0.0 (tail) -> UV.y = 1.0 (leading tip)
	float lead_edge = 1.0 - smoothstep(sweep_progress - 0.06, sweep_progress + 0.20, UV.y);
	float tail_dissolve = smoothstep(max(0.0, sweep_progress - 0.78), min(1.0, sweep_progress + 0.08), UV.y);
	float env = clamp(sin(clamp(sweep_progress, 0.0, 1.0) * 3.14159265) * 1.38, 0.0, 1.0);
	float final_a = tex.a * lead_edge * mix(1.0, tail_dissolve, sweep_progress * 0.68) * env * tint_color.a;
	COLOR = vec4(tex.rgb * tint_color.rgb, final_a);
}
