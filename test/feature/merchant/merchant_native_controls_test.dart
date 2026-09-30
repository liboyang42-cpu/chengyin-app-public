import 'dart:io';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:chengyin_app/feature/merchant/merchant_apply_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_edit_page.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 入驻页进页先问「这个账号名下有没有已提交的申请」(真源 checkExisting)。
  // 这几条用例要的是**向导本体**,所以一律当后端回了 NONE(没有申请行)。
  // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,靠推断。
  final noApplication = <dynamic>[
    merchantApplicationProvider.overrideWith((ref) async => null),
  ];

  test('商家资料三页不再使用 Material 输入和按钮', () {
    final source = <String>[
      'lib/feature/merchant/merchant_apply_page.dart',
      'lib/feature/merchant/merchant_edit_page.dart',
      'lib/feature/merchant/merchant_decor_page.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(source, isNot(contains('TextFormField(')));
    expect(RegExp(r'(?<!Cupertino)TextField\(').hasMatch(source), isFalse);
    expect(source, isNot(contains('FilledButton(')));
    expect(source, isNot(contains('OutlinedButton')));
    expect(source, isNot(contains('TextButton(')));
    expect(source, contains('CupertinoTextField'));
    expect(source, contains('CupertinoButton'));
    expect(source, contains('CupertinoActivityIndicator'));
  });

  testWidgets('入驻第一步保持小程序顺序并使用正确的 iOS 键盘/autofill', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: noApplication.cast(),
        child: MaterialApp(home: const MerchantApplyPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTextField), findsNWidgets(3));
    final labels = <Finder>[
      find.text('店铺名称'),
      find.text('经营类目'),
      find.text('联系电话'),
    ];
    for (final label in labels) {
      expect(label, findsOneWidget);
    }
    expect(
      labels.map((finder) => tester.getTopLeft(finder).dy).toList(),
      orderedEquals(
        <double>[
          tester.getTopLeft(labels[0]).dy,
          tester.getTopLeft(labels[1]).dy,
          tester.getTopLeft(labels[2]).dy,
        ]..sort(),
      ),
    );

    final name = tester.widget<CupertinoTextField>(
      find.byKey(const Key('merchant-apply-name')),
    );
    final phone = tester.widget<CupertinoTextField>(
      find.byKey(const Key('merchant-apply-phone')),
    );
    expect(name.keyboardType, TextInputType.name);
    expect(name.autofillHints, contains(AutofillHints.organizationName));
    expect(phone.keyboardType, TextInputType.phone);
    expect(phone.autofillHints, contains(AutofillHints.telephoneNumber));

    await tester.enterText(
      find.byKey(const Key('merchant-apply-name')),
      '城市咖啡',
    );
    await tester.enterText(
      find.byKey(const Key('merchant-apply-phone')),
      '13800138000',
    );
    await tester.pump();
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('merchant-apply-next')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pump();
    final address = tester.widget<CupertinoTextField>(
      find.byKey(const Key('merchant-apply-address')),
    );
    final Finder businessTime = find.byKey(
      const Key('merchant-apply-business-time'),
    );
    expect(address.keyboardType, TextInputType.streetAddress);
    expect(address.autofillHints, contains(AutofillHints.fullStreetAddress));
    expect(tester.getSize(businessTime).height, greaterThanOrEqualTo(44));
    expect(find.text('店铺介绍'), findsOneWidget);
  });

  testWidgets('经营时间按小程序真源使用 iOS 营业日与双时间选择器', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: noApplication.cast(),
        child: MaterialApp(home: const MerchantApplyPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-apply-name')),
      '城市咖啡',
    );
    await tester.enterText(
      find.byKey(const Key('merchant-apply-phone')),
      '13800138000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pumpAndSettle();

    final Finder hours = find.byKey(const Key('merchant-apply-business-time'));
    expect(tester.getSize(hours).height, greaterThanOrEqualTo(44));
    final hoursNode = tester.getSemantics(hours);
    expect(hoursNode.label, contains('经营时间，必填，点击设置营业日与时段'));
    expect(hoursNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: hoursNode.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('设置经营时间'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNWidgets(2));

    final Finder monday = find.byKey(const Key('merchant-hours-day-1'));
    expect(tester.getSize(monday).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(monday).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    final mondayNode = tester.getSemantics(monday);
    expect(
      mondayNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: mondayNode.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(
      tester.getSemantics(monday).flagsCollection.isSelected,
      Tristate.isFalse,
    );

    await tester.tap(find.widgetWithText(CupertinoButton, '完成'));
    await tester.pumpAndSettle();
    expect(find.text('周二、三、四、五、六、日 10:00-22:00'), findsOneWidget);

    await tester.tap(hours);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('周二、三、四、五、六、日 10:00-22:00'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('200% 动态字号下经营时间选择器仍可访问', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: noApplication.cast(),
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const MerchantApplyPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-apply-name')),
      '城市咖啡',
    );
    await tester.enterText(
      find.byKey(const Key('merchant-apply-phone')),
      '13800138000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-apply-business-time')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CupertinoDatePicker), findsNWidgets(2));
    expect(find.widgetWithText(CupertinoButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(CupertinoButton, '完成'), findsOneWidget);
  });

  testWidgets('320x568 SE 下 7 个经营日均保留 44pt 且周日可横滑到达', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: noApplication.cast(),
        child: MaterialApp(home: const MerchantApplyPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-apply-name')),
      '城市咖啡',
    );
    await tester.enterText(
      find.byKey(const Key('merchant-apply-phone')),
      '13800138000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-apply-business-time')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (int day = 1; day <= 7; day++) {
      final Size hit = tester.getSize(
        find.byKey(Key('merchant-hours-day-$day')),
      );
      expect(hit.width, greaterThanOrEqualTo(44), reason: '周$day 宽度不足');
      expect(hit.height, greaterThanOrEqualTo(44), reason: '周$day 高度不足');
    }
    final Finder sunday = find.byKey(const Key('merchant-hours-day-7'));
    await tester.ensureVisible(sunday);
    await tester.pumpAndSettle();
    expect(sunday.hitTestable(), findsOneWidget);
    expect(find.widgetWithText(CupertinoButton, '完成'), findsOneWidget);
  });

  testWidgets('店铺资料的名称与网址使用系统语义键盘', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          merchantInfoProvider.overrideWith(
            (ref) async => <String, dynamic>{
              'id': 7,
              'name': '夜归咖啡',
              'description': '',
              'derivatives': '',
              'website': 'https://example.com',
              'preference': '',
              'logo': '',
            },
          ),
        ].cast(),
        child: const MaterialApp(home: MerchantEditPage()),
      ),
    );
    await tester.pumpAndSettle();

    final name = tester.widget<CupertinoTextField>(
      find.byKey(const Key('merchant-edit-name')),
    );
    final website = tester.widget<CupertinoTextField>(
      find.byKey(const Key('merchant-edit-website')),
    );
    expect(name.keyboardType, TextInputType.name);
    expect(name.autofillHints, contains(AutofillHints.organizationName));
    expect(website.keyboardType, TextInputType.url);
    expect(website.autofillHints, contains(AutofillHints.url));
  });

  testWidgets('店铺装修根页无内联输入，单字段进 Cupertino Sheet', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          merchantApiProvider.overrideWithValue(_DecorMerchantApi()),
        ].cast(),
        child: const MaterialApp(home: MerchantDecorPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTextField), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一句话 slogan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('merchant-decor-field-input')), findsOneWidget);
    expect(find.widgetWithText(CupertinoButton, '完成'), findsOneWidget);
  });
}

class _DecorMerchantApi implements MerchantApi {
  @override
  Future<Map<String, dynamic>> coopProfile() async => <String, dynamic>{
    'id': 7,
    'name': '夜归咖啡',
    'slogan': '一杯咖啡的城市',
    'gallery': '[]',
    'tags': '[]',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
