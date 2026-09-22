import 'package:flutter/material.dart';

/// Icon set for the Griot 2.0 design system.
///
/// A single, deliberate **outline** vocabulary drawn from Material's
/// `*_outlined` families, matching the line-icon sheet supplied in
/// `UI model/fonts.jpeg` (and the thin-stroke icons in the navigation-bar and
/// onboarding references). The app previously rendered Font Awesome *solid*
/// glyphs everywhere, which read as heavy against the web's light, hairline
/// treatment.
///
/// Every icon in the app resolves through this file, so changing the icon
/// language app-wide is a one-file edit. Member names intentionally mirror the
/// Material [Icons] members they replace so call sites stay readable; the
/// `constant_identifier_names` lint is suppressed below because a handful keep
/// their historical suffixes (`search`, `chevron_right`).
///
/// Two deliberate exceptions to the outline rule: the like and bookmark
/// toggles keep a filled "on" state ([favorite], [bookmark]) because they are
/// the only place where state would otherwise be conveyed by colour alone.
// ignore_for_file: constant_identifier_names
abstract final class AppIcons {
  // --- Brand marks (outline glyphs do not exist for third-party logos) ---
  static const IconData facebook = Icons.facebook;
  static const IconData alternate_email = Icons.alternate_email;

  // --- Navigation & chrome ---
  static const IconData account_circle_outlined = Icons.account_circle_outlined;
  static const IconData analytics_outlined = Icons.analytics_outlined;
  static const IconData arrow_forward_ios = Icons.chevron_right;
  static const IconData badge_outlined = Icons.badge_outlined;
  static const IconData auto_awesome = Icons.auto_awesome_outlined;
  static const IconData auto_stories = Icons.auto_stories_outlined;
  static const IconData auto_stories_outlined = Icons.auto_stories_outlined;
  static const IconData autorenew = Icons.autorenew_outlined;
  static const IconData bedtime_outlined = Icons.bedtime_outlined;
  static const IconData bolt_outlined = Icons.bolt_outlined;
  static const IconData business_outlined = Icons.business_outlined;
  static const IconData calendar_today = Icons.calendar_today_outlined;
  static const IconData chat_bubble = Icons.chat_bubble_outline;
  static const IconData clear = Icons.close;
  static const IconData clear_all = Icons.clear_all_outlined;
  static const IconData close = Icons.close;
  static const IconData dark_mode_outlined = Icons.dark_mode_outlined;
  static const IconData download_done_rounded = Icons.download_done_outlined;
  static const IconData edit = Icons.edit_outlined;
  static const IconData edit_outlined = Icons.edit_outlined;
  static const IconData email_outlined = Icons.email_outlined;
  static const IconData error_outline = Icons.error_outline;
  static const IconData explore = Icons.explore_outlined;
  static const IconData filter_list = Icons.filter_list_outlined;
  static const IconData filter_list_off = Icons.filter_list_off_outlined;
  static const IconData flag_outlined = Icons.flag_outlined;
  static const IconData flash_off = Icons.flash_off_outlined;
  static const IconData flash_on = Icons.flash_on_outlined;
  static const IconData history = Icons.history_outlined;
  static const IconData image_outlined = Icons.image_outlined;
  static const IconData info_outline = Icons.info_outline;
  static const IconData insights_outlined = Icons.insights_outlined;
  static const IconData keyboard = Icons.keyboard_outlined;
  static const IconData language = Icons.language_outlined;
  static const IconData lightbulb_outline = Icons.lightbulb_outline;
  static const IconData location_on = Icons.location_on_outlined;
  static const IconData lock_outline = Icons.lock_outline;
  static const IconData logout = Icons.logout_outlined;
  static const IconData menu_book_outlined = Icons.menu_book_outlined;
  static const IconData chevron_right = Icons.chevron_right;
  static const IconData more_horiz = Icons.more_horiz;
  static const IconData more_vert = Icons.more_vert;
  static const IconData pause_circle_filled = Icons.pause_circle_filled;
  static const IconData people_outline = Icons.people_outline;
  static const IconData person_add_alt = Icons.person_add_outlined;
  static const IconData person_outline = Icons.person_outline;
  static const IconData person_pin_outlined = Icons.person_pin_outlined;
  static const IconData place_outlined = Icons.place_outlined;
  static const IconData preview = Icons.preview_outlined;
  static const IconData refresh = Icons.refresh_outlined;
  static const IconData repeat = Icons.repeat_outlined;
  static const IconData schedule = Icons.schedule_outlined;
  static const IconData search = Icons.search_outlined;
  static const IconData send = Icons.send_outlined;
  static const IconData settings_outlined = Icons.settings_outlined;
  static const IconData share = Icons.share_outlined;
  static const IconData share_outlined = Icons.share_outlined;
  static const IconData speed = Icons.speed_outlined;
  static const IconData task_alt = Icons.task_alt_outlined;
  static const IconData timer_outlined = Icons.timer_outlined;
  static const IconData trending_up = Icons.trending_up_outlined;
  static const IconData visibility = Icons.visibility_outlined;
  static const IconData visibility_off = Icons.visibility_off_outlined;
  static const IconData visibility_outlined = Icons.visibility_outlined;
  static const IconData volume_off = Icons.volume_off_outlined;
  static const IconData volume_up = Icons.volume_up_outlined;
  static const IconData warning_amber_rounded = Icons.warning_amber_rounded;
  static const IconData wifi = Icons.wifi_outlined;
  static const IconData wifi_off = Icons.wifi_off_outlined;

