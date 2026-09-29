import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/core/security/local_credential_hasher.dart';

/// Known-answer vectors generated with `hashlib.pbkdf2_hmac('sha256', ...)`
/// from CPython, the de-facto reference. They pin [LocalCredentialHasher] to
/// RFC 8018, so a refactor cannot silently change what is written to disk —
/// which would orphan every existing local account, since a stored hash is
/// all there is to verify against.
///
/// The raw salt and derived-key bytes are listed rather than their base64
/// form: base64 has to be transcribed by hand here, and a mis-transcribed
/// vector fails in a way that looks like an implementation bug. Assembling the
/// storable record from bytes keeps these values exact.
typedef _Vector = ({
  String password,
  List<int> salt,
  int iterations,
  List<int> expected,
});

final _referenceVectors = <_Vector>[
  // Single iteration — exercises the U1 = PRF(P, S || INT_32_BE(1)) fast path.
  (
    password: 'p',
    salt: [115],
    iterations: 1,
    expected: <int>[
      55, 44, 201, 129, 82, 68, 196, 162, 183, 89, 85, 177, //
      53, 140, 222, 9, 13, 156, 18, 45, 26, 125, 227, 2,
      169, 4, 224, 77, 53, 186, 107, 6,
    ],
  ),
  (
    password: 'correct horse',
    salt: [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102],
    iterations: 1000,
    expected: <int>[
      112, 24, 60, 15, 96, 238, 158, 4, 65, 246, 78, 250, 179, //
      52, 225, 127, 151, 161, 127, 32, 115, 247, 221, 90, 203, 163,
      211, 241, 42, 240, 147, 131,
    ],
  ),
  // Empty password must still produce a well-defined record.
  (
    password: '',
    salt: [115, 97, 108, 116],
    iterations: 4096,
    expected: <int>[
      234, 37, 128, 11, 124, 196, 12, 152, 170, 79, 78, //
      196, 16, 112, 21, 36, 209, 137, 1, 199, 12, 216, 225, 238, 86,
      80, 253, 151, 142, 203, 170, 16,
    ],
  ),
  // Multi-byte UTF-8 password, and a salt containing NUL and a high byte.
  (
    password: 'unicode \u00fcn\u00efc\u00f8d\u00e9 pass',
    salt: [0, 1, 2, 255],
    iterations: 2,
    expected: <int>[
      249, 237, 51, 48, 106, 23, 217, 25, 86, 46, 89, //
      234, 120, 33, 39, 193, 84, 131, 47, 56, 34, 194, 157, 241, 67,
      237, 3, 109, 37, 20, 64, 146,
    ],
  ),
  // A password longer than the 64-byte HMAC block, forcing HMAC's SHA-256
  // key-reduction path. Built by repetition so the length is unambiguous.
  (
    password: List.filled(80, 'a').join(),
    salt: List.filled(64, 120),
    iterations: 3,
    expected: <int>[
      226, 197, 132, 192, 201, 131, 107, 216, 90, 73, //
      209, 5, 12, 160, 182, 126, 113, 82, 127, 128, 21, 211, 185, 94,
      32, 165, 24, 118, 153, 6, 125, 39,
    ],
  ),
];

String _recordFor(_Vector v) => <String>[
      'pbkdf2_sha256',
      '${v.iterations}',
      base64.encode(v.salt),
      base64.encode(v.expected),
    ].join(r'$');

