/**
 * Griot AI web — Tailwind theme (single source of truth).
 *
 * Consumed in two places:
 *   1. tailwind.config.js reads this file at build time (Node CLI build of
 *      static/web/css/tailwind.css).
 *   2. base.html loads it in the browser so the Tailwind Play-CDN fallback
 *      produces identical class semantics when the local CSS build is
 *      missing or broken.
 *
 * Keep the palette WCAG 2.1 AA compliant (mirrors the mobile app theme).
 */
(function (root) {
  'use strict';

  root.GRIOT_TAILWIND_CONFIG = {
    darkMode: 'class',
    theme: {
      extend: {
        colors: {
          /* Primary — Royal Ndop indigo */
          'cam-indigo': { DEFAULT: '#1E2B58', dark: '#151F42', light: '#2A3B73' },
          /* Primary Accent — Foumban bronze
           *
           * `strong` is the *text* variant and is the one to reach for on any
           * label. The base bronze is 2.95:1 on white, which is fine as a fill
           * but far under the 4.5:1 WCAG 1.4.3 asks of text. It is a CSS custom
           * property rather than a fixed hex because it has to flip with the
           * `dark` class: #8A5D13 on the light ground, #D9A84D on the dark one.
           * A single fixed value cannot do both — #8A5D13 drops to 3.26:1 on
           * `bg-mud-charcoal`. The variable is defined in web/base.html so the
           * Tailwind CLI build and the Play-CDN fallback share it. */
          'cam-bronze': { DEFAULT: '#C68B29', dark: '#A67420', light: '#D9A84D', tint: '#F5ECD6', strong: 'rgb(var(--griot-accent-text) / <alpha-value>)' },
          /* Secondary Accent — Highland earth */
          'cam-earth': { DEFAULT: '#A0382B', dark: '#852D22', light: '#C44D3E', tint: '#F4DDD9' },
          /* Supporting Nature — Equatorial green */
          'cam-green': { DEFAULT: '#1B4332', dark: '#143326', light: '#2D6A4F', tint: '#D8E8E0' },
          /* Background Neutral — Raffia ivory */
          'cam-ivory': '#FBF9F4',
          /* Surface — Pure white for cards */
          'cam-white': '#FFFFFF',
          /* Dark Text — Slate charcoal */
          'cam-dark': '#1C1C1E',
          /* Secondary text */
          'cam-muted': '#6B7280',
          /* Error */
          'cam-error': '#D32F2F',
          /* Legacy aliases for backward compatibility */
          terracotta: { DEFAULT: '#C68B29', dark: '#A67420', tint: '#F5ECD6', strong: 'rgb(var(--griot-accent-text) / <alpha-value>)' },
          ochre: { DEFAULT: '#C68B29', dark: '#A67420', tint: '#F5ECD6', strong: 'rgb(var(--griot-accent-text) / <alpha-value>)' },
          savannah: { DEFAULT: '#1B4332', tint: '#D8E8E0' },
          sand: '#FBF9F4',
          'deep-earth': '#1C1C1E',
          'mud-charcoal': '#0F1219',
          'warm-brown': '#1E2B58',
          'secondary-text': '#6B7280',
          'brand-border': '#E5E7EB',
          'brand-error': '#D32F2F',
        },
        fontFamily: {
          display: ['Fraunces', 'Georgia', 'serif'],
          body: ['"Plus Jakarta Sans"', 'system-ui', 'sans-serif'],
        },
        borderRadius: {
          xl2: '1rem',
        },
      },
    },
  };

  /* CommonJS export so the Tailwind CLI (Node) can require() this file. */
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = root.GRIOT_TAILWIND_CONFIG;
  }
})(typeof window !== 'undefined' ? window : globalThis);
