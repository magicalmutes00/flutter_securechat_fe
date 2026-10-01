import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/services/in_app_notification_service.dart';

void main() {
  group('shouldRequestSessionReset', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('first failure always asks', () {
      expect(shouldRequestSessionReset(null, now), isTrue);
    });

    test('repeat failures inside the window stay quiet', () {
      expect(
        shouldRequestSessionReset(now.subtract(const Duration(minutes: 4, seconds: 59)), now),
        isFalse,
      );
    });

    test('failures past the window ask again', () {
      expect(
        shouldRequestSessionReset(now.subtract(const Duration(minutes: 5)), now),
        isTrue,
      );
      expect(
        shouldRequestSessionReset(now.subtract(const Duration(hours: 1)), now),
        isTrue,
      );
    });

    test('a custom interval applies', () {
      const interval = Duration(seconds: 30);
      expect(
        shouldRequestSessionReset(
          now.subtract(const Duration(seconds: 29)),
          now,
          minInterval: interval,
        ),
        isFalse,
      );
      expect(
        shouldRequestSessionReset(
          now.subtract(const Duration(seconds: 30)),
          now,
          minInterval: interval,
        ),
        isTrue,
      );
    });
  });
}
