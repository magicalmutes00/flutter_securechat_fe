import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/core/theme/app_colors.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/presentation/widgets/encrypted_image.dart';

void main() {
  testWidgets('hosted media without a key fails closed', (tester) async {
    final message = Message(
      id: 'keyless-media',
      senderId: 'peer',
      receiverId: 'me',
      messageType: 'image',
      content: '',
      filePath: '/api/files/keyless-media',
      status: 'sent',
      createdAt: DateTime.utc(2026, 1, 1),
      encryption: 'none',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light()]),
        home: Scaffold(body: EncryptedImage(message: message)),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
