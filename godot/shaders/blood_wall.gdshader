shader_type canvas_item;
render_mode blend_mix, unshaded;

// 结构判断始终使用 Nearest，避免破坏项目的像素画边缘。
uniform sampler2D screen_texture_nearest : hint_screen_texture, repeat_disable, filter_nearest;
// Linear 采样器只供极轻微的湿润折射使用，可随时关闭作对照。
uniform sampler2D screen_texture_linear : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms blood_appearance;
uniform vec4 blood_color : source_color = vec4(0.48, 0.025, 0.02, 1.0);
uniform float blood_opacity : hint_range(0.0, 1.0, 0.01) = 0.86;
uniform float multiply_intensity : hint_range(0.0, 2.0, 0.01) = 1.10;
uniform float alpha_discard_threshold : hint_range(0.0, 0.25, 0.001) = 0.01;

group_uniforms feature_switches;
uniform bool enable_occlusion = true;
uniform bool enable_darkness = true;
uniform bool enable_refraction = true;
uniform bool use_linear_refraction = true;
uniform bool enable_normal_lighting = true;
uniform bool enable_dark_surface_lift = true;

group_uniforms directional_occlusion;
// Godot 屏幕坐标 Y 轴向下：0/90/-90 度分别朝右/下/上喷射。
uniform float spray_angle : hint_range(-180.0, 180.0, 0.1) = 0.0;
uniform float occlusion_strength : hint_range(0.0, 24.0, 0.1) = 6.0;
uniform int occlusion_ray_steps : hint_range(1, 32, 1) = 12;
// 单位为屏幕像素，避免分辨率改变后遮蔽范围被成倍放大。
uniform float occlusion_ray_length : hint_range(0.0, 48.0, 0.5) = 12.0;

group_uniforms darkness_mask;
uniform float darkness_threshold : hint_range(0.0, 1.0, 0.001) = 0.035;
// 给阈值留一个柔和过渡，减少相机移动时的单像素闪烁。
uniform float darkness_softness : hint_range(0.001, 0.25, 0.001) = 0.025;

group_uniforms dark_surface_readability;
// 纯正片叠底会在暗墙上吃掉彩色色相；仅在暗面混回受光后的原色，不改亮墙。
uniform float dark_surface_lift_strength : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float dark_surface_lift_start : hint_range(0.0, 0.6, 0.01) = 0.10;
// 覆盖中暗钢墙；纯黑门洞仍由 darkness_visibility 在补色前清除。
uniform float dark_surface_lift_end : hint_range(0.0, 0.6, 0.01) = 0.34;

group_uniforms wet_refraction;
// 单位为屏幕像素；默认仅四分之一像素，不能扰乱轮廓。
uniform float luminance_deformation_strength : hint_range(0.0, 1.0, 0.01) = 0.25;

group_uniforms normal_lighting;
uniform float background_bump_strength : hint_range(0.0, 12.0, 0.1) = 4.0;
uniform float blood_bump_strength : hint_range(0.0, 12.0, 0.1) = 3.0;
uniform float light_angle : hint_range(-180.0, 180.0, 0.1) = -45.0;
uniform float light_height : hint_range(0.05, 2.0, 0.01) = 0.75;
// 不能设为 1.0，否则漫反射项恒定，看不出伪法线。
uniform float ambient_light : hint_range(0.0, 1.0, 0.01) = 0.72;

group_uniforms debug;
// 0 完整；1 原始 Alpha；2 遮蔽；3 暗区；4 背景亮度；5 背景伪法线；6 暗墙补色范围。
uniform int debug_mode : hint_range(0, 6, 1) = 0;

// 显式传递节点调制，避免在 fragment 中重复乘入 TEXTURE Alpha。
varying vec4 canvas_modulate;

void vertex() {
	canvas_modulate = COLOR;
}

