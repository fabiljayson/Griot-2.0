/// Discover feature — region browsing.
///
/// Home's "Discover Regions" strip used to be four hardcoded chips with a dead
/// `onTap`, no imagery and no data. This feature supplies the curated region
/// catalogue (each with its own photograph), real story counts from the local
/// database, and the per-region story list.
library;

// Models
export 'models/region_model.dart';

// Providers
export 'providers/region_provider.dart';

// Widgets
export 'widgets/region_card.dart';

// Screens
export 'screens/region_stories_screen.dart';
