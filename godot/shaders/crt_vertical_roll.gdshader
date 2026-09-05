shader_type canvas_item;
render_mode unshaded;

// BackBufferCopy 在同一 CanvasLayer、同一帧先复制完整视口；这里只做 GPU 内屏幕采样。
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 viewport_size = vec2(1360.0, 765.0);
uniform float roll_progress : hint_range(0.0, 1.0) = 0.0;
uniform float fault_strength : hint_range(0.0, 1.0) = 0.75;
uniform float sync_tear_px : hint_range(10.0, 24.0) = 18.0;
uniform float rgb_separation_px : hint_range(3.0, 5.0) = 4.0;
uniform float snow_amount : hint_range(0.0, 0.08) = 0.028;
uniform float retrace_strength : hint_range(0.0, 1.0) = 0.72;
uniform float desaturation : hint_range(0.0, 0.4) = 0.16;
uniform float scanline_strength : hint_range(0.0, 0.15) = 0.055;

float wrapped_distance(float a, float b) {
	float distance = abs(a - b);
	return min(distance, 1.0 - distance);
}

float band_mask(float y, float center, float inner_width, float outer_width) {
	return 1.0 - smoothstep(inner_width, outer_width, wrapped_distance(y, center));
}

float stable_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 size = max(viewport_size, vec2(1.0));
	float progress = clamp(roll_progress, 0.0, 1.0);
	float fault = clamp(fault_strength, 0.0, 1.0);

	// 六段“停顿→抽动”保持严格单调；fault=0 时可对照原本匀速整屏上卷。
	float segment_count = 6.0;
	float segment = min(floor(progress * segment_count), segment_count - 1.0);
	float local_progress = progress >= 0.999999 ? 1.0 : fract(progress * segment_count);
	float jerk = smoothstep(0.55, 0.85, local_progress);
	float stepped_roll = progress >= 0.999999 ? 1.0 : (segment + jerk) / segment_count;
	float roll_offset = mix(progress, stepped_roll, fault);

	// 输出像素向下寻找更靠下的源像素，因此整幅画面向上移动；fract 让出顶内容从底部接回。
	vec2 sample_uv = SCREEN_UV;
	sample_uv.y = fract(sample_uv.y + roll_offset);

	// 三条宽同步撕裂带只在 progress 分段改变位置；没有按时钟逐像素乱闪。
	float phase = floor(progress * segment_count);
	float band_a = band_mask(SCREEN_UV.y, fract(0.16 + phase * 0.071), 0.025, 0.042);
	float band_b = band_mask(SCREEN_UV.y, fract(0.50 + phase * 0.113), 0.032, 0.052);
	float band_c = band_mask(SCREEN_UV.y, fract(0.81 + phase * 0.047), 0.020, 0.038);
	float tear_mix = band_a * 0.72 - band_b + band_c * 0.58;
	sample_uv.x += tear_mix * sync_tear_px * fault / size.x;

	// 采样坐标锁到真实视口像素中心，保持项目 nearest 像素边缘。
	sample_uv.x = clamp(sample_uv.x, 0.5 / size.x, 1.0 - 0.5 / size.x);
	sample_uv = (floor(sample_uv * size) + vec2(0.5)) / size;
	sample_uv.y = fract(sample_uv.y);
	vec4 source = textureLod(screen_texture, sample_uv, 0.0);

	// 3~5px RGB 分离只出现在同步撕裂带内，主体画面仍保持像素对齐。
	float rgb_band = clamp(band_a + band_b + band_c, 0.0, 1.0);
	float rgb_offset = rgb_separation_px * fault * rgb_band / size.x;
	vec2 red_uv = sample_uv + vec2(rgb_offset, 0.0);
	vec2 blue_uv = sample_uv - vec2(rgb_offset, 0.0);
	red_uv.x = clamp(red_uv.x, 0.5 / size.x, 1.0 - 0.5 / size.x);
	blue_uv.x = clamp(blue_uv.x, 0.5 / size.x, 1.0 - 0.5 / size.x);
	red_uv = (floor(red_uv * size) + vec2(0.5)) / size;
	blue_uv = (floor(blue_uv * size) + vec2(0.5)) / size;
	source.r = textureLod(screen_texture, red_uv, 0.0).r;
	source.b = textureLod(screen_texture, blue_uv, 0.0).b;

	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 color = mix(source.rgb, vec3(luminance), desaturation * (0.55 + fault * 0.45));

	// 局部雪花是按像素格和 progress 段确定的短划点，只占一小片，不生成满屏噪声。
	float snow_center = fract(0.34 + phase * 0.137);
	float snow_region = band_mask(SCREEN_UV.y, snow_center, 0.038, 0.082);
	vec2 snow_cell = vec2(floor(FRAGCOORD.x / 3.0), floor(FRAGCOORD.y) + phase * 97.0);
	float snow = step(1.0 - snow_amount, stable_hash(snow_cell)) * snow_region * fault;
	color = mix(color, vec3(0.62 + luminance * 0.20), snow * 0.72);

	// 环回接缝附近压出一条黑色回扫带，强调电视失锁而不是平滑网页滚动。
	float retrace_center = fract(1.0 - roll_offset);
	float retrace = band_mask(SCREEN_UV.y, retrace_center, 0.006, 0.019);
	color *= 1.0 - retrace * retrace_strength * fault;
	// 每四个显示像素仅压暗一条细扫描线，不闪白、不模糊、不改变几何轮廓。
	float scanline = 1.0 - step(0.5, mod(floor(FRAGCOORD.y), 4.0));
	color *= 1.0 - scanline * scanline_strength;
	COLOR = vec4(color, 1.0);
}
