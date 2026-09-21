import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Convenience re-exports so call sites only need this file's import to use
/// [FaIcon] (v11's Font Awesome icon widget, required for [FaIconData]).
export 'package:font_awesome_flutter/font_awesome_flutter.dart'
    show FaIcon, FaIconData;

/// Font Awesome icon set for the Griot 2.0 design system.
///
/// Central mapping from the Material [Icons] names previously used across the
/// app to their Font Awesome equivalents (solid style; brand style only where
/// no solid variant exists). Swapping or refining an icon app-wide is now a
/// one-line change in this file.
///
/// Font Awesome 11 icons are [FaIconData] and render with [FaIcon] instead of
/// the standard [Icon] widget.
///
/// Note: names intentionally mirror the Material [Icons] members they
/// replace, so the `constant_identifier_names` lint is suppressed below.
///
/// Style note: in Font Awesome 7 data, plain names refer to the *regular*
/// (outlined) variant when a `solid*` alias exists — the `solid*` prefix is
/// used here so every icon renders filled.
// ignore_for_file: constant_identifier_names
abstract final class AppIcons {
  // --- Brand icons (no solid/regular variant exists) ---
  static const FaIconData facebook = FontAwesomeIcons.facebookF;
  static const FaIconData alternate_email = FontAwesomeIcons.xTwitter;

