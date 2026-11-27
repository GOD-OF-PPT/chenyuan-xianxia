shader_type canvas_item;
// Intentionally shaded (WITHOUT render_mode unshaded) so Milestone 4 PointLight2D and CanvasModulate illuminate actors naturally.

uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex_col = texture(TEXTURE, UV);
	float out_alpha = tex_col.a * v_modulate.a;
	vec3 base_rgb = tex_col.rgb * v_modulate.rgb;
	float f = clamp(hit_flash, 0.0, 1.0) * flash_color.a;
	// Blend 88% toward warm mineral white-gold + 12% lift so Song-Ming Gongbi ink lines remain subtly legible
	vec3 flashed_rgb = mix(base_rgb, flash_color.rgb, f * 0.88) + flash_color.rgb * (f * 0.12);
	COLOR = vec4(clamp(flashed_rgb, vec3(0.0), vec3(1.0)), out_alpha);
}
