import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/models/user_model.dart';

void main() {
  test('User serializes optional Firebase auth fields', () {
    final user = User.fromJson(const {
      'id': 'user-123',
      'email': 'demo@example.com',
      'display_name': 'Demo User',
      'is_online': true,
    });

    expect(user.id, 'user-123');
    expect(user.email, 'demo@example.com');
    expect(user.displayName, 'Demo User');
    expect(user.isOnline, isTrue);

    expect(user.toJson(), containsPair('email', 'demo@example.com'));
    expect(user.toJson(), containsPair('display_name', 'Demo User'));
  });
}