  // --- Solid icons ---
  static const FaIconData account_circle_outlined =
      FontAwesomeIcons.solidCircleUser;
  static const FaIconData analytics_outlined = FontAwesomeIcons.chartColumn;
  static const FaIconData arrow_forward_ios = FontAwesomeIcons.chevronRight;
  static const FaIconData badge_outlined = FontAwesomeIcons.solidIdCard;
  static const FaIconData auto_awesome = FontAwesomeIcons.wandMagicSparkles;
  static const FaIconData auto_stories = FontAwesomeIcons.bookOpen;
  static const FaIconData auto_stories_outlined = FontAwesomeIcons.bookOpen;
  static const FaIconData autorenew = FontAwesomeIcons.rotate;
  static const FaIconData bedtime_outlined = FontAwesomeIcons.solidMoon;
  static const FaIconData bolt_outlined = FontAwesomeIcons.bolt;
  static const FaIconData bookmark = FontAwesomeIcons.solidBookmark;
  static const FaIconData bookmark_border = FontAwesomeIcons.solidBookmark;
  static const FaIconData bookmark_outline = FontAwesomeIcons.solidBookmark;
  static const FaIconData business_outlined = FontAwesomeIcons.solidBuilding;
  static const FaIconData calendar_today = FontAwesomeIcons.solidCalendarDays;
  static const FaIconData cancel = FontAwesomeIcons.xmark;
  static const FaIconData chat_bubble = FontAwesomeIcons.solidComment;
  static const FaIconData check = FontAwesomeIcons.check;
  static const FaIconData check_circle = FontAwesomeIcons.solidCircleCheck;
  static const FaIconData chevron_right = FontAwesomeIcons.chevronRight;
  static const FaIconData clear = FontAwesomeIcons.xmark;
  static const FaIconData clear_all = FontAwesomeIcons.broom;
  static const FaIconData close = FontAwesomeIcons.xmark;
  static const FaIconData crop_landscape = FontAwesomeIcons.tabletScreenButton;
  static const FaIconData crop_portrait = FontAwesomeIcons.mobileScreenButton;
  static const FaIconData crop_square = FontAwesomeIcons.solidSquare;
  static const FaIconData dark_mode_outlined = FontAwesomeIcons.solidMoon;
  static const FaIconData delete_forever = FontAwesomeIcons.trash;
  static const FaIconData download_done_rounded = FontAwesomeIcons.download;
  static const FaIconData edit = FontAwesomeIcons.pen;
  static const FaIconData edit_outlined = FontAwesomeIcons.pen;
  static const FaIconData email_outlined = FontAwesomeIcons.solidEnvelope;
  static const FaIconData emoji_events_outlined = FontAwesomeIcons.trophy;
  static const FaIconData error_outline = FontAwesomeIcons.circleExclamation;
  static const FaIconData explore = FontAwesomeIcons.solidCompass;
  static const FaIconData favorite = FontAwesomeIcons.solidHeart;
  static const FaIconData favorite_border = FontAwesomeIcons.solidHeart;
  static const FaIconData favorite_outline = FontAwesomeIcons.solidHeart;
  static const FaIconData filter_list = FontAwesomeIcons.filter;
  static const FaIconData filter_list_off = FontAwesomeIcons.filter;
  static const FaIconData flag_outlined = FontAwesomeIcons.solidFlag;
  static const FaIconData flash_off = FontAwesomeIcons.bolt;
  static const FaIconData flash_on = FontAwesomeIcons.bolt;
  static const FaIconData forward_10 = FontAwesomeIcons.forward;
  static const FaIconData headphones = FontAwesomeIcons.headphones;
  static const FaIconData history = FontAwesomeIcons.clockRotateLeft;
  static const FaIconData image_outlined = FontAwesomeIcons.solidImage;
  static const FaIconData info_outline = FontAwesomeIcons.circleInfo;
  static const FaIconData insights_outlined = FontAwesomeIcons.chartLine;
  static const FaIconData keyboard = FontAwesomeIcons.solidKeyboard;
  static const FaIconData language = FontAwesomeIcons.language;
  static const FaIconData lightbulb_outline = FontAwesomeIcons.solidLightbulb;
  static const FaIconData location_on = FontAwesomeIcons.locationDot;
  static const FaIconData lock_outline = FontAwesomeIcons.lock;
  static const FaIconData logout = FontAwesomeIcons.rightFromBracket;
  static const FaIconData menu_book_outlined = FontAwesomeIcons.bookOpen;
  static const FaIconData military_tech_outlined = FontAwesomeIcons.medal;
  static const FaIconData medal = FontAwesomeIcons.medal;
  static const FaIconData medal_outlined = FontAwesomeIcons.medal;
  static const FaIconData more_horiz = FontAwesomeIcons.ellipsis;
  static const FaIconData more_vert = FontAwesomeIcons.ellipsisVertical;
  static const FaIconData movie_creation_outlined =
      FontAwesomeIcons.clapperboard;
  static const FaIconData museum = FontAwesomeIcons.buildingColumns;
  static const FaIconData museum_outlined = FontAwesomeIcons.buildingColumns;
  static const FaIconData pause = FontAwesomeIcons.pause;
  static const FaIconData pause_circle_filled =
      FontAwesomeIcons.solidCirclePause;
  static const FaIconData people_outline = FontAwesomeIcons.users;
  static const FaIconData person_add_alt = FontAwesomeIcons.userPlus;
  static const FaIconData person_outline = FontAwesomeIcons.solidUser;
  static const FaIconData person_pin_outlined = FontAwesomeIcons.userTie;
  static const FaIconData place_outlined = FontAwesomeIcons.locationDot;
  static const FaIconData play_arrow = FontAwesomeIcons.play;
  static const FaIconData play_arrow_rounded = FontAwesomeIcons.play;
  static const FaIconData play_circle_filled = FontAwesomeIcons.solidCirclePlay;
  static const FaIconData play_circle_outline =
      FontAwesomeIcons.solidCirclePlay;
  static const FaIconData preview = FontAwesomeIcons.eye;
  static const FaIconData qr_code_scanner = FontAwesomeIcons.qrcode;
  static const FaIconData quiz = FontAwesomeIcons.solidCircleQuestion;
  static const FaIconData quiz_outlined = FontAwesomeIcons.solidCircleQuestion;
  static const FaIconData refresh = FontAwesomeIcons.rotate;
  static const FaIconData remove_red_eye_outlined = FontAwesomeIcons.eye;
  static const FaIconData repeat = FontAwesomeIcons.repeat;
  static const FaIconData replay_10 = FontAwesomeIcons.rotateLeft;
  static const FaIconData schedule = FontAwesomeIcons.solidClock;
  static const FaIconData search = FontAwesomeIcons.magnifyingGlass;
  static const FaIconData send = FontAwesomeIcons.solidPaperPlane;
  static const FaIconData share = FontAwesomeIcons.shareNodes;
  static const FaIconData share_outlined = FontAwesomeIcons.shareNodes;
  static const FaIconData speed = FontAwesomeIcons.gaugeHigh;
  static const FaIconData star = FontAwesomeIcons.solidStar;
  static const FaIconData task_alt = FontAwesomeIcons.solidCircleCheck;
  static const FaIconData timer_outlined = FontAwesomeIcons.stopwatch;
  static const FaIconData trending_up = FontAwesomeIcons.arrowTrendUp;
  static const FaIconData visibility = FontAwesomeIcons.eye;
  static const FaIconData visibility_off = FontAwesomeIcons.eyeSlash;
  static const FaIconData visibility_outlined = FontAwesomeIcons.eye;
  static const FaIconData volume_off = FontAwesomeIcons.volumeXmark;
  static const FaIconData volume_up = FontAwesomeIcons.volumeHigh;
  static const FaIconData warning_amber_rounded =
      FontAwesomeIcons.triangleExclamation;
  static const FaIconData wifi = FontAwesomeIcons.wifi;
  static const FaIconData wifi_off = FontAwesomeIcons.wifi;

