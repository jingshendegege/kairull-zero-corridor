"""敌人限定色板：ramp = [高光, 基色, 阴影, 深影]，line = 自身色系描边。

阵营统一：深蓝灰装甲 + 琥珀色装备 + 青色目镜/灯 + 品红危险提示，与玩家的白/冷蓝区分；
背景是冷蓝灰低对比，敌人主体压暗、用琥珀和青色做识别点。
"""

RIFLEMAN = {
    # 深蓝制服 / 炭灰裤 / 炭黑装甲 —— 参考旧枪手的沉稳配色，琥珀挂包与青色目镜做识别点
    "cloth": {"ramp": ["#4a64a8", "#2f437c", "#223058", "#161f3c"], "line": "#0a0f20", "grain": True, "outline_front": True},
    "pants": {"ramp": ["#565b67", "#3b3f49", "#2a2d35", "#1c1e24"], "line": "#0d0e12", "grain": True},
    "armor": {"ramp": ["#5f6673", "#3d424d", "#2a2e36", "#1b1e24"], "line": "#0a0b0e", "spec": "#9aa3b2", "grain": True},
    "amber": {"ramp": ["#f7c46a", "#cf8e3c", "#9a5f28", "#65391a"], "line": "#34190a"},
    "metal": {"ramp": ["#6f7a86", "#4a535e", "#333a42", "#23282e"], "line": "#0e1115", "spec": "#b5bfca"},
    "gun": {"ramp": ["#5a626d", "#353a42", "#23272d", "#15171b"], "line": "#060708", "spec": "#a7b3c2", "spec_at": 0.9, "outline_front": True},
    "mask": {"ramp": ["#555a66", "#373b44", "#25282f", "#18191e"], "line": "#0a0b0e"},
    "glove": {"ramp": ["#ddd2b8", "#ada189", "#7c7362", "#534c41"], "line": "#211c14", "outline_front": True},
    "boot": {"ramp": ["#5d4a3c", "#3f3229", "#2b221c", "#1d1713"], "line": "#0c0907"},
    "visor": {"ramp": ["#8ff8ff"], "line": "#1c8c9c", "emissive": True},
    "lamp": {"ramp": ["#ff5aa8"], "line": "#8c1a52", "emissive": True},
    "flash": {"ramp": ["#fff3c4"], "line": "#ffb23a", "emissive": True},
}

LOADER = {
    "armor": {"ramp": ["#d4ae58", "#a27e36", "#715626", "#463517"], "line": "#1c1406", "spec": "#f3dc98", "grain": True},
    "plate": {"ramp": ["#5b5f69", "#3d4048", "#2a2c32", "#1c1d22"], "line": "#09090b", "spec": "#9ca1ab", "grain": True},
    "hazard": {"ramp": ["#ffd27a", "#e0a13c", "#a9702a", "#71461a"], "line": "#3a220a"},
    "cloth": {"ramp": ["#4a5c86", "#33426a", "#243050", "#171f36"], "line": "#0a0e1a", "grain": True},
    "metal": {"ramp": ["#a3adb8", "#6b7581", "#474e58", "#2d3239"], "line": "#12151a", "spec": "#e2e8ee"},
    "mask": {"ramp": ["#5a5f6b", "#3a3e48", "#272a32", "#191b21"], "line": "#0b0c10"},
    "boot": {"ramp": ["#5b4d42", "#3f352d", "#2b241e", "#1c1814"], "line": "#0c0a08"},
    "glove": {"ramp": ["#ddd2b8", "#ada189", "#7c7362", "#534c41"], "line": "#211c14", "outline_front": True},
    "visor": {"ramp": ["#8ff8ff"], "line": "#1c8c9c", "emissive": True},
    "lamp": {"ramp": ["#ff5aa8"], "line": "#8c1a52", "emissive": True},
    "hot": {"ramp": ["#ff9b5a"], "line": "#8c3212", "emissive": True},
}


HOUND = {
    # 炭蓝机械装甲 + 深蓝胸甲 + 琥珀侧腹警示条；品红眼缝是飞扑预警的视觉焦点
    "plate": {"ramp": ["#5f6a7e", "#3c4556", "#2a303c", "#1c2029"], "line": "#0a0c11", "spec": "#98a3b6", "grain": True},
    "armor": {"ramp": ["#4f6394", "#33436c", "#232f4e", "#171f35"], "line": "#0a0e1c", "spec": "#8ea2d0"},
    "hazard": {"ramp": ["#ffd27a", "#dc9a45", "#a4662b", "#6e411c"], "line": "#3a200c"},
    "metal": {"ramp": ["#8d99a6", "#5d6875", "#3f4751", "#2a3037"], "line": "#12161b", "spec": "#d2dae3"},
    "lamp": {"ramp": ["#ff5aa8"], "line": "#8c1a52", "emissive": True},
    "lamp_cyan": {"ramp": ["#8ff8ff"], "line": "#1c8c9c", "emissive": True},
}
