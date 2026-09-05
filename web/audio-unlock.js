(() => {
  const contexts = new Set();
  let button;
  function refresh() {
    if (!button) return;
    const blocked = [...contexts].some(context => context.state !== 'running' && context.state !== 'closed');
    button.hidden = !blocked;
    button.textContent = '开启声音';
  }
  function unlock() {
    for (const context of contexts) {
      if (context.state === 'suspended' || context.state === 'interrupted') {
        context.resume().then(refresh).catch(() => { if (button) button.hidden = false; });
      }
    }
  }
  for (const key of ['AudioContext', 'webkitAudioContext']) {
    const NativeContext = window[key];
    if (!NativeContext) continue;
    window[key] = new Proxy(NativeContext, {
      construct(Target, args) {
        const context = new Target(...args);
        contexts.add(context);
        context.addEventListener('statechange', refresh);
        refresh();
        if (location.hostname === '127.0.0.1') {
          context.addEventListener('statechange', () => console.info('[Audio QA] state=' + context.state));
          const createSource = context.createBufferSource.bind(context);
          context.createBufferSource = () => {
            const source = createSource();
            const start = source.start.bind(source);
            source.start = (...values) => {
              const data = source.buffer?.getChannelData(0);
              let peak = 0;
              if (data) for (let i = 0; i < data.length; i += 32) peak = Math.max(peak, Math.abs(data[i]));
              console.info('[Audio QA] source state=' + context.state + ' peak=' + peak);
              return start(...values);
            };
            return source;
          };
        }
        return context;
      }
    });
  }
  document.addEventListener('pointerdown', unlock, true);
  document.addEventListener('keydown', unlock, true);
  document.addEventListener('DOMContentLoaded', () => {
    button = document.createElement('button');
    button.hidden = true;
    button.style.cssText = 'position:fixed;right:12px;top:58px;z-index:10001;padding:8px 14px;background:#14362c;color:#daf6ea;border:1px solid #6cb89c;border-radius:6px;cursor:pointer';
    button.addEventListener('click', () => { unlock(); document.querySelector('canvas')?.focus(); });
    document.body.append(button);
    refresh();
  });
})();
