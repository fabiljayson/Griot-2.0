// Keep the branded splash on screen for at least 5 seconds, then fade it away
// once Flutter has drawn its first frame. A safety timeout guarantees the page
// is never hidden behind the splash even if the app stalls.
//
// This lives in its own file rather than inline in index.html so the
// Content-Security-Policy can use `script-src 'self'` with no
// 'unsafe-inline' — an inline script cannot be exempted from a policy that
// blocks inline script, so moving it is what makes the policy possible at all.
(function () {
  var MIN_MS = 5000;
  var FADE_MS = 450;
  var startedAt = Date.now();
  var el = document.getElementById('griot-splash');
  if (!el) return;

  function hide() {
    var wait = Math.max(0, MIN_MS - (Date.now() - startedAt));
    setTimeout(function () {
      el.style.opacity = '0';
      setTimeout(function () {
        el.hidden = true;
      }, FADE_MS);
    }, wait);
  }

  window.addEventListener('flutter-first-frame', hide);
  setTimeout(hide, 20000); // safety: never trap the user
})();
