import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../debug/debug_log.dart';
import 'secure_storage_factory.dart';

/// Encrypts PII columns at rest with AES-256-GCM.
///
/// `local_users` and `offline_users` hold a reader's email and name — data
/// that is useful offline but that nobody wants readable in a raw SQLite dump
/// from a rooted device or a stolen backup. The password already left the
/// database (see `LocalCredentialHasher`); this gives the rest of the
/// identity the same treatment without a SQLCipher migration.
///
/// Design:
///
/// * **One app-level key**, 32 random bytes, generated on first use and kept
///   in platform secure storage (Keystore/Keychain-backed). One key keeps
///   lookups and migrations simple — the tables are tiny and every row
///   belongs to the same device.
/// * **Transparent.** Values are stored as `enc.v1.<nonce>.<ct>.<mac>`.
///   Anything without the prefix is passed through untouched, so rows written
///   before this existed still read fine and migrate on their next write —
///   no schema change, no migration window.
/// * **Degrades to today's behaviour.** If the key cannot be read or written,
///   encryption falls back to storing the value as-is and decryption returns
///   an empty string rather than throwing: a profile with no email is better
///   than an auth flow that crashes.
///
/// Cipher instances are memoized per [FlutterSecureStorage] so every repo
/// sharing a storage object also shares one key — two repos racing to
/// generate a key would strand each other's ciphertext.
final class PiiCipher {
  PiiCipher({FlutterSecureStorage? storage})
    : _storage = storage ?? SecureStorageFactory.instance;

  static const String _prefix = 'enc.v1.';
  static const String _keyStorageKey = 'griot_pii_key_v1';

  static final Map<FlutterSecureStorage, PiiCipher> _instances = {};

  /// The cipher for the shared app storage.
  static final PiiCipher instance = PiiCipher();

  /// The cipher bound to [storage]. Same storage → same instance → same key.
  static PiiCipher forStorage(FlutterSecureStorage storage) =>
      _instances.putIfAbsent(storage, () => PiiCipher(storage: storage));

  final FlutterSecureStorage _storage;
  final AesGcm _aes = AesGcm.with256bits();
  Future<SecretKey>? _keyFuture;

  /// Whether [value] was written by this cipher.
  static bool isEncrypted(String value) => value.startsWith(_prefix);

  /// Encrypt [plain] for storage. Empty values and values that are already
  /// encrypted pass through unchanged.
  Future<String> encrypt(String plain) async {
    if (plain.isEmpty || isEncrypted(plain)) return plain;
    try {
      final key = await _key();
      final rng = Random.secure();
      final box = await _aes.encrypt(
        utf8.encode(plain),
        secretKey: key,
        nonce: List<int>.generate(12, (_) => rng.nextInt(256)),
      );
      return '$_prefix'
          '${base64Encode(box.nonce)}.'
          '${base64Encode(box.cipherText)}.'
          '${base64Encode(box.mac.bytes)}';
    } catch (e) {
      debugLog('[PiiCipher] encrypt failed, storing plaintext: $e');
      return plain;
    }
  }

  /// The original value of [stored]. Pre-encryption rows pass through;
  /// ciphertext that cannot be read (key gone, value tampered) comes back
  /// empty rather than throwing into an auth flow.
  Future<String> decrypt(String stored) async {
    if (stored.isEmpty || !isEncrypted(stored)) return stored;
    try {
      final parts = stored.substring(_prefix.length).split('.');
      if (parts.length != 3) return '';
      final box = SecretBox(
        base64Decode(parts[1]),
        nonce: base64Decode(parts[0]),
        mac: Mac(base64Decode(parts[2])),
      );
      final key = await _key();
      return utf8.decode(await _aes.decrypt(box, secretKey: key));
    } catch (e) {
      debugLog('[PiiCipher] decrypt failed, returning empty: $e');
      return '';
    }
  }

  Future<SecretKey> _key() => _keyFuture ??= _loadKey();

  Future<SecretKey> _loadKey() async {
    var stored = await _storage.read(key: _keyStorageKey);
    if (stored == null || stored.isEmpty) {
      final rng = Random.secure();
      final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
      stored = base64Encode(bytes);
      await _storage.write(key: _keyStorageKey, value: stored);
    }
    return SecretKey(base64Decode(stored));
  }
}
