// a2-club-entry 条目13:探店日期次的「带票分享」在 App 侧必须点得动,
// 且分享链接带**票源归因**参数 —— 真源
// `pages/club/detail/index.js:2653-2665` + `utils/ticket-source.js:146-157`:
//   https://api.example.invalid/topic/<topicId>?sourceClubId=<clubId>&clubCode=club-<clubId>-t<topicId>
// 两个参数都由真 ID 合成;标题用不带日期的原始主题名。
//
// 分享出口用 share_plus 的方法通道 mock 截获(不弹真分享面板;
// mock 的是插件自己的通道,不是替身实现)。

import 'package:flutter/material.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_edition_report_page.dart';

/// share_plus 12 的 platform interface 通道(见其 method_channel_share.dart)。
const MethodChannel _shareChannel = MethodChannel(
  'dev.fluttercommunity.plus/share',
);

void main() {
  final List<MethodCall> shareCalls = <MethodCall>[];

  setUp(() {
    shareCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, (MethodCall call) async {
          shareCalls.add(call);
          return 'shared';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null);
  });

  Future<void> pump(WidgetTester tester, List<EditionOption> editions, {Locale locale = const Locale('zh')}) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          clubEditionsProvider(3).overrideWith((ref) async => editions),
        ].cast(),
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const ClubEditionReportPage(clubId: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('English edition sharing preserves attribution and authored title', (tester) async {
    await pump(tester, [EditionOption(id: 77, label: '原始期次', topicName: '原始主题')],
      locale: const Locale('en'));
    expect(find.text('Discovery Day hours and evidence'), findsOneWidget);
    expect(find.text('Time to be confirmed · Operating club edition'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edition-share-77')));
    await tester.pumpAndSettle();
    final args = shareCalls.singleWhere((call) => call.method == 'share').arguments as Map<Object?, Object?>;
    expect(args['subject'], '原始主题');
    expect(args['text'], 'https://api.example.invalid/topic/77?sourceClubId=3&clubCode=club-3-t77');
    expect(tester.takeException(), isNull);
  });

  testWidgets('期次列表下每行出「带票分享」,链接带 sourceClubId+clubCode', (
    WidgetTester tester,
  ) async {
    await pump(tester, <EditionOption>[
      EditionOption(
        id: 77,
        label: '静安夜跑(2026-09-01)',
        topicName: '静安夜跑',
        startDate: '2026-09-01',
      ),
    ]);
    await tester.tap(find.byKey(const Key('edition-share-77')));
    await tester.pumpAndSettle();
    final MethodCall call = shareCalls.singleWhere(
      (MethodCall c) => c.method == 'share',
    );
    final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    expect(args['subject'], '静安夜跑');
    expect(
      args['text'],
      'https://api.example.invalid/topic/77'
      '?sourceClubId=3&clubCode=club-3-t77',
    );
  });

  testWidgets('缺名字/缺日期的期次:标题退到「城瘾」,行内标「时间待定」,不造码', (WidgetTester tester) async {
    await pump(tester, <EditionOption>[EditionOption(id: 88, label: '期次 #88')]);
    expect(find.text('时间待定 · 执行俱乐部期次'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edition-share-88')));
    await tester.pumpAndSettle();
    final Map<Object?, Object?> args =
        shareCalls.singleWhere((MethodCall c) => c.method == 'share').arguments
            as Map<Object?, Object?>;
    expect(args['subject'], '城瘾');
    expect(
      args['text'],
      'https://api.example.invalid/topic/88'
      '?sourceClubId=3&clubCode=club-3-t88',
      reason: 'clubCode 只由真 ID 合成(topicId=88 来自后端列表)',
    );
  });

  testWidgets('没有期次 → 分享区不出现(不说空话)', (WidgetTester tester) async {
    await pump(tester, <EditionOption>[]);
    expect(find.text('本俱乐部当前没有已开售的探店日期次。期次要在平台开售冻结之后才会出现在这里。'), findsOneWidget);
    expect(find.byKey(const Key('edition-share-77')), findsNothing);
    expect(shareCalls.where((MethodCall c) => c.method == 'share'), isEmpty);
  });
}
