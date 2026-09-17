/**
 * Story detail page behaviors.
 * - Scroll-based reading progress (auto-saves like the mobile reader).
 * - Share via Web Share API when available, falling back to the sheet.
 */
(function () {
  'use strict';

  var article = document.querySelector('[data-story-slug]');
  if (!article) return;

  var slug = article.getAttribute('data-story-slug');
  var label = document.getElementById('progress-label');
  var lastSent = 0;
  var authenticated = document.body.dataset.authenticated === 'true';

  /* ── Reading progress (mirrors mobile scroll tracking → progress API) ── */
  function computePercent() {
    var rect = article.getBoundingClientRect();
    var total = rect.height - window.innerHeight;
    if (total <= 0) return 100;
    var scrolled = Math.min(Math.max(-rect.top, 0), total);
    return Math.round((scrolled / total) * 100);
  }

  var throttle = null;
  window.addEventListener('scroll', function () {
    if (throttle) return;
    throttle = setTimeout(function () {
      throttle = null;
      if (!authenticated) return;
      var pct = computePercent();
      if (label) label.textContent = pct + '%';
      if (pct - lastSent >= 20 || (pct >= 95 && lastSent < 95)) {
        lastSent = pct;
        var url = '/actions/story/' + slug + '/progress/';
        var body = new URLSearchParams();
        body.set('progress_percent', String(pct));
        body.set('next', window.location.pathname);
        if (window.csrfToken) body.set('csrfmiddlewaretoken', window.csrfToken);
        fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'fetch' },
          body: body.toString(),
          keepalive: true,
        }).catch(function () { /* offline — the queue mirrors mobile behavior */ });
      }
    }, 400);
  }, { passive: true });

  /* ── Native share when supported (mirrors mobile share_plus) ──────────── */
  var targets = {};
  var raw = document.getElementById('share-targets');
  if (raw) { try { targets = JSON.parse(raw.textContent); } catch (e) {} }

  document.querySelectorAll('[data-sheet-open="share-sheet"]').forEach(function (btn) {
    if (!(navigator.share && targets.story_url)) return;
    btn.addEventListener('click', function (e) {
      e.stopImmediatePropagation();
      navigator.share({
        title: targets.story_title || document.title,
        text: targets.share_text || '',
        url: targets.story_url,
      }).catch(function () { /* user cancelled — keep sheet closed */ });
    }, true);
  });
})();
