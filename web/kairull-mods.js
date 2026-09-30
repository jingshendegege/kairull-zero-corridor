// 《凯露尔：零号回廊》创意工坊 Mod API（window.KairullMods）与启动编排（window.KairullBoot）。
// 必须在 VibeHub 工坊 Loader 之前加载：先建立 API，再由 Loader 加载启动前 Mod。
// 公开约定见仓库根目录 WORKSHOP.md；带下划线的成员只供游戏内部桥接（Godot ModBridge）使用，Mod 不得调用。
(() => {
  'use strict';
  const API_VERSION = 1;
  const GAME_VERSION = '0.2.0';
  const ID_PATTERN = /^[a-z0-9][a-z0-9._-]{2,63}$/;
  const EVENTS = ['game:ready', 'menu:enter', 'level:start', 'level:clear', 'player:hurt',
    'player:death', 'rhythm:judge', 'boss:defeat'];
  const DIFFICULTIES = ['easy', 'hard', 'zero'];

  // 每类注册：Map<id, {id, owner, order, value}>；按注册顺序合并，后注册的同名字段覆盖先注册的。
  const registries = {
    difficultyHealth: new Map(),
    timeStop: new Map(),
    boss: new Map(),
    playerTint: new Map(),
  };
  const listeners = new Map(EVENTS.map((name) => [name, new Set()]));
  const overlays = new Map();
  let order = 0;
  let version = 0;
  let lastState = { scene: '', title: '', difficulty: '', maxHealth: 0 };
  let gameReady = false;

  function currentModId() {
    return window.VibeHubWorkshop?.currentMod?.id || null;
  }

  function checkId(id) {
    if (typeof id !== 'string' || !ID_PATTERN.test(id)) {
      throw new Error(`KairullMods: 注册 ID "${id}" 无效，只能用 3–64 位小写字母、数字、点、横线、下划线`);
    }
  }

  function clamp(value, min, max, name) {
    const number = Number(value);
    if (!Number.isFinite(number)) throw new Error(`KairullMods: ${name} 必须是数字`);
    return Math.min(max, Math.max(min, number));
  }

  function register(kind, id, value) {
    checkId(id);
    for (const [otherKind, map] of Object.entries(registries)) {
      if (map.has(id)) {
        throw new Error(`KairullMods: ID "${id}" 已被注册（${otherKind}），请先 unregister 或换一个 ID`);
      }
    }
    registries[kind].set(id, { id, owner: currentModId(), order: order++, value });
    version++;
    return () => unregister(id);
  }

  function unregister(id) {
    let removed = false;
    for (const map of Object.values(registries)) removed = map.delete(id) || removed;
    const overlay = overlays.get(id);
    if (overlay) {
      overlay.remove();
      overlays.delete(id);
      removed = true;
    }
    if (removed) version++;
    return removed;
  }

  function merged(kind) {
    const result = {};
    const entries = [...registries[kind].values()].sort((a, b) => a.order - b.order);
    for (const entry of entries) Object.assign(result, entry.value);
    return result;
  }

  function overlayRoot() {
    let root = document.getElementById('kairull-mod-layer');
    if (!root) {
      root = document.createElement('div');
      root.id = 'kairull-mod-layer';
      root.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:20;overflow:hidden';
      document.body.append(root);
    }
    return root;
  }

  const api = Object.freeze({
    apiVersion: API_VERSION,
    gameVersion: GAME_VERSION,
    events: Object.freeze([...EVENTS]),

    /** 覆盖三档难度的生命上限（1–9 格）。下一次开局 / 进入关卡时生效。 */
    registerDifficultyHealth(id, health) {
      const value = {};
      for (const mode of DIFFICULTIES) {
        if (health?.[mode] !== undefined) value[mode] = Math.round(clamp(health[mode], 1, 9, mode));
      }
      return register('difficultyHealth', id, value);
    },

    /** 时停：durationScale 最长时停倍率、rechargeScale 充满所需时间倍率（0.25–4）。 */
    registerTimeStopTuning(id, tuning) {
      const value = {};
      if (tuning?.durationScale !== undefined) value.durationScale = clamp(tuning.durationScale, 0.25, 4, 'durationScale');
      if (tuning?.rechargeScale !== undefined) value.rechargeScale = clamp(tuning.rechargeScale, 0.25, 4, 'rechargeScale');
      return register('timeStop', id, value);
    },

    /** 节奏 Boss：hpScale 血量倍率（0.25–4）。下一次进入 Boss 关时生效。 */
    registerBossTuning(id, tuning) {
      const value = {};
      if (tuning?.hpScale !== undefined) value.hpScale = clamp(tuning.hpScale, 0.25, 4, 'hpScale');
      return register('boss', id, value);
    },

    /** 主角色调：color 为 #rrggbb，strength 0–1（默认 1）。即时生效，只影响本地画面。 */
    registerPlayerTint(id, tint) {
      const color = String(tint?.color || '');
      if (!/^#[0-9a-fA-F]{6}$/.test(color)) throw new Error('KairullMods: color 必须是 #rrggbb');
      const strength = tint?.strength === undefined ? 1 : clamp(tint.strength, 0, 1, 'strength');
      return register('playerTint', id, { color, strength });
    },

    /** 在游戏画面上方创建一个属于该 ID 的 HTML 容器（默认不接收点击）。返回该元素。 */
    createOverlay(id) {
      checkId(id);
      if (overlays.has(id)) throw new Error(`KairullMods: 覆盖层 "${id}" 已存在`);
      const element = document.createElement('div');
      element.dataset.kairullMod = id;
      element.style.cssText = 'position:absolute;inset:0;pointer-events:none';
      overlayRoot().append(element);
      overlays.set(id, element);
      return element;
    },

    unregister,

    /** 订阅游戏事件；返回取消订阅函数。处理函数抛错不会影响游戏和其他 Mod。 */
    on(eventName, handler) {
      if (!listeners.has(eventName)) throw new Error(`KairullMods: 未知事件 "${eventName}"`);
      if (typeof handler !== 'function') throw new Error('KairullMods: handler 必须是函数');
      const owner = currentModId();
      const entry = { handler, owner };
      listeners.get(eventName).add(entry);
      return () => listeners.get(eventName).delete(entry);
    },

    /** 最近一次 level:start / level:clear 的关卡信息（只读副本）。 */
    getState() {
      return { ...lastState, gameReady };
    },

    /** 当前所有注册（只读），方便排查多个 Mod 的冲突。 */
    listRegistrations() {
      const rows = [];
      for (const [kind, map] of Object.entries(registries)) {
        for (const entry of map.values()) rows.push({ kind, id: entry.id, owner: entry.owner, value: { ...entry.value } });
      }
      for (const id of overlays.keys()) rows.push({ kind: 'overlay', id, owner: null, value: {} });
      return rows;
    },

    // ---- 以下仅供 Godot ModBridge 调用 ----
    get _version() {
      return version;
    },
    _snapshot() {
      return JSON.stringify({
        difficultyHealth: merged('difficultyHealth'),
        timeStop: merged('timeStop'),
        boss: merged('boss'),
        playerTint: merged('playerTint'),
      });
    },
    _emit(eventName, payloadJson) {
      let payload = {};
      try {
        payload = JSON.parse(payloadJson || '{}');
      } catch (_) {
        payload = {};
      }
      if (eventName === 'level:start' || eventName === 'level:clear') lastState = { ...lastState, ...payload };
      for (const entry of listeners.get(eventName) || []) {
        try {
          entry.handler(Object.freeze({ ...payload }));
        } catch (error) {
          console.error(`[KairullMods] Mod ${entry.owner || '(unknown)'} 处理 ${eventName} 出错`, error);
        }
      }
    },
    _gameReady() {
      if (gameReady) return;
      gameReady = true;
      window.VibeHubWorkshop?.markGameReady();
    },
  });

  Object.defineProperty(window, 'KairullMods', { value: api, writable: false, configurable: false });

  // 启动编排：API 已建立 → 等待启动前 Mod → 启动 Godot → （Godot 就绪时 markGameReady）→ 等待启动后 Mod。
  const BEFORE_START_TIMEOUT_MS = 10000;
  const GAME_READY_FALLBACK_MS = 20000;
  window.KairullBoot = Object.freeze({
    async start(launch) {
      const workshop = window.VibeHubWorkshop;
      if (workshop) {
        const timedOut = await Promise.race([
          workshop.beforeStart.then(() => false),
          new Promise((resolve) => setTimeout(() => resolve(true), BEFORE_START_TIMEOUT_MS)),
        ]);
        if (timedOut) console.warn('[KairullMods] 等待工坊启动前 Mod 超时，先启动游戏（不影响无 Mod 游玩）');
      }
      await launch();
      if (workshop) {
        // 正常情况下 Godot ModBridge 在首个场景就绪时调用 _gameReady()；若桥接异常，兜底放行启动后 Mod。
        setTimeout(() => api._gameReady(), GAME_READY_FALLBACK_MS);
        workshop.afterStart.then((result) => {
          if (result?.errors?.length) console.warn('[KairullMods] 部分 Mod 加载失败', result.errors);
        });
      }
    },
  });
})();
