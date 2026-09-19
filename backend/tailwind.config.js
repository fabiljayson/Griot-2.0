/** Tailwind config for the Griot AI webapp.
 *
 * Used by the Tailwind CLI when compiling static/web/css/tailwind.css from
 * static/web/css/tailwind.input.css. The `config` directive in the input CSS
 * points here, so class semantics are identical to the old Play CDN setup.
 *
 * The theme itself lives in static/web/js/tailwind-theme.js so the browser
 * Play-CDN fallback (base.html) shares the exact same values.
 */
const GRIOT_TAILWIND_CONFIG = require('./static/web/js/tailwind-theme.js');

module.exports = {
  content: [
    './templates/**/*.html',
    './static/web/js/**/*.js',
    // Icon/typography helpers emit Tailwind classes from Python (web_extras).
    './web/**/*.py',
  ],
  darkMode: GRIOT_TAILWIND_CONFIG.darkMode,
  theme: GRIOT_TAILWIND_CONFIG.theme,
  plugins: [],
};
