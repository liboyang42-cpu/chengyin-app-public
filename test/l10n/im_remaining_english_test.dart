import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/im/chat_card.dart';
import 'package:chengyin_app/feature/im/chat_review_result_sheet.dart';
import 'package:chengyin_app/feature/im/route_picker_sheet.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Topics implements TopicApi {
  @override
  Future<List<Topic>> list({int isMy = 0, String? keyword, String? categoryId,
    bool recommend = false, int pageNum = 1, int pageSize = 10}) async =>
      [Topic(id: 71, name: '用户的路线', introduction: '原始介绍')];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Future<void> Function(BuildContext) open) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(builder: (context) => CupertinoPageScaffold(child: Center(
    child: CupertinoButton(onPressed: () => open(context), child: const Text('Open')),
  ))),
);

void main() {
  test('notification fallback localizes without translating authored message content', () {
    final title = AppLocalizationsEn().imRemainingNotification;
    expect(parseChatCard('{"sub":"原始详情"}', notificationTitle: title)?.title, 'Notification');
    expect(parseChatCard('{"title":"通知"}', notificationTitle: title)?.title, '通知');
    expect(parseChatCard('{"sub":"原始详情"}', fallbackTitle: '通知', notificationTitle: title)?.title, '通知');
    expect(parseChatCard('{"sub":"原始详情"}')?.title, '通知');
  });

  testWidgets('English review labels preserve server outcome, reason and follow-up', (tester) async {
    await tester.pumpWidget(_app((context) => showChatReviewResult(context,
      const ChatCardResult(taskId: '007', bizId: 'B-2', outcome: '原始结论', reason: '原始原因', followUp: '原始后续'))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Review result'), findsOneWidget);
    expect(find.text('Review task #007 · Business item #B-2'), findsOneWidget);
    expect(find.text('原始结论'), findsOneWidget);
    expect(find.text('Reason: 原始原因'), findsOneWidget);
    expect(find.text('原始后续'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English route picker returns original ID and preserves route text', (tester) async {
    int? selected;
    await tester.pumpWidget(ProviderScope(overrides: [topicApiProvider.overrideWithValue(_Topics())],
      child: _app((context) async { selected = await pickRouteToShare(context); })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a route'), findsOneWidget);
    expect(find.text('用户的路线'), findsOneWidget);
    expect(find.text('原始介绍'), findsOneWidget);
    await tester.tap(find.byKey(const Key('route-pick-71')));
    await tester.pumpAndSettle();
    expect(selected, 71);
    expect(tester.takeException(), isNull);
  });
}
