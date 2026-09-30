import 'package:chengyin_app/feature/play/pack_opening_intro.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('public pack opens without a third-party animation asset', (
    WidgetTester tester,
  ) async {
    int completions = 0;
    await tester.pumpWidget(
      CupertinoApp(home: PackOpeningIntro(onDone: () => completions += 1)),
    );
    expect(find.byType(PackOpeningPoster), findsOneWidget);
    final Finder advance = find.bySemanticsLabel('继续开卡');
    await tester.tap(advance);
    await tester.tap(advance);
    await tester.tap(advance);
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 2600));
    expect(completions, 1);
    await tester.tap(find.text('跳过'));
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });
}