  // --- Media playback ---
  static const IconData forward_10 = Icons.forward_10_outlined;
  static const IconData headphones = Icons.headphones_outlined;
  static const IconData movie_creation_outlined = Icons.movie_creation_outlined;
  static const IconData pause = Icons.pause;
  static const IconData play_arrow = Icons.play_arrow;
  static const IconData play_arrow_rounded = Icons.play_arrow_rounded;
  static const IconData play_circle_filled = Icons.play_circle_filled;
  static const IconData play_circle_outline = Icons.play_circle_outline;
  static const IconData replay_10 = Icons.replay_10_outlined;

  // --- State toggles (filled "on" state, outlined "off" state) ---
  static const IconData check = Icons.check;
  static const IconData check_circle = Icons.check_circle_outlined;
  static const IconData favorite = Icons.favorite;
  static const IconData favorite_border = Icons.favorite_border;
  static const IconData favorite_outline = Icons.favorite_border;
  static const IconData bookmark = Icons.bookmark;
  static const IconData bookmark_border = Icons.bookmark_border;
  static const IconData bookmark_outline = Icons.bookmark_border;
  static const IconData star = Icons.star;
  static const IconData cancel = Icons.cancel_outlined;
  static const IconData delete_forever = Icons.delete_forever_outlined;
  static const IconData emoji_events_outlined = Icons.emoji_events_outlined;
  static const IconData remove_red_eye_outlined =
      Icons.remove_red_eye_outlined;

  // --- Crop / aspect ratio (video generation) ---
  static const IconData crop_landscape = Icons.crop_landscape_outlined;
  static const IconData crop_portrait = Icons.crop_portrait_outlined;
  static const IconData crop_square = Icons.crop_square_outlined;

  // --- Discovery & achievements ---
  static const IconData auto_awesome_outlined = Icons.auto_awesome_outlined;

  /// Medal / milestone marker. Material has no `medal_outlined`.
  static const IconData medal = Icons.workspace_premium_outlined;
  static const IconData medal_outlined = Icons.workspace_premium_outlined;
  static const IconData military_tech_outlined = Icons.military_tech_outlined;
  static const IconData qr_code_scanner = Icons.qr_code_scanner_outlined;
  static const IconData quiz = Icons.quiz_outlined;
  static const IconData quiz_outlined = Icons.quiz_outlined;

  // --- Artifact & region icons (parity with web_extras.artifact_category_icon)
  /// Monument / sculpture. Material has no `monument`; the classical colonnade
  /// reads as architecture and is used for both.
  static const IconData monument = Icons.account_balance_outlined;
  static const IconData gopuram = Icons.temple_hindu_outlined;
  static const IconData jar = Icons.liquor_outlined;
  static const IconData drum = Icons.piano_outlined;
  static const IconData gem = Icons.diamond_outlined;
  static const IconData khanda = Icons.gavel_outlined;
  static const IconData hammer = Icons.handyman_outlined;
  static const IconData box_open = Icons.inventory_2_outlined;
  static const IconData landmark = Icons.account_balance_outlined;
  static const IconData earth_africa = Icons.public_outlined;
  static const IconData fire = Icons.local_fire_department_outlined;
  static const IconData masks_theater = Icons.theater_comedy_outlined;
  static const IconData scissors = Icons.content_cut_outlined;
  static const IconData scroll = Icons.article_outlined;
  static const IconData mountain_sun = Icons.landscape_outlined;
  static const IconData water = Icons.waves_outlined;
  static const IconData layerGroup = Icons.layers_outlined;
  static const IconData museum = Icons.museum_outlined;

