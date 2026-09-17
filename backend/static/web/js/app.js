/**
 * Griot AI web — shared client-side behaviors.
 * Vanilla JS only, mirroring the mobile app's interactions:
 * toasts, bottom sheets/modals, dark mode.
 */

(function () {
  'use strict';

  /* ── Toast auto-dismiss (mirrors mobile SnackBar) ─────────────────────── */
  var toasts = document.querySelectorAll('#toast-stack .toast');
  if (toasts.length) {
    setTimeout(function () {
      toasts.forEach(function (t) {
        t.style.transition = 'opacity .4s, transform .4s';
        t.style.opacity = '0';
        t.style.transform = 'translateY(-8px)';
        setTimeout(function () { t.remove(); }, 400);
      });
    }, 4000);
  }

  /* ── Bottom sheets / modals (mirrors mobile showModalBottomSheet) ─────── */
  document.addEventListener('click', function (e) {
    var opener = e.target.closest('[data-sheet-open]');
    if (opener) {
      var sheet = document.getElementById(opener.getAttribute('data-sheet-open'));
      if (sheet) {
        sheet.classList.remove('hidden');
        var panel = sheet.querySelector('.sheet-panel');
        if (panel) requestAnimationFrame(function () { panel.classList.add('sheet-open'); });
        document.body.style.overflow = 'hidden';
      }
      return;
    }

    var closer = e.target.closest('[data-sheet-close]');
    if (closer) {
      var openSheet = closer.closest('.sheet');
      if (openSheet) closeSheet(openSheet);
    }
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      document.querySelectorAll('.sheet:not(.hidden)').forEach(closeSheet);
    }
  });

  function closeSheet(sheet) {
    var panel = sheet.querySelector('.sheet-panel');
    if (panel) {
      panel.classList.remove('sheet-open');
      setTimeout(function () {
        sheet.classList.add('hidden');
        document.body.style.overflow = '';
      }, 150);
    } else {
      sheet.classList.add('hidden');
      document.body.style.overflow = '';
    }
  }

  /* Sheet slide-up animation */
  var style = document.createElement('style');
  style.textContent =
    '.sheet-panel{transform:translateY(16px);opacity:0;transition:transform .2s ease-out,opacity .2s ease-out}' +
    '@media(min-width:640px){.sheet-panel.sm\\:-translate-y-1\\/2{transform:translateY(16px) translateY(-50%)}}' +
    '.sheet-panel.sheet-open{transform:translateY(0);opacity:1}';
  document.head.appendChild(style);

  /* ── Confirm guards for destructive actions (mirrors mobile dialogs) ──── */
  document.querySelectorAll('[data-confirm]').forEach(function (el) {
    el.addEventListener('click', function (e) {
      if (!window.confirm(el.getAttribute('data-confirm'))) e.preventDefault();
    });
  });
})();
