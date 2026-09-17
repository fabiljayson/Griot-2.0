/**
 * Story form helpers — markdown preview toggle (mirrors the mobile
 * StoryFormScreen preview chip).
 */
(function () {
  'use strict';

  var toggle = document.getElementById('preview-toggle');
  var editor = document.getElementById('id_content');
  var preview = document.getElementById('content-preview');
  if (!toggle || !editor || !preview) return;

  var visible = false;

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function renderPreview() {
    // Lightweight client-side preview: paragraphs, headings, quotes and
    // emphasis. The authoritative render stays server-side (web_extras.markdown).
    var lines = editor.value.replace(/\r\n/g, '\n').split('\n');
    var out = [];
    var paragraph = [];
    function flush() {
      if (paragraph.length) {
        out.push('<p>' + inline(paragraph.join(' ')) + '</p>');
        paragraph = [];
      }
    }
    function inline(text) {
      text = escapeHtml(text);
      text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
      text = text.replace(/\*([^*\n]+)\*/g, '<em>$1</em>');
      text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
      return text;
    }
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line.trim()) { flush(); continue; }
      var heading = line.match(/^(#{1,3})\s+(.*)$/);
      if (heading) { flush(); out.push('<h' + heading[1].length + '>' + inline(heading[2]) + '</h' + heading[1].length + '>'); continue; }
      if (line.trim().startsWith('>')) { flush(); out.push('<blockquote><p>' + inline(line.trim().slice(1)) + '</p></blockquote>'); continue; }
      paragraph.push(line.trim());
    }
    flush();
    preview.innerHTML = out.join('') || '<p class="text-secondary-text">Nothing to preview yet.</p>';
  }

  toggle.addEventListener('click', function () {
    visible = !visible;
    preview.classList.toggle('hidden', !visible);
    if (visible) renderPreview();
  });
})();
