shader_type spatial;
render_mode unshaded, cull_back;

// 监控墙小屏（2026-09-30 开始界面重做）：mode 0 = 关卡实拍慢摇镜 + 单色染色 + 扫描线 + 滚动亮带；
// mode 1 = 雪花无信号；mode 2 = 彩条测试卡。自发光亮度 > 1 以触发 Environment 辉光。
uniform sampler2D feed : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform int mode = 0;
uniform float seed = 0.0;
uniform float energy = 1.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 7.13) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + seed * 3.7;
	vec3 rgb;
	if (mode == 1) {
		float n = hash(floor(uv * vec2(160.0, 90.0)) + floor(t * 24.0));
		rgb = vec3(n * 0.75) * tint.rgb * 0.8 + vec3(n * 0.2);
	} else if (mode == 2) {
		float bar = floor(uv.x * 7.0);
		vec3 bars[7] = vec3[7](vec3(.8,.8,.8), vec3(.8,.8,.1), vec3(.1,.8,.8), vec3(.1,.8,.1),
			vec3(.8,.1,.8), vec3(.8,.1,.1), vec3(.1,.1,.8));
		rgb = bars[int(bar)] * (uv.y < 0.72 ? 1.0 : 0.25);
		rgb *= 0.55 + 0.45 * step(0.5, fract(t * 0.5));
	} else {
		// 慢摇镜：放大 1.25 倍，在画面内左右缓慢平移
		float zoom = 1.25;
		vec2 pan = vec2(0.5 + 0.5 * sin(t * 0.11), 0.5 + 0.3 * sin(t * 0.07));
		vec2 src = uv / zoom + pan * (1.0 - 1.0 / zoom);
		src.x += (hash(vec2(floor(uv.y * 90.0), floor(t * 12.0))) - 0.5) * 0.004;
		vec3 c = texture(feed, src).rgb;
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		rgb = mix(vec3(lum), c, 0.25) * tint.rgb * 1.25;
		rgb += (hash(uv * 300.0 + t) - 0.5) * 0.08;
	}
	// 扫描线 + 向下滚动的亮带 + 暗角
	rgb *= 0.78 + 0.22 * step(0.5, fract(uv.y * 120.0));
	float roll = fract(t * 0.23 + seed);
	rgb += tint.rgb * 0.18 * smoothstep(0.06, 0.0, abs(uv.y - roll));
	vec2 d = abs(uv - 0.5) * 2.0;
	rgb *= 1.0 - pow(max(d.x, d.y), 6.0) * 0.7;
	ALBEDO = rgb * energy;
}
