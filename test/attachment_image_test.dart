import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/core/theme/app_colors.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/presentation/widgets/attachment_image.dart';

void main() {
  testWidgets('missing file path shows a failure icon, not a lock', (
    tester,
  ) async {
    final message = Message(
      id: 'no-path',
      senderId: 'peer',
      receiverId: 'me',
      messageType: 'image',
      content: '',
      filePath: '',
      status: 'sent',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light()]),
        home: Scaffold(body: AttachmentImage(message: message)),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('null file path shows a failure icon', (tester) async {
    final message = Message(
      id: 'null-path',
      senderId: 'me',
      receiverId: 'peer',
      messageType: 'image',
      content: '',
      filePath: null,
      status: 'sending',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light()]),
        home: Scaffold(body: AttachmentImage(message: message)),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