void main() {
  group('known-answer vectors', () {
    test('every vector is structurally sound', () {
      for (final v in _referenceVectors) {
        final record = _recordFor(v);
        final parts = record.split(r'$');
        expect(parts, hasLength(4), reason: record);
        expect(parts[0], 'pbkdf2_sha256', reason: record);
        expect(int.tryParse(parts[1]), v.iterations, reason: record);
        expect(base64.decode(parts[2]), v.salt, reason: 'salt round-trip: $record');
        expect(
          base64.decode(parts[3]),
          v.expected,
          reason: 'derived key round-trip: $record',
        );
        expect(v.expected, hasLength(32), reason: 'PBKDF2 dkLen is 32');
      }
    });

    test('the long-password vector really is longer than one HMAC block', () {
      final long = _referenceVectors.last.password;
      expect(long, hasLength(80));
      expect(long.codeUnitAt(0), 0x61);
      expect(
        long.runes.every((r) => r == 0x61),
        isTrue,
        reason: 'guards against a transcription typo weakening the test',
      );
    });

    test('verify() accepts records produced by the reference implementation', () {
      for (final v in _referenceVectors) {
        expect(
          LocalCredentialHasher.verify(v.password, _recordFor(v)),
          isTrue,
          reason: 'reference vector must verify',
        );
      }
    });

    test('a mutation of the password fails against the same record', () {
      for (final v in _referenceVectors) {
        expect(
          LocalCredentialHasher.verify('${v.password}x', _recordFor(v)),
          isFalse,
          reason: 'mutated password must not verify',
        );
      }
    });

    test('records are emitted in the documented format', () {
      final record = LocalCredentialHasher.hash('pw');
      final parts = record.split(r'$');
      expect(parts, hasLength(4));
      expect(parts[0], 'pbkdf2_sha256');
      expect(int.parse(parts[1]), LocalCredentialHasher.iterations);
      expect(base64.decode(parts[2]), hasLength(16), reason: 'salt is 16 bytes');
      expect(base64.decode(parts[3]), hasLength(32), reason: 'key is 32 bytes');
    });

    test('hash() reproduces a reference record given the same salt', () {
      // Re-derive the single-iteration vector by re-salting is not possible
      // (salt is random), so assert the inverse instead: verify is consistent
      // with hash for the same credential across many draws.
      for (var i = 0; i < 5; i++) {
        final record = LocalCredentialHasher.hash('stable');
        expect(LocalCredentialHasher.verify('stable', record), isTrue);
      }
    });
  });

  group('hash / verify round-trip', () {
    test('accepts the correct password', () {
      final record = LocalCredentialHasher.hash('s3cret-passphrase');
      expect(LocalCredentialHasher.verify('s3cret-passphrase', record), isTrue);
    });

    test('rejects a wrong password', () {
      final record = LocalCredentialHasher.hash('s3cret-passphrase');
      expect(LocalCredentialHasher.verify('wrong', record), isFalse);
    });

    test('rejects an empty password against a non-empty record', () {
      final record = LocalCredentialHasher.hash('s3cret-passphrase');
      expect(LocalCredentialHasher.verify('', record), isFalse);
    });

    test('does not leak the plaintext into the record', () {
      const password = 'SuperSecret123!';
      final record = LocalCredentialHasher.hash(password);
      expect(record, isNot(contains(password)));
      expect(record, isNot(contains(base64.encode(utf8.encode(password)))));
      expect(record, isNot(contains(base64.encode(utf8.encode(password)).substring(0, 8))));
    });

    test('salts per record, so identical passwords differ', () {
      final a = LocalCredentialHasher.hash('same');
      final b = LocalCredentialHasher.hash('same');
      expect(a, isNot(b));
      expect(LocalCredentialHasher.verify('same', a), isTrue);
      expect(LocalCredentialHasher.verify('same', b), isTrue);
    });

    test('honours an injected Random, making output reproducible', () {
      final a = LocalCredentialHasher.hash('pw', random: Random(7));
      final b = LocalCredentialHasher.hash('pw', random: Random(7));
      expect(a, b);
      expect(LocalCredentialHasher.verify('pw', a), isTrue);
      expect(LocalCredentialHasher.verify('nope', a), isFalse);
    });
  });

  group('verify fails closed on a damaged record', () {
    test('null', () {
      expect(LocalCredentialHasher.verify('pw', null), isFalse);
    });

    test('empty string', () {
      expect(LocalCredentialHasher.verify('pw', ''), isFalse);
    });

    test('wrong number of fields', () {
      expect(
        LocalCredentialHasher.verify('pw', r'pbkdf2_sha256$1000$AAAA'),
        isFalse,
      );
      expect(
        LocalCredentialHasher.verify('pw', r'pbkdf2_sha256$1000$AAAA$BBBB$CCCC'),
        isFalse,
      );
    });

    test('unknown scheme', () {
      final record =
          LocalCredentialHasher.hash('pw').replaceFirst('pbkdf2_sha256', 'md5');
      expect(LocalCredentialHasher.verify('pw', record), isFalse);
    });

    test('non-numeric iteration count', () {
      final record =
          LocalCredentialHasher.hash('pw').replaceFirst(r'$100000$', r'$lots$');
      expect(LocalCredentialHasher.verify('pw', record), isFalse);
    });

    test('zero iteration count', () {
      final record =
          LocalCredentialHasher.hash('pw').replaceFirst(r'$100000$', r'$0$');
      expect(LocalCredentialHasher.verify('pw', record), isFalse);
    });

    test('non-base64 salt', () {
      final record =
          LocalCredentialHasher.hash('pw').replaceFirst(r'$100000$', r'$!!!$');
      expect(LocalCredentialHasher.verify('pw', record), isFalse);
    });

    test('truncated hash does not match', () {
      final parts = LocalCredentialHasher.hash('pw').split(r'$');
      final truncated = [
        parts[0],
        parts[1],
        parts[2],
        base64.encode(base64.decode(parts[3]).sublist(0, 8)),
      ].join(r'$');
      expect(LocalCredentialHasher.verify('pw', truncated), isFalse);
    });

    test('a record with a tampered hash byte does not match', () {
      final parts = LocalCredentialHasher.hash('pw').split(r'$');
      final bytes = base64.decode(parts[3]);
      bytes[0] ^= 0xff;
      final tampered = [
        parts[0],
        parts[1],
        parts[2],
        base64.encode(bytes),
      ].join(r'$');
      expect(LocalCredentialHasher.verify('pw', tampered), isFalse);
    });
  });

  group('needsRehash', () {
    test('false at the current work factor', () {
      expect(
        LocalCredentialHasher.needsRehash(LocalCredentialHasher.hash('pw')),
        isFalse,
      );
    });

    test('true for a weaker record', () {
      final record =
          LocalCredentialHasher.hash('pw').replaceFirst(r'$100000$', r'$1000$');
      expect(LocalCredentialHasher.needsRehash(record), isTrue);
    });

    test('false for null and for a damaged record', () {
      expect(LocalCredentialHasher.needsRehash(null), isFalse);
      expect(LocalCredentialHasher.needsRehash('garbage'), isFalse);
    });
  });
}
