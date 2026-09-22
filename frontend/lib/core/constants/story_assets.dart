/// Curated cover art bundled with the app.
///
/// The local story seed previously shipped **no** `cover_image` at all, so every
/// card fell back to a placeholder. Covers are keyed by story slug and bundled
/// from `assets/imagery/stories/` (all declared in `pubspec.yaml`).
///
/// Translated stories reuse their source-language cover — same story, same art.
abstract final class StoryCoverAssets {
  static const String _dir = 'assets/imagery/stories/';

  /// Slug → bundled asset path.
  static const Map<String, String> bySlug = {
    // English
    'anansi-wisdom-pot': '$_dir/anansi-wisdom-pot.jpg',
    'lions-bath': '$_dir/lions-bath.jpg',
    'talking-drum-foumban': '$_dir/talking-drum-foumban.jpg',
    'river-goddess': '$_dir/river-goddess.jpg',
    'chameleon-color': '$_dir/chameleon-color.jpg',
    'weaver-bird-lion': '$_dir/weaver-bird-lion.jpg',
    'moon-pot-stars': '$_dir/moon-pot-stars.jpg',

    // French translations share the original cover art.
    'anansi-wisdom-pot-fr': '$_dir/anansi-wisdom-pot.jpg',
    'lions-bath-fr': '$_dir/lions-bath.jpg',
    'talking-drum-foumban-fr': '$_dir/talking-drum-foumban.jpg',
    'river-goddess-fr': '$_dir/river-goddess.jpg',
    'chameleon-color-fr': '$_dir/chameleon-color.jpg',
    'weaver-bird-lion-fr': '$_dir/weaver-bird-lion.jpg',
    'moon-pot-stars-fr': '$_dir/moon-pot-stars.jpg',

    // Online library stories (seeded on the shared backend) — cover art is
    // shipped in the bundle so cards/detail render without hitting Render.
    'the-sacred-forest-of-foreke-dschang':
        '$_dir/the-sacred-forest-of-foreke-dschang.jpg',
    'the-ekom-nkam-waterfalls-where-tarzan-was-born':
        '$_dir/the-ekom-nkam-waterfalls-where-tarzan-was-born.jpg',
    'the-mysterious-lakes-of-manengouba':
        '$_dir/the-mysterious-lakes-of-manengouba.jpg',
    'bimbia-where-memory-lives': '$_dir/bimbia-where-memory-lives.jpg',
    'the-bamileke-guardians-of-the-highlands':
        '$_dir/the-bamileke-guardians-of-the-highlands.jpg',
    'the-baaka-pygmies-keepers-of-the-forest':
        '$_dir/the-baaka-pygmies-keepers-of-the-forest.jpg',
    'the-legend-of-mount-mbapits-crater-lake':
        '$_dir/the-legend-of-mount-mbapits-crater-lake.jpg',
  };

  /// Cover for [slug], or null when no bundled art exists.
  static String? forSlug(String slug) => bySlug[slug];

  /// Every bundled cover path (used by the asset smoke test).
  static List<String> get all => bySlug.values.toSet().toList();
}
