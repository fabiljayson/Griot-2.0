import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single construction point for [FlutterSecureStorage].
///
/// Every repository used to build its own `const FlutterSecureStorage()`, which
/// meant the per-platform options had to be repeated — and the web ones, which
/// are the only ones that matter here, were never set at all.
///
/// ## Web storage
///
/// On web, `flutter_secure_storage` is backed by `localStorage`. Values are
/// AES-GCM encrypted, but **the AES key is written to the same
/// `localStorage`** unless a wrap key is supplied. That still stops a token
/// from being readable by a stray `localStorage.getItem`, an extension, or a
/// support engineer pasting the blob into a bug report — the common leak paths
/// — but it is not a defence against arbitrary JavaScript running on the page.
///
/// The real control against that is the Content-Security-Policy in
/// `web/index.html`: if injected script cannot run, the key next to the
/// ciphertext is unreadable. This class makes the two things that *are* in its
/// control explicit:
///
/// * **Session storage** (`useSessionStorage: true`). Tokens die with the tab.
///   A shared or kiosk machine no longer hands the next person a live session
///   out of `localStorage`, and closing the tab revokes the at-rest copy. The
///   cost is a re-login after a browser restart, which is the right trade for
///   a heritage-reading app that also works fully offline.
/// * **Optional wrap key.** Supply
///   `--dart-define=WEB_SECURE_STORAGE_WRAP_KEY=<base64 256-bit key>` and the
///   AES key is wrapped with RSA-OAEP against it, so the stored key material
///   is not usable on its own. Requires a secure context (HTTPS or localhost),
///   which is the same requirement the package already imposes.
///
/// The wrap key is a `String.fromEnvironment` constant, so it is compiled into
/// the bundle. That is not a substitute for CSP — a client-side app has no
/// server to keep a secret — it is a second layer that raises the cost of a
/// raw `localStorage` dump. Rotate it with a rebuild.
abstract final class SecureStorageFactory {
  /// Namespace prefix for the web key/ciphertext entries.
  static const String _webDbName = 'GriotSecureStorage';

  /// Base64 RSA-OAEP wrap key, injected at build time. Empty when unset.
  static const String _webWrapKey = String.fromEnvironment(
    'WEB_SECURE_STORAGE_WRAP_KEY',
  );

  /// Base64 IV for the wrap key. Required whenever a wrap key is supplied —
  /// the plugin base64-decodes it unconditionally when unwrapping, so an empty
  /// value throws on the first read rather than silently degrading.
  static const String _webWrapKeyIv = String.fromEnvironment(
    'WEB_SECURE_STORAGE_WRAP_KEY_IV',
  );

  /// The shared instance. Use this instead of constructing the plugin directly.
  static final FlutterSecureStorage instance = _build();

  static FlutterSecureStorage _build() {
    if (!kIsWeb) {
      // Native platforms use the platform keystore. `AndroidOptions` defaults
      // to AES-GCM with an RSA-OAEP wrapped Keystore key (EncryptedShared-
      // Preferences, the only option since v11), and `IOSOptions` pins the
      // accessibility class so the key never syncs to iCloud or leaks through
      // an unlocked-device backup.
      return const FlutterSecureStorage(
        aOptions: AndroidOptions(),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
    }

    final wrapKey = _webWrapKey.trim();
    final wrapKeyIv = _webWrapKeyIv.trim();
    return FlutterSecureStorage(
      webOptions: WebOptions(
        dbName: _webDbName,
        publicKey: _webDbName,
        useSessionStorage: true,
        wrapKey: wrapKey.isEmpty ? '' : wrapKey,
        wrapKeyIv: wrapKeyIv,
      ),
    );
  }

  /// True when a wrap key and its IV were both compiled in.
  static bool get hasWrapKey => _webWrapKey.trim().isNotEmpty;

  /// True when a wrap key was compiled in without the IV it needs.
  ///
  /// Surfaced as a warning in debug so a half-configured build is noticed at
  /// startup rather than at the first token read in production.
  static bool get isWrapKeyMisconfigured =>
      hasWrapKey && _webWrapKeyIv.trim().isEmpty;
}
