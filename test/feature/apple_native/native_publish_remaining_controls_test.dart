import 'dart:io';

import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/data/models/activity_publish.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/feature/publish/publish_activity_page.dart';
import 'package:chengyin_app/feature/publish/publish_capability.dart';
import 'package:chengyin_app/feature/publish/publish_page.dart';
import 'package:chengyin_app/feature/publish/publish_pro_ticket_tab.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('活动时间改动会把票的履约窗口对齐到同一起止时间', () {
    final DateTime start = DateTime(2026, 9, 8, 19);
    final DateTime end = DateTime(2026, 9, 8, 22);
    final List<TicketDraft> aligned = alignActivityTicketSchedule(
      const <TicketDraft>[
        TicketDraft(name: '早鸟票', price: 39, totalStock: 20),
        TicketDraft(name: '标准票', price: 69, totalStock: 40),
      ],
      startDate: start,
      endDate: end,
    );

    expect(aligned.map((TicketDraft ticket) => ticket.startTime), <DateTime>[
      start,
      start,
    ]);
    expect(aligned.map((TicketDraft ticket) => ticket.endTime), <DateTime>[
      end,
      end,
    ]);
    expect(aligned.map((TicketDraft ticket) => ticket.name), <String>[
      '早鸟票',
      '标准票',
    ]);
  });

  testWidgets('快速配置保留小程序字段顺序，使用 iOS 输入与按钮', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PublishPage())),
    );
    await tester.pumpAndSettle();

    final Finder name = find.byKey(const Key('publish-quick-name'));
    final Finder description = find.byKey(
      const Key('publish-quick-description'),
    );
    expect(name, findsOneWidget);
    expect(description, findsOneWidget);
    expect(tester.widget(name), isA<CupertinoTextField>());
    expect(tester.widget(description), isA<CupertinoTextField>());
    expect(
      tester.getTopLeft(name).dy,
      lessThan(tester.getTopLeft(description).dy),
    );
    expect(
      tester.widget<CupertinoTextField>(description).keyboardType,
      TextInputType.multiline,
    );
    expect(find.byKey(const Key('publish-ai-draft')), findsOneWidget);
    expect(find.byKey(const Key('publish-quick-enter-editor')), findsOneWidget);
  });

  testWidgets('活动发布首屏使用系统键盘与日期选择入口', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(role: 'club'),
          ),
        ].cast(),
        child: const MaterialApp(home: PublishActivityPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget(find.byKey(const Key('activity-name'))),
      isA<CupertinoTextField>(),
    );
    expect(
      tester.widget(find.byKey(const Key('activity-address'))),
      isA<CupertinoButton>(),
    );
    expect(find.byKey(const Key('activity-start')), findsOneWidget);
    expect(find.byKey(const Key('activity-end')), findsOneWidget);
    expect(find.byKey(const Key('activity-categories')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('activity-primary'))),
      isA<CupertinoButton>(),
    );
  });

  test('活动分类和我的模板使用真实接口与 Cupertino Sheet', () {
    final String source = File(
      'lib/feature/publish/publish_activity_page.dart',
    ).readAsStringSync();
    expect(source, contains("list(type: '2')"));
    expect(source, contains('templateMyList(keyword: keyword)'));
    expect(source, contains('showCupertinoSheet<List<Category>>'));
    expect(source, contains('showCupertinoSheet<PublishTemplate>'));
    expect(source, contains("Key('activity-categories')"));
    expect(source, contains("Key('activity-template')"));
    expect(source, contains("Key('activity-template-search')"));
    expect(source, contains('CupertinoSearchTextField'));
  });

  testWidgets('活动发布能从真实数据缝选中分类和我的模板', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PublishTemplate template = PublishTemplate(
      id: 31,
      title: '夜游任务模板',
      imgUrl: '',
      players: '2-6',
      duration: 90,
      raw: const <String, dynamic>{},
    );
    String requestedKeyword = '';
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(role: 'club'),
          ),
          activityPublishCategoriesProvider.overrideWith(
            (Ref ref) async => <Category>[
              Category(id: 2, name: '城市漫游', type: 2),
            ],
          ),
          activityPublishTemplatesProvider.overrideWith((
            Ref ref,
            String keyword,
          ) async {
            requestedKeyword = keyword;
            return <PublishTemplate>[template];
          }),
        ].cast(),
        child: const MaterialApp(home: PublishActivityPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('activity-categories')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-category-2')));
    await tester.tap(find.byKey(const Key('activity-categories-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('城市漫游'), findsOneWidget);

    tester
        .widget<CupertinoButton>(find.byKey(const Key('activity-primary')))
        .onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<CupertinoButton>(
          find.descendant(
            of: find.byKey(const Key('activity-template')),
            matching: find.byType(CupertinoButton),
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('activity-template-search')),
      '夜游',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(requestedKeyword, '夜游');
    await tester.tap(find.byKey(const Key('activity-template-31')));
    await tester.tap(find.byKey(const Key('activity-template-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('夜游任务模板'), findsOneWidget);
  });

  testWidgets('活动类型接口返回空列表时 fail closed，不生成假选项', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(role: 'club'),
          ),
          activityPublishCategoriesProvider.overrideWith(
            (Ref ref) async => <Category>[],
          ),
        ].cast(),
        child: const MaterialApp(home: PublishActivityPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('activity-categories')));
    await tester.pumpAndSettle();
    expect(find.text('暂无可选活动类型'), findsOneWidget);
    expect(find.byKey(const Key('activity-category-0')), findsNothing);
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('activity-categories-confirm')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('专业票种按小程序顺序使用数字键盘与系统日期器', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PublishDraft draft = PublishDraft()
      ..productType = 1
      ..tickets = <PublishTicket>[
        PublishTicket()
          ..name = '早鸟票'
          ..mode = 1
          ..totalStock = 100,
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublishTicketTab(
              draft: draft,
              merchantPoolEditable: false,
              myClubs: const [],
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('早鸟票'));
    await tester.pumpAndSettle();

    final Finder name = find.byKey(const Key('ticket-editor-name'));
    final Finder price = find.byKey(const Key('ticket-editor-price'));
    final Finder stock = find.byKey(const Key('ticket-editor-stock'));
    expect(tester.widget(name), isA<CupertinoTextField>());
    expect(tester.getTopLeft(name).dy, lessThan(tester.getTopLeft(price).dy));
    expect(
      tester.widget<CupertinoTextField>(price).keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(
      tester.widget<CupertinoTextField>(stock).keyboardType,
      TextInputType.number,
    );

    await tester.tap(find.text('选择日期').first);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  test('发布主页不再混用 Material 表单和操作按钮', () {
    for (final String path in <String>[
      'lib/feature/publish/publish_page.dart',
      'lib/feature/publish/publish_activity_page.dart',
      'lib/feature/publish/publish_pro_page.dart',
      'lib/feature/publish/publish_pro_ticket_tab.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      for (final RegExp forbidden in <RegExp>[
        RegExp(r'(?<!Cupertino)\bTextField\('),
        RegExp(r'(?<!Cupertino)\bTextFormField\('),
        RegExp(r'\bFilledButton\('),
        RegExp(r'\bOutlinedButton\('),
        RegExp(r'(?<!Cupertino)\bTextButton\('),
      ]) {
        expect(
          forbidden.hasMatch(source),
          isFalse,
          reason: '$path 应用 Cupertino/系统控件替代 $forbidden',
        );
      }
    }
  });
}
