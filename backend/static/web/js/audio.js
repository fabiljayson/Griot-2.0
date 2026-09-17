/**
 * Audio narration player — web mirror of the mobile AudioPlayerSheet.
 * Custom play/pause button over a native <audio> element (§6 parity).
 */
(function () {
  'use strict';

  var toggle = document.getElementById('audio-toggle');
  var player = document.getElementById('story-audio');
  var icon = document.getElementById('audio-icon');
  if (!toggle || !player) return;

  var source = toggle.getAttribute('data-audio-src');
  if (!source) return;

  toggle.addEventListener('click', function () {
    if (player.paused) {
      if (!player.src) player.src = source;
      player.play().catch(function () {
        if (icon) icon.className = 'fa-solid fa-play';
      });
      if (icon) icon.className = 'fa-solid fa-pause';
    } else {
      player.pause();
      if (icon) icon.className = 'fa-solid fa-play';
    }
  });

  player.addEventListener('ended', function () {
    if (icon) icon.className = 'fa-solid fa-play';
  });
})();
