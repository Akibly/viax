import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vivax/data/content_hash.dart';

/// Known-answer tests from FIPS 180-4 and RFC 6234.
///
/// This matters more than most tests here: the hash is the de-duplication key
/// for uploaded documents, and a subtly wrong implementation would not throw —
/// it would quietly let two different files share an identity, or stop a
/// re-upload from being recognised. Either way the failure would surface as
/// confusing behaviour long after the cause.
void main() {
  group('SHA-256 known vectors', () {
    test('empty input', () {
      expect(
        contentFingerprint(const []),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('"abc"', () {
      expect(
        contentFingerprint(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('two-block message', () {
      // 56 bytes: crosses the padding boundary, which is where a naive
      // implementation goes wrong.
      expect(
        contentFingerprint(utf8.encode(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        )),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('one million "a"', () {
      // Exercises the multi-block loop far past the first chunk.
      expect(
        contentFingerprint(List.filled(1000000, 0x61)),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });

  group('shape', () {
    test('always 64 lowercase hex characters', () {
      for (final input in [
        <int>[],
        [0],
        [255, 0, 128],
        utf8.encode('ViaX'),
      ]) {
        final digest = contentFingerprint(input);
        expect(digest.length, 64, reason: 'the column constrains this to 64');
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
      }
    });

    test('a single changed byte changes the digest', () {
      // De-duplication depends on this: two documents differing anywhere must
      // not be treated as the same upload.
      final a = contentFingerprint(utf8.encode('Operating Systems notes'));
      final b = contentFingerprint(utf8.encode('Operating Systems notez'));
      expect(a, isNot(equals(b)));
    });
  });
}