float luminance(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

vec2 screen_pixel_size() {
	// Godot 4 CanvasItem 不提供 SCREEN_PIXEL_SIZE；直接从当前屏幕副本尺寸换算 texel。
	return vec2(1.0) / vec2(textureSize(screen_texture_nearest, 0));
}

vec2 safe_screen_uv(vec2 uv) {
	vec2 half_pixel = screen_pixel_size() * 0.5;
	return clamp(uv, half_pixel, vec2(1.0) - half_pixel);
}

float screen_luminance(vec2 uv) {
	return luminance(texture(screen_texture_nearest, safe_screen_uv(uv)).rgb);
}

// 沿喷射方向的反方向寻找更亮的结构，将背景亮度近似为伪高度。
float directional_visibility(vec2 uv, vec2 spray_direction) {
	int step_count = max(occlusion_ray_steps, 1);
	vec2 ray_step = spray_direction * screen_pixel_size() * occlusion_ray_length / float(step_count);
	float current_height = screen_luminance(uv);
	float accumulated_occlusion = 0.0;

	// 固定上限便于 GL Compatibility 编译；运行时参数只负责提前退出。
	for (int index = 1; index <= 32; index++) {
		if (index > step_count) {
			break;
		}
		float progress = float(index) / float(step_count);
		float sampled_height = screen_luminance(uv - ray_step * float(index));
		// 轻微抬高视线，避免整片同亮墙面互相遮蔽。
		float line_of_sight_height = current_height + progress * 0.06;
		float height_excess = max(sampled_height - line_of_sight_height, 0.0);
		accumulated_occlusion += height_excess * occlusion_strength / float(step_count);
	}

	return 1.0 - clamp(accumulated_occlusion, 0.0, 1.0);
}

// 用中心与八邻域的亮度差估算湿润折射方向。
vec2 luminance_deformation(vec2 uv) {
	float center = screen_luminance(uv);
	vec2 deformation = vec2(0.0);
	vec2 pixel_size = screen_pixel_size();
	const float DIAGONAL_WEIGHT = 0.70710678;

	deformation += vec2(-1.0, 0.0) * (center - screen_luminance(uv + vec2(-pixel_size.x, 0.0)));
	deformation += vec2(1.0, 0.0) * (center - screen_luminance(uv + vec2(pixel_size.x, 0.0)));
	deformation += vec2(0.0, -1.0) * (center - screen_luminance(uv + vec2(0.0, -pixel_size.y)));
	deformation += vec2(0.0, 1.0) * (center - screen_luminance(uv + vec2(0.0, pixel_size.y)));
	deformation += vec2(-DIAGONAL_WEIGHT, -DIAGONAL_WEIGHT) * (center - screen_luminance(uv - pixel_size));
	deformation += vec2(DIAGONAL_WEIGHT, -DIAGONAL_WEIGHT) * (center - screen_luminance(uv + vec2(pixel_size.x, -pixel_size.y)));
	deformation += vec2(-DIAGONAL_WEIGHT, DIAGONAL_WEIGHT) * (center - screen_luminance(uv + vec2(-pixel_size.x, pixel_size.y)));
	deformation += vec2(DIAGONAL_WEIGHT, DIAGONAL_WEIGHT) * (center - screen_luminance(uv + pixel_size));

	return deformation / 8.0;
}

vec3 background_normal_at(vec2 uv) {
	float center = screen_luminance(uv);
	vec2 pixel_size = screen_pixel_size();
	float right = screen_luminance(uv + vec2(pixel_size.x, 0.0));
	float down = screen_luminance(uv + vec2(0.0, pixel_size.y));
	vec2 gradient = vec2(center - right, center - down) * background_bump_strength;
	return normalize(vec3(gradient, 1.0));
}

vec3 blood_normal_from_alpha(float center, float right, float down) {
	// TEXTURE/TEXTURE_PIXEL_SIZE 是 fragment 阶段内建量，采样在调用处完成再传入。
	vec2 gradient = vec2(center - right, center - down) * blood_bump_strength;
	return normalize(vec3(gradient, 1.0));
}

void fragment() {
	vec4 source_texel = texture(TEXTURE, UV);
	float raw_alpha = source_texel.a * canvas_modulate.a;
	if (raw_alpha < alpha_discard_threshold) {
		discard;
	}

	float spray_radians = radians(spray_angle);
	vec2 spray_direction = vec2(cos(spray_radians), sin(spray_radians));
	float occlusion_visibility = 1.0;
	if (enable_occlusion && (debug_mode == 0 || debug_mode == 2)) {
		occlusion_visibility = directional_visibility(SCREEN_UV, spray_direction);
	}

	float base_luminance = 0.0;
	if (debug_mode == 0 || debug_mode >= 3) {
		base_luminance = screen_luminance(SCREEN_UV);
	}
	float darkness_visibility = 1.0;
	if (enable_darkness && (debug_mode == 0 || debug_mode == 3 || debug_mode == 6)) {
		darkness_visibility = smoothstep(
			darkness_threshold,
			darkness_threshold + darkness_softness,
			base_luminance
		);
	}
	// Inspector 中即使把起止值填反，也按较暗端到较亮端平滑过渡。
	float lift_start = min(dark_surface_lift_start, dark_surface_lift_end);
	float lift_end = max(
			max(dark_surface_lift_start, dark_surface_lift_end), lift_start + 0.001);
	float dark_surface_lift_mask = 1.0 - smoothstep(
			lift_start, lift_end, base_luminance);

	float effective_alpha = raw_alpha * occlusion_visibility * darkness_visibility;

	// fragment 入口不允许 return；用互斥分支保证调试模式仍跳过不需要的重采样。
	if (debug_mode == 1) {
		COLOR = vec4(vec3(raw_alpha), 1.0);
	} else if (debug_mode == 2) {
		COLOR = vec4(vec3(occlusion_visibility), 1.0);
	} else if (debug_mode == 3) {
		COLOR = vec4(vec3(darkness_visibility), 1.0);
	} else if (debug_mode == 4) {
		COLOR = vec4(vec3(base_luminance), 1.0);
	} else if (debug_mode == 6) {
		// 同时显示暗区剔除后的实际生效范围，纯黑门洞不会被误标为可补色区域。
		COLOR = vec4(vec3(dark_surface_lift_mask * darkness_visibility), 1.0);
	} else {
		vec2 deformed_uv = SCREEN_UV;
		if (enable_refraction && debug_mode == 0) {
			vec2 deformation = luminance_deformation(SCREEN_UV);
			deformed_uv += deformation * screen_pixel_size() * luminance_deformation_strength * effective_alpha;
			deformed_uv = safe_screen_uv(deformed_uv);
		}

		vec3 background_normal = vec3(0.0, 0.0, 1.0);
		// 关闭法线时真正省掉三次背景亮度采样；调试模式 5 仍可单独查看伪法线。
		if (enable_normal_lighting || debug_mode == 5) {
			background_normal = background_normal_at(deformed_uv);
		}
		if (debug_mode == 5) {
			COLOR = vec4(background_normal * 0.5 + 0.5, 1.0);
		} else {
			if (effective_alpha < alpha_discard_threshold) {
				discard;
			}

			vec3 sampled_background;
			if (enable_refraction && use_linear_refraction) {
				sampled_background = texture(screen_texture_linear, deformed_uv).rgb;
			} else {
				sampled_background = texture(screen_texture_nearest, deformed_uv).rgb;
			}

			float light_intensity = 1.0;
			if (enable_normal_lighting) {
				vec3 blood_normal = blood_normal_from_alpha(
					source_texel.a,
					texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a,
					texture(TEXTURE, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a
				);
				vec3 mixed_normal = normalize(mix(background_normal, blood_normal, effective_alpha));
				float light_radians = radians(light_angle);
				vec3 light_direction = normalize(vec3(cos(light_radians), sin(light_radians), light_height));
				float diffuse = max(dot(mixed_normal, light_direction), 0.0);
				light_intensity = diffuse * (1.0 - ambient_light) + ambient_light;
			}

			// RGB 只输出“血迹源色”，Alpha 交给 blend_mix 合成一次，避免背景二次混合产生黑边。
			vec3 multiplied_blood = sampled_background * blood_color.rgb * multiply_intensity;
			vec3 final_blood_rgb = multiplied_blood * light_intensity;
			if (enable_dark_surface_lift) {
				// 暗面仍保留 45% 正片叠底纹理，并混回受同一伪法线光照的彩色颜料；
				// 不做加色、不采额外纹理，纯黑区域仍由 darkness_visibility 提前剔除。
				vec3 lit_pigment = blood_color.rgb * light_intensity;
				float pigment_mix = dark_surface_lift_mask * dark_surface_lift_strength;
				final_blood_rgb = mix(final_blood_rgb, lit_pigment, pigment_mix);
			}
			float final_alpha = clamp(effective_alpha * blood_opacity * blood_color.a, 0.0, 1.0);
			COLOR = vec4(final_blood_rgb, final_alpha);
		}
	}
}
