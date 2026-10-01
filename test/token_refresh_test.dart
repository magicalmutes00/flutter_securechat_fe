import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/services/api_client.dart';

/// Unsigned JWT with a controlled `exp` claim (signature is irrelevant: the
/// check only reads the payload, the server verifies on use).
String _jwt(Map<String, dynamic> payload) {
  String part(Object o) => base64Url
      .encode(utf8.encode(jsonEncode(o)))
      .replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(payload)}.sig';
}

void main() {
  group('ApiClient.isExpiringSoon', () {
    final now = DateTime.utc(2026, 5, 1, 12);
    const threshold = Duration(minutes: 15);
    int epoch(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

    test('fresh token is not soon', () {
      final token = _jwt({'exp': epoch(now.add(const Duration(hours: 23)))});
      expect(ApiClient.isExpiringSoon(token, now, threshold), isFalse);
    });

    test('token expiring inside the window is soon', () {
      final token = _jwt({'exp': epoch(now.add(const Duration(minutes: 5)))});
      expect(ApiClient.isExpiringSoon(token, now, threshold), isTrue);
    });

    test('exactly at the threshold counts as soon', () {
      final token = _jwt({'exp': epoch(now.add(threshold))});
      expect(ApiClient.isExpiringSoon(token, now, threshold), isTrue);
    });

    test('already-expired token is soon (needs rotation)', () {
      final token =
          _jwt({'exp': epoch(now.subtract(const Duration(hours: 1)))});
      expect(ApiClient.isExpiringSoon(token, now, threshold), isTrue);
    });

    test('malformed tokens are not soon (the 401 path handles them)', () {
      expect(ApiClient.isExpiringSoon('garbage', now, threshold), isFalse);
      expect(ApiClient.isExpiringSoon('a.b', now, threshold), isFalse);
      expect(ApiClient.isExpiringSoon(_jwt({}), now, threshold), isFalse);
      expect(
        ApiClient.isExpiringSoon(_jwt({'exp': 'soon'}), now, threshold),
        isFalse,
      );
    });
  });
}
