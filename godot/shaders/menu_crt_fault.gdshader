shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// 每台实体CRT只处理自己的SubViewport纹理；不读全屏，不扰动房间、外框或导航。
uniform sampler2D screen_image : source_color, filter_nearest, repeat_disable;
uniform float focus_gain : hint_range(0.3, 1.3) = 1.0;
uniform float fault_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fault_progress : hint_range(0.0, 1.0) = 0.0;
uniform float fault_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.13, 289.97))) * 13758.21);
}

void fragment() {
	vec2 uv = UV;
	float phase = clamp(fault_progress, 0.0, 1.0);
	float envelope = sin(phase * 3.14159265) * fault_amount;
	float tick = floor(phase * 11.0);
	float band_a = step(abs(uv.y - 0.28), 0.055);
	float band_b = step(abs(uv.y - 0.66), 0.040);
	float band = max(band_a, band_b);
	float jerk = (hash(vec2(tick, fault_seed)) - 0.5) * 16.0;
	uv.x += band * jerk * envelope / 640.0;
	// 小幅垂直失步后回卷；故障归零即完全恢复原UV，文字不会长期被弯曲或滤糊。
	float roll = (floor(phase * 4.0) / 4.0) * 0.21 * envelope;
	uv.y = fract(uv.y + roll);
	vec3 rgb = texture(screen_image, uv).rgb;
	float split = 2.8 * envelope * band / 640.0;
	rgb.r = texture(screen_image, uv + vec2(split, 0.0)).r;
	rgb.b = texture(screen_image, uv - vec2(split, 0.0)).b;
	float noise = hash(floor(uv * vec2(640.0, 360.0)) + vec2(tick, fault_seed));
	float snow = step(0.83, noise) * band * envelope;
	rgb = mix(rgb, vec3(noise * 0.58), snow * 0.55);
	float retrace = step(abs(uv.y - fract(0.80 + phase * 0.32)), 0.009) * envelope;
	rgb *= 1.0 - retrace * 0.42;
	// 只有边沿轻微玻璃暗角/反光；中心正文保持nearest与稳定对比。
	vec2 centered = abs(UV - vec2(0.5)) * 2.0;
	float edge = pow(max(centered.x, centered.y), 9.0);
	rgb *= 1.0 - edge * 0.13;
	float gleam = max(0.0, 1.0 - abs(UV.y - (0.06 + UV.x * 0.18)) * 95.0);
	rgb += vec3(0.008, 0.012, 0.013) * gleam * (1.0 - centered.x);
	ALBEDO = rgb * focus_gain;
}
