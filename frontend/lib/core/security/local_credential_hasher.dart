import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Salted, iterated password hashing for **local-only** accounts.
///
/// ## Why this exists
///
/// The app is offline-first: a reader who registers with no connectivity has
/// to be able to sign in again later, still offline. That used to be
/// implemented by keeping the password verbatim in the `local_users` SQLite
/// table and comparing it with `WHERE username = ? AND password = ?`, which
/// meant any process that could read the database file — a rooted device, an
/// `adb backup` pull, a stolen phone — recovered the plaintext credential. The
/// credential is also a *real* one whenever the account exists on the backend,
/// so the leak reached the Django database too.
///
/// This replaces that with the same shape the server uses: a random per-user
/// salt, an iterated one-way function, and a length-independent comparison.
///
/// ## Format
///
/// ```text
/// pbkdf2_sha256$<iterations>$<salt-b64>$<hash-b64>
/// ```
///
/// Self-describing so the iteration count can be raised later without
/// invalidating existing hashes: [verify] re-hashes with whatever count is
/// stored in the record, and [needsRehash] reports when a stored hash was made
/// with fewer rounds than [iterations] so the caller can upgrade it on the next
/// successful sign-in.
///
/// This is not a substitute for the server's own hashing. It exists only so an
/// offline account can be verified locally without storing its secret.
class LocalCredentialHasher {
  const LocalCredentialHasher._();

  static const String _scheme = 'pbkdf2_sha256';

  /// Work factor: 600,000 rounds, the OWASP-recommended minimum for
  /// PBKDF2-HMAC-SHA256 (Password Storage Cheat Sheet). High enough to make an
  /// offline dictionary attack against a stolen database expensive, low enough
  /// that a sign-in on a budget phone stays imperceptible.
  ///
  /// [verify] honours whatever round count a record embeds, so hashes written
  /// at the old 100,000 rounds keep working; [needsRehash] then reports them
  /// as stale and the repository re-hashes them at this cost after the next
  /// successful sign-in.
  static const int iterations = 600000;

  /// Test-only override for the work factor used by [hash] and [needsRehash].
  ///
  /// A full-cost hash takes seconds in a debug VM — longer than the test
  /// runner's per-test timeout once a test hashes more than once — so suites
  /// that only need a *valid* record (not a realistically slow one) pin this
  /// low. Production never sets it: [iterations] is what lands on disk, and
  /// tests that must prove that clear the override explicitly.
  @visibleForTesting
  static int? debugOverrideIterations;

  static int get _rounds => debugOverrideIterations ?? iterations;

  /// 16 bytes of salt — 128 bits, above the 8-byte floor OWASP recommends.
  static const int _saltBytes = 16;

  static const int _hashBytes = 32;

  /// Hash [password] with a fresh random salt and return the storable record.
  ///
  /// The salt comes from [Random.secure], so two accounts that share a
  /// password still produce unrelated records.
  static String hash(String password, {Random? random}) {
    final salt = _randomBytes(_saltBytes, random);
    final derived = _pbkdf2(utf8.encode(password), salt, _rounds, _hashBytes);
    return [
      _scheme,
      '$_rounds',
      base64.encode(salt),
      base64.encode(derived),
    ].join(r'$');
  }

  /// Constant-time check of [password] against a [record] from [hash].
  ///
  /// Returns false for any record that is malformed or uses an unknown
  /// scheme, so a hand-edited or partially-migrated row fails closed rather
  /// than throwing or — worse — matching.
  static bool verify(String password, String? record) {
    if (record == null) return false;

    final parts = record.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;

    final parsedIterations = int.tryParse(parts[1]);
    if (parsedIterations == null || parsedIterations <= 0) return false;

    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64.decode(parts[2]);
      expected = base64.decode(parts[3]);
    } on FormatException {
      return false;
    }
    if (salt.isEmpty) return false;

    // Pin the derived key length. Deriving `expected.length` bytes instead
    // would let a tampered row shorten the stored hash and still authenticate:
    // an 8-byte truncation *is* the first 8 bytes of the real output, so the
    // record would verify while silently lowering the attacker's work factor.
    if (expected.length != _hashBytes) return false;

    final actual = _pbkdf2(utf8.encode(password), salt, parsedIterations, _hashBytes);
    return _constantTimeEquals(actual, expected);
  }

  /// Whether [record] was produced with fewer rounds than the current work
  /// factor, and so should be replaced after a successful sign-in.
  static bool needsRehash(String? record) {
    if (record == null) return false;
    final parts = record.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;
    final parsed = int.tryParse(parts[1]);
    return parsed == null || parsed < _rounds;
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018 §5.2) over `crypto`'s `Hmac` primitive.
  ///
  /// Only the standard construction is used — no bespoke mixing.
  static Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final blockCount = (keyLength / _hashBytes).ceil();
    final output = Uint8List(blockCount * _hashBytes);

    for (var block = 1; block <= blockCount; block++) {
      // U1 = PRF(P, S || INT_32_BE(block))
      final seeded = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..buffer.asByteData().setUint32(salt.length, block);

      var u = Uint8List.fromList(
        Hmac(sha256, password).convert(seeded).bytes,
      );
      final accumulator = Uint8List.fromList(u);

      for (var round = 1; round < iterations; round++) {
        u = Uint8List.fromList(Hmac(sha256, password).convert(u).bytes);
        for (var i = 0; i < accumulator.length; i++) {
          accumulator[i] ^= u[i];
        }
      }

      final offset = (block - 1) * _hashBytes;
      final take = min(_hashBytes, keyLength - offset);
      output.setRange(offset, offset + take, accumulator.take(take));
    }

    return Uint8List.fromList(output.take(keyLength).toList());
  }

  /// Length-independent, branch-free byte comparison.
  ///
  /// A plain `==` on the derived bytes would leak how much of a forged hash
  /// matched through timing.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Uint8List _randomBytes(int length, Random? random) {
    final source = random ?? Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = source.nextInt(256);
    }
    return bytes;
  }
}
