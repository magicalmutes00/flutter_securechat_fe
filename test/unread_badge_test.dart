import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/presentation/widgets/ui/unread_badge.dart';

Future<void> _pumpBadge(WidgetTester tester, Widget badge) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Wide parent: reproduces the ListTile.trailing Column that used
        // to stretch the badge into a full-width bar.
        body: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [badge],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _badgeWidth(WidgetTester tester) {
  final box = tester.renderObject(find.byType(UnreadBadge)) as RenderBox;
  return box.size.width;
}

void main() {
  testWidgets('single digit badge stays a compact circle', (tester) async {
    await _pumpBadge(tester, const UnreadBadge(count: 3));

    expect(find.text('3'), findsOneWidget);
    final width = _badgeWidth(tester);
    expect(width, lessThan(40));
    expect(width, greaterThanOrEqualTo(18));
  });

  testWidgets('two digits form a slightly wider pill, never full width',
      (tester) async {
    await _pumpBadge(tester, const UnreadBadge(count: 42));

    expect(find.text('42'), findsOneWidget);
    final width = _badgeWidth(tester);
    expect(width, lessThan(60));
  });

  testWidgets('counts of 100 or more show 99+', (tester) async {
    await _pumpBadge(tester, const UnreadBadge(count: 150));

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('150'), findsNothing);
  });

  testWidgets('badge hides when the count is zero', (tester) async {
    await _pumpBadge(tester, const UnreadBadge(count: 0));

    expect(find.byType(UnreadBadge), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(_badgeWidth(tester), 0);
  });
}
