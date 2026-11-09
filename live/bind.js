/* DSH LIVE bind —— 每 5 秒重新载入 live/live-data.js（bridge 生成），并通知页面刷新。
 * 若 index.html 有改动（bridge 上报 appMtime 变化），自动带新版本号重载页面，
 * 这样改完代码不用每次回 Lively 重新 Set as wallpaper。
 * 只读本地文件，不联网、不调用模型。
 */
(function () {
  var n = 0, timer = 0, seen = 0;
  function hardReload() {
    var q = '?v=' + Date.now() + (location.hash || '#ops');
    location.replace(location.pathname + q);
  }
  function load() {
    var s = document.createElement('script');
    s.src = 'live/live-data.js?t=' + Date.now() + '_' + (++n);
    s.onload = function () {
      try {
        var L = window.__DSH_LIVE__;
        if (L && L.appMtime) {
          if (seen && L.appMtime !== seen) { hardReload(); return; }
          seen = L.appMtime;
        }
        window.dispatchEvent(new Event('dsh-live'));
      } catch (e) {}
      if (s.parentNode) s.parentNode.removeChild(s);
    };
    s.onerror = function () { if (s.parentNode) s.parentNode.removeChild(s); };
    (document.head || document.documentElement).appendChild(s);
  }
  function start() { if (!timer) { load(); timer = setInterval(load, 5000); } }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
