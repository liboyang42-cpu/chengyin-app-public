import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 7, nickname: '我', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _QuoteActivityApi implements ActivityApi {
  @override
  Future<RegistrationQuote> quote({
    required int ownerId,
    int? ticketId,
    bool usePoints = false,
  }) async => const RegistrationQuote(payAmount: 49, quoteSign: 'signed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ActivityDetail _activity() => ActivityDetail(
  id: 7,
  name: '静安探店日',
  tickets: <ActivityTicket>[
    ActivityTicket(id: 11, name: '早鸟单人票', price: 49),
    ActivityTicket(id: 12, name: '双人同行票', price: 88),
  ],
);

Future<void> _openSignup(WidgetTester tester, {double textScale = 1}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_FixedAuth.new),
        activityApiProvider.overrideWithValue(_QuoteActivityApi()),
        activityDetailProvider(7).overrideWith((ref) async => _activity()),
        myJoinedActivitiesProvider.overrideWith(
          (ref) async => <MyRegistration>[],
        ),
      ].cast(),
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ActivityDetailPage(activityId: 7),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('立即报名'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('报名姓名与手机号使用对应 iOS 键盘、Action 和自动填充', (WidgetTester tester) async {
    await _openSignup(tester);

    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].keyboardType, TextInputType.name);
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[0].autofillHints, contains(AutofillHints.name));
    expect(fields[1].keyboardType, TextInputType.phone);
    expect(fields[1].textInputAction, TextInputAction.done);
    expect(fields[1].autofillHints, contains(AutofillHints.telephoneNumber));
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('票种使用 Cupertino Action Sheet，单独同意使用 Cupertino 勾选', (
    WidgetTester tester,
  ) async {
    await _openSignup(tester);

    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.byType(CupertinoCheckbox), findsOneWidget);
    final Finder consent = find.byKey(const Key('signup-data-consent'));
    expect(tester.getSize(consent).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .getSemantics(consent)
          .getSemanticsData()
          .flagsCollection
          .isChecked
          .name,
      'isFalse',
    );
    await tester.tap(consent);
    await tester.pump();
    expect(
      tester
          .getSemantics(consent)
          .getSemanticsData()
          .flagsCollection
          .isChecked
          .name,
      'isTrue',
    );
    await tester.tap(find.byKey(const Key('signup-ticket-picker')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('早鸟单人票  ¥49.00'), findsWidgets);
    expect(find.text('双人同行票  ¥88.00'), findsWidgets);
  });

  testWidgets('报名富表单使用 Cupertino Sheet，积分抵扣使用原生开关', (
    WidgetTester tester,
  ) async {
    await _openSignup(tester);

    expect(
      find.ancestor(
        of: find.byKey(const Key('signup-points-toggle')),
        matching: find.byType(CupertinoPageScaffold),
      ),
      findsOneWidget,
    );
    expect(find.byType(CyNativeButton), findsWidgets);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('signup-points-toggle'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('200% Dynamic Type 下票种与单独同意仍可达', (WidgetTester tester) async {
    await _openSignup(tester, textScale: 2);
    expect(find.byKey(const Key('signup-ticket-picker')), findsOneWidget);
    expect(find.byKey(const Key('signup-data-consent')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
