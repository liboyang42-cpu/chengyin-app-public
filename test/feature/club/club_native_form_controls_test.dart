import 'dart:ui' show SemanticsFlag;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_compensation_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/feature/club/club_apply_page.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_edit_page.dart';
import 'package:chengyin_app/feature/club/club_edition_report_page.dart';

Widget _app(
  Widget home, {
  List<dynamic> overrides = const <dynamic>[],
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

Club _editableClub() => Club(
  id: 1,
  name: '城西探店社',
  city: '上海',
  clubType: '兴趣社群',
  activityPrefs: const <String>['城市定向'],
  isOwner: false,
  joinPolicySupported: true,
  joinPolicy: 1,
  prioritySignupEnabled: false,
  memberReservedQuota: 3,
);

class _RecordingCompensationApi extends ClubCompensationApi {
  _RecordingCompensationApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  int? hoursTopicId;
  int? hoursClubId;
  String? hoursKind;
  double? actualHours;
  int? evidenceTopicId;
  int? evidenceClubId;
  String? dimension;
  String? evidenceHash;

  @override
  Future<List<EditionOption>> editions(int clubId) async => <EditionOption>[
    EditionOption(id: 10, label: '静安第一期（2026-08-24）'),
    EditionOption(id: 12, label: '徐汇第二期（2026-09-06）'),
  ];

  @override
  Future<void> reportHours({
    required int topicId,
    required int clubId,
    required String hourKind,
    required double actualHours,
  }) async {
    hoursTopicId = topicId;
    hoursClubId = clubId;
    hoursKind = hourKind;
    this.actualHours = actualHours;
  }

  @override
  Future<void> submitEvidence({
    required int topicId,
    required int clubId,
    required String dimension,
    required String evidenceHash,
  }) async {
    evidenceTopicId = topicId;
    evidenceClubId = clubId;
    this.dimension = dimension;
    this.evidenceHash = evidenceHash;
  }
}

void main() {
  testWidgets('Apple 经验选择器保留 44pt、VoiceOver、选中触感与减少动效', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final List<MethodCall> platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      _app(const ClubApplyPage(), disableAnimations: true),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('club-apply-leader-name')),
      '陈晨',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('club-apply-phone')),
      '13800000000',
    );
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    final Finder choice = find.byKey(
      const ValueKey<String>('club-apply-exp-1-5场'),
    );
    expect(tester.getSize(choice).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('1-5场'), findsOneWidget);

    await tester.tap(choice);
    await tester.pump();

    expect(
      platformCalls,
      contains(
        isA<MethodCall>()
            .having(
              (MethodCall call) => call.method,
              'method',
              'HapticFeedback.vibrate',
            )
            .having(
              (MethodCall call) => call.arguments,
              'arguments',
              'HapticFeedbackType.selectionClick',
            ),
      ),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('1-5场'))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    expect(
      tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: choice,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .duration,
      Duration.zero,
    );
    semantics.dispose();
  });

  testWidgets('主理人申请的布尔项使用 iOS Switch 并可切换', (WidgetTester tester) async {
    await tester.pumpWidget(_app(const ClubApplyPage()));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(CupertinoTextField), findsNWidgets(4));
    final CupertinoTextField name = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey<String>('club-apply-leader-name')),
    );
    final CupertinoTextField phone = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey<String>('club-apply-phone')),
    );
    expect(name.keyboardType, TextInputType.name);
    expect(name.textInputAction, TextInputAction.next);
    expect(name.autofillHints, const <String>[AutofillHints.name]);
    expect(phone.keyboardType, TextInputType.text);
    expect(phone.textInputAction, TextInputAction.next);
    expect(phone.autofillHints, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('club-apply-leader-name')),
      '陈晨',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('club-apply-phone')),
      '13800000000',
    );
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1-5场'));
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('club-apply-exp-1-5场')))
          .height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsNothing);
    expect(find.byType(CupertinoSwitch), findsNWidgets(4));
    CupertinoSwitch route = tester.widget<CupertinoSwitch>(
      find.byType(CupertinoSwitch).first,
    );
    expect(route.value, isFalse);
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pump();
    route = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first);
    expect(route.value, isTrue);
  });

  testWidgets('编辑俱乐部的报名配置使用 iOS Switch', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const ClubEditPage(clubId: 1),
        overrides: <dynamic>[
          clubDetailProvider(1).overrideWith((ref) async => _editableClub()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('成员优先报名'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byType(Switch), findsNothing);
    expect(find.byType(CupertinoSwitch), findsWidgets);
    final CupertinoSwitch priority = tester.widget<CupertinoSwitch>(
      find.byType(CupertinoSwitch).first,
    );
    expect(priority.value, isFalse);
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pump();
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first).value,
      isTrue,
    );
    expect(find.byType(TextField), findsNothing);
    final CupertinoTextField quota = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey<String>('club-member-reserved-quota')),
    );
    expect(quota.keyboardType, TextInputType.number);
    expect(quota.textInputAction, TextInputAction.done);
  });

  testWidgets('编辑俱乐部保留小程序分区顺序且操作不回退 Material', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const ClubEditPage(clubId: 1),
        overrides: <dynamic>[
          clubDetailProvider(1).overrideWith((ref) async => _editableClub()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    const labels = <String>[
      '俱乐部形象',
      '基础信息',
      '俱乐部介绍',
      '俱乐部类型',
      '活动倾向(最多 3 个)',
      '会员经营配置',
    ];
    final tops = <double>[
      for (final String label in labels) tester.getTopLeft(find.text(label)).dy,
    ];
    expect(tops, orderedEquals(tops.toList()..sort()));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('保存修改'), findsOneWidget);
  });

  testWidgets('期次和质量维度用 iOS 短列表选择器', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const ClubEditionReportPage(clubId: 1),
        overrides: <dynamic>[
          clubEditionsProvider(1).overrideWith(
            (ref) async => <EditionOption>[
              EditionOption(id: 10, label: '静安第一期（2026-08-24）'),
              EditionOption(id: 12, label: '徐汇第二期（2026-09-06）'),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.bySemanticsLabel('选择要报的期次'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('edition-picker')))
          .height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(find.byKey(const ValueKey<String>('edition-picker')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('徐汇第二期（2026-09-06）').last);
    await tester.pumpAndSettle();
    expect(find.text('徐汇第二期（2026-09-06）'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('dimension-picker')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey<String>('dimension-picker')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('玩家体验').last);
    await tester.pumpAndSettle();
    expect(find.text('玩家体验'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('edition-evidence-hash')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    final CupertinoTextField evidence = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey<String>('edition-evidence-hash')),
    );
    expect(evidence.textInputAction, TextInputAction.done);
    expect(evidence.keyboardType, TextInputType.visiblePassword);
    expect(evidence.autocorrect, isFalse);
    expect(evidence.enableSuggestions, isFalse);
    expect(evidence.smartDashesType, SmartDashesType.disabled);
    expect(evidence.smartQuotesType, SmartQuotesType.disabled);
    expect(
      tester
          .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
          .where(
            (CupertinoTextField field) =>
                field.keyboardType ==
                const TextInputType.numberWithOptions(decimal: true),
          )
          .length,
      4,
    );
    semantics.dispose();
  });

  testWidgets('200% Dynamic Type 下选择器与证据入口仍可滚动访问', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const ClubEditionReportPage(clubId: 1),
        textScaler: TextScaler.linear(2),
        overrides: <dynamic>[
          clubEditionsProvider(1).overrideWith(
            (ref) async => <EditionOption>[
              EditionOption(id: 10, label: '静安第一期（2026-08-24）'),
              EditionOption(id: 12, label: '徐汇第二期（2026-09-06）'),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('dimension-picker')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible 只保证「露出来」,不保证「中心点可 tap」——
    // 2x 字下选择器底边贴着视口底时,命中点落在屏外等于没点。
    {
      final ScrollPosition position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final double delta =
          tester
              .getRect(find.byKey(const ValueKey<String>('dimension-picker')))
              .center
              .dy -
          tester.getRect(find.byType(Scrollable).first).center.dy;
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey<String>('dimension-picker')));
    await tester.pumpAndSettle();
    expect(find.text('内容与回顾报告'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('edition-evidence-hash')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey<String>('edition-evidence-hash')),
      findsOneWidget,
    );
  });

  testWidgets('工时与证据提交保留期次、维度和标准化 payload', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RecordingCompensationApi fake = _RecordingCompensationApi();
    await tester.pumpWidget(
      _app(
        const ClubEditionReportPage(clubId: 7),
        overrides: <dynamic>[
          clubCompensationApiProvider.overrideWithValue(fake),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('edition-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('徐汇第二期（2026-09-06）').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('edition-hours-准备')),
      '1.5',
    );
    await tester.tap(find.widgetWithText(CupertinoButton, '自报').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.hoursTopicId, 12);
    expect(fake.hoursClubId, 7);
    expect(fake.hoursKind, 'PREP');
    expect(fake.actualHours, 1.5);

    await tester.tap(find.byKey(const ValueKey<String>('dimension-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玩家体验').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('edition-evidence-hash')),
      'A' * 64,
    );
    await tester.tap(find.widgetWithText(CupertinoButton, '提交证据'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.evidenceTopicId, 12);
    expect(fake.evidenceClubId, 7);
    expect(fake.dimension, 'PLAYER_EXPERIENCE');
    expect(fake.evidenceHash, 'a' * 64);
  });
}
