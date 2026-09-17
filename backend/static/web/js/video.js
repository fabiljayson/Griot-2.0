/**
 * AI video job polling — web mirror of the mobile VideoStatusPoller.
 * Refreshes the status badge while a Luma AI job is pending/processing (§7).
 */
(function () {
  'use strict';

  var section = document.querySelector('[data-video-poll]');
  if (!section) return;

  var slug = section.getAttribute('data-video-poll');
  var attempts = 0;
  var MAX_ATTEMPTS = 60; // ~5 minutes at 5s intervals

  function tick() {
    fetch('/actions/story/' + slug + '/video-status/', {
      headers: { 'X-Requested-With': 'fetch' },
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (data.status === 'completed' || data.status === 'failed') {
          window.location.reload();
          return;
        }
        attempts += 1;
        if (attempts < MAX_ATTEMPTS) setTimeout(tick, 5000);
      })
      .catch(function () {
        attempts += 1;
        if (attempts < MAX_ATTEMPTS) setTimeout(tick, 8000);
      });
  }

  setTimeout(tick, 5000);
})();