  // --- Artifact & region icons (parity with web_extras.artifact_category_icon)
  static const FaIconData monument = FontAwesomeIcons.monument;
  static const FaIconData gopuram = FontAwesomeIcons.gopuram;
  static const FaIconData jar = FontAwesomeIcons.jar;
  static const FaIconData drum = FontAwesomeIcons.drum;
  static const FaIconData gem = FontAwesomeIcons.gem;
  static const FaIconData khanda = FontAwesomeIcons.khanda;
  static const FaIconData hammer = FontAwesomeIcons.hammer;
  static const FaIconData box_open = FontAwesomeIcons.boxOpen;
  static const FaIconData landmark = FontAwesomeIcons.landmark;
  static const FaIconData earth_africa = FontAwesomeIcons.earthAfrica;
  static const FaIconData fire = FontAwesomeIcons.fireFlameCurved;
  static const FaIconData masks_theater = FontAwesomeIcons.masksTheater;
  static const FaIconData scissors = FontAwesomeIcons.scissors;
  static const FaIconData scroll = FontAwesomeIcons.scroll;
  static const FaIconData mountain_sun = FontAwesomeIcons.mountainSun;
  static const FaIconData water = FontAwesomeIcons.water;
  static const FaIconData layerGroup = FontAwesomeIcons.layerGroup;

  /// Icon for an artifact category slug.
  ///
  /// Mirrors `artifact_category_icon` in the webapp.
  static FaIconData artifactCategory(String category) {
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
  static FaIconData fromEmoji(String emoji) {
    switch (emoji.trim()) {
      case '📖':
        return auto_stories;
      case '📚':
        return FontAwesomeIcons.book;
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
        return FontAwesomeIcons.water;
      case '🏆':
        return FontAwesomeIcons.trophy;
      case '🔍':
        return search;
      case '✍':
      case '✍️':
        return FontAwesomeIcons.featherPointed;
      case '⚡':
        return bolt_outlined;
      case '❤':
      case '❤️':
        return favorite;
      case '🤍':
        return FontAwesomeIcons.heart;
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
        return FontAwesomeIcons.medal;
      case '🎉':
        return FontAwesomeIcons.champagneGlasses;
      case '🎭':
        return masks_theater;
      case '🪘':
      case '🥁':
        return drum;
      case '🧭':
        return explore;
      case '🗂':
      case '🗂️':
        return FontAwesomeIcons.layerGroup;
      case '🔥':
        return fire;
      case '👋':
      case '🤲':
        return FontAwesomeIcons.hand;
      case '📊':
        return FontAwesomeIcons.chartSimple;
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
        return FontAwesomeIcons.flask;
      case '📦':
        return box_open;
      case '🛖':
        return FontAwesomeIcons.igloo;
      // Glyphs absent from the web ICON_MAP; mapped here so the Flutter app
      // never falls back to rendering emoji text.
      case '🌌':
        return FontAwesomeIcons.moon;
      case '💡':
        return lightbulb_outline;
      case '🎵':
        return FontAwesomeIcons.music;
      case '👣':
        return FontAwesomeIcons.shoePrints;
      case '🐛':
        return FontAwesomeIcons.bug;
      case '🛡':
      case '🛡️':
        return FontAwesomeIcons.shieldHalved;
      case '📝':
        return FontAwesomeIcons.penToSquare;
      case '🎓':
        return FontAwesomeIcons.graduationCap;
      case '💯':
        return FontAwesomeIcons.star;
      case '🗺':
      case '🗺️':
        return FontAwesomeIcons.map;
      case '✅':
        return check_circle;
      case '❌':
        return cancel;
      case '⚙':
      case '⚙️':
        return FontAwesomeIcons.gear;
      case '🇬🇧':
        return FontAwesomeIcons.earthEurope;
      case '🇫🇷':
        return FontAwesomeIcons.earthEurope;
      default:
        return auto_stories;
    }
  }

  static FaIconData role(String value) {
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
}