  /// Icon for an artifact category slug.
  ///
  /// Mirrors `artifact_category_icon` in the webapp.
  static IconData artifactCategory(String category) {
    switch (category) {
      case 'sculpture':
        return monument;
      case 'textile':
        return scissors;
      case 'instrument':
        return drum;
      case 'jewelry':
        return gem;
      case 'pottery':
        return jar;
      case 'mask':
        return masks_theater;
      case 'weapon':
        return khanda;
      case 'fabric':
        return scroll;
      case 'tool':
        return hammer;
      default:
        return box_open;
    }
  }

  /// Maps a DB-stored emoji glyph (categories, badges, languages) to a real
  /// icon, so no screen ever renders a decorative emoji as UI text.
  ///
  /// Ports `ICON_MAP` from the webapp's `web_extras.py` and extends it with
  /// the glyphs the web mapping is missing, so both platforms stay in step.
  static IconData fromEmoji(String emoji) {
    switch (emoji.trim()) {
      case '📖':
        return auto_stories;
      case '📚':
        return menu_book_outlined;
      case '🏛':
      case '🏛️':
        return landmark;
      case '🗿':
        return monument;
      case '🛕':
        return gopuram;
      case '🌄':
        return mountain_sun;
      case '🌊':
        return water;
      case '🏆':
        return emoji_events_outlined;
      case '🔍':
        return search;
      case '✍':
      case '✍️':
        return create_outlined;
      case '⚡':
        return bolt_outlined;
      case '❤':
      case '❤️':
        return favorite;
      case '🤍':
        return favorite_border;
      case '🔖':
        return bookmark;
      case '📑':
        return bookmark_border;
      case '👁':
        return visibility_outlined;
      case '🌍':
      case '🌐':
        return earth_africa;
      case '🥇':
        return medal;
      case '🎉':
        return celebration_outlined;
      case '🎭':
        return masks_theater;
      case '🪘':
      case '🥁':
        return drum;
      case '🧭':
        return explore;
      case '🗂':
      case '🗂️':
        return layerGroup;
      case '🔥':
        return fire;
      case '👋':
      case '🤲':
        return emoji_people_outlined;
      case '📊':
        return bar_chart_outlined;
      case '🗡':
      case '🗡️':
      case '⚔':
      case '⚔️':
        return khanda;
      case '🧵':
        return scissors;
      case '🏺':
        return jar;
      case '💎':
        return gem;
      case '🔨':
      case '🔧':
        return hammer;
      case '⚗':
      case '⚗️':
        return science_outlined;
      case '📦':
        return box_open;
      case '🛖':
        return cottage_outlined;
      // Glyphs absent from the web ICON_MAP; mapped here so the Flutter app
      // never falls back to rendering emoji text.
      case '🌌':
        return dark_mode_outlined;
      case '💡':
        return lightbulb_outline;
      case '🎵':
        return music_note_outlined;
      case '👣':
        return directions_walk_outlined;
      case '🐛':
        return bug_report_outlined;
      case '🛡':
      case '🛡️':
        return shield_outlined;
      case '📝':
        return edit_note_outlined;
      case '🎓':
        return school_outlined;
      case '💯':
        return star;
      case '🗺':
      case '🗺️':
        return map_outlined;
      case '✅':
        return check_circle;
      case '❌':
        return cancel;
      case '⚙':
      case '⚙️':
        return settings_outlined;
      case '🇬🇧':
      case '🇫🇷':
        return language;
      default:
        return auto_stories;
    }
  }

  static IconData role(String value) {
    switch (value) {
      case 'contributor':
        return edit_outlined;
      case 'institution_manager':
        return museum_outlined;
      case 'admin':
        return account_circle_outlined;
      default:
        return explore;
    }
  }

  // --- Glyphs referenced directly by the helpers above ---
  static const IconData bar_chart_outlined = Icons.bar_chart_outlined;
  static const IconData celebration_outlined = Icons.celebration_outlined;
  static const IconData cottage_outlined = Icons.cottage_outlined;
  static const IconData create_outlined = Icons.create_outlined;
  static const IconData directions_walk_outlined =
      Icons.directions_walk_outlined;
  static const IconData bug_report_outlined = Icons.bug_report_outlined;
  static const IconData edit_note_outlined = Icons.edit_note_outlined;
  static const IconData emoji_people_outlined = Icons.emoji_people_outlined;
  static const IconData map_outlined = Icons.map_outlined;
  static const IconData music_note_outlined = Icons.music_note_outlined;
  static const IconData museum_outlined = Icons.museum_outlined;
  static const IconData school_outlined = Icons.school_outlined;
  static const IconData science_outlined = Icons.science_outlined;
  static const IconData shield_outlined = Icons.shield_outlined;
}
