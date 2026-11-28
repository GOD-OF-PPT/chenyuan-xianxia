shader_type canvas_item;
// Song-Ming celadon-ink occlusion silhouette contour + wash shader (20-art-bible.md §5.3).
// Renders a crisp light celadon-xuan rim outline and subtle jade-ink silhouette fill when an actor
// stands behind a 55% semi-transparent roof eave or ancient tree canopy.

uniform vec4 rim_color : source_color = vec4(0.68, 0.82, 0.78, 0.92);
uniform vec4 fill_color : source_color = vec4(0.24, 0.36, 0.35, 0.34);
uniform float rim_px : hint_range(0.5, 4.0) = 1.75;

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 center = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * rim_px;
	float neighbor_min_a = min(
		min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a)
	);
	float inside = smoothstep(0.12, 0.45, center.a);
	float is_rim = inside * (1.0 - smoothstep(0.15, 0.65, neighbor_min_a));
	vec3 rgb = mix(fill_color.rgb, rim_color.rgb, is_rim);
	float a = inside * mix(fill_color.a, rim_color.a, is_rim) * v_modulate.a;
	COLOR = vec4(clamp(rgb, vec3(0.0), vec3(0.90)), a);
}
