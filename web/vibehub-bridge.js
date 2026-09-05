/* Single-player: local authority; no room or network simulation is created. */
(() => {
  const panel = document.createElement('div');
  panel.style.cssText = 'position:fixed;right:12px;top:10px;z-index:10000;display:flex;gap:8px;align-items:center;padding:6px 10px;background:#101820df;color:#c9d5ce;border:1px solid #426158;border-radius:6px;font:12px sans-serif';
  const status = document.createElement('span');
  status.textContent = '游客游玩';
  const login = document.createElement('button');
  login.textContent = '登录 VibeHub';
  const logout = document.createElement('button');
  logout.textContent = '退出账号';
  logout.hidden = true;
  panel.append(status, login, logout);
  document.body.append(panel);
  const focusGame = () => document.querySelector('canvas')?.focus();
  const fail = (error) => {
    status.textContent = '账号服务暂不可用，可继续游玩';
    console.warn('VibeHub account service:', error);
  };
  async function initialize() {
    if (!window.VibeHub) throw new Error('SDK unavailable');
    const vibe = await window.VibeHub.init({ work: 'kairull-zero-corridor' });
    vibe.onAuthChange(user => {
      status.textContent = user ? `已登录：${user.name}` : '游客游玩';
      login.hidden = !!user;
      logout.hidden = !user;
    });
    login.onclick = async () => { try { await vibe.login(); } catch (e) { fail(e); } finally { focusGame(); } };
    logout.onclick = async () => { try { await vibe.logout(); } catch (e) { fail(e); } finally { focusGame(); } };
  }
  initialize().catch(fail);
})();
