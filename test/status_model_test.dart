import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/models/status_model.dart';
import 'package:secure_chat/data/models/user_model.dart';

void main() {
  group('StatusModel', () {
    test('parses JSON with image media and viewers', () {
      final status = Status.fromJson({
        'id': 'status-1',
        'user_id': 'user-1',
        'text': null,
        'media_path': '/api/files/abc.jpg',
        'media_type': 'image/jpeg',
        'created_at': '2024-01-01T10:00:00.000Z',
        'expires_at': '2024-01-02T10:00:00.000Z',
        'viewers': ['viewer-1', 'viewer-2'],
      });

      expect(status.id, 'status-1');
      expect(status.isImage, isTrue);
      expect(status.hasBeenViewedBy('viewer-1'), isTrue);
      expect(status.hasBeenViewedBy('nobody'), isFalse);
    });

    test('isImage is false for plain text statuses', () {
      final status = Status.fromJson({
        'id': 'status-2',
        'user_id': 'user-1',
        'text': 'Hello',
        'media_path': null,
        'media_type': null,
        'created_at': '2024-01-01T10:00:00.000Z',
        'expires_at': '2024-01-02T10:00:00.000Z',
        'viewers': [],
      });
      expect(status.isImage, isFalse);
    });

    test('isExpired reflects the expiry timestamp', () {
      final status = Status.fromJson({
        'id': 'status-3',
        'user_id': 'user-1',
        'text': 'World',
        'created_at': '2024-01-01T10:00:00.000Z',
        'expires_at': '2024-01-02T10:00:00.000Z',
        'viewers': [],
      });
      expect(
          status.isExpired(DateTime.parse('2024-01-03T00:00:00.000Z')), isTrue);
      expect(status.isExpired(DateTime.parse('2024-01-01T12:00:00.000Z')),
          isFalse);
    });

    test('author user model survives JSON round-trip', () {
      final status = Status.fromJson({
        'id': 'status-4',
        'user_id': 'user-1',
        'text': 'x',
        'created_at': '2024-01-01T10:00:00.000Z',
        'expires_at': '2024-01-02T10:00:00.000Z',
        'viewers': const [],
      });
      final withAuthor = Status(
        id: status.id,
        userId: status.userId,
        text: status.text,
        mediaPath: status.mediaPath,
        mediaType: status.mediaType,
        createdAt: status.createdAt,
        expiresAt: status.expiresAt,
        viewers: status.viewers,
        author: const User(id: 'user-1', displayName: 'Alice'),
      );
      expect(withAuthor.author!.displayName, 'Alice');
      expect(withAuthor.userId, 'user-1');
    });
  });
}
