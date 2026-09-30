import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/feature/account/address_edit_page.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';

import '../../support/fixed_auth.dart';

class _AddressApi extends Fake implements AddressApi {
  int saveCalls = 0;

  @override
  Future<void> save({
    int? id,
    required String fullName,
    required String mobilePhone,
    String? province,
    String? detailAddress,
    bool isDefault = false,
  }) async {
    saveCalls++;
  }
}

void main() {
  testWidgets('参与人表单仅保留真源两个字段并使用 iOS 系统输入', (WidgetTester tester) async {
    final _AddressApi api = _AddressApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          addressApiProvider.overrideWithValue(api),
        ].cast(),
        child: const MaterialApp(home: AddressEditPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('参与人信息'), findsOneWidget);
    expect(find.text('用于报名联系和到场核验，不会公开展示，也不用于配送。'), findsOneWidget);
    expect(find.byType(CupertinoTextFormFieldRow), findsNWidgets(2));
    expect(find.text('省市区'), findsNothing);
    expect(find.text('详细地址'), findsNothing);
    expect(find.text('设为默认'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    final Finder fields = find.byType(CupertinoTextFormFieldRow);
    final Finder cupertinoFields = find.descendant(
      of: fields,
      matching: find.byType(CupertinoTextField),
    );
    final CupertinoTextField nameField = tester.widget<CupertinoTextField>(
      cupertinoFields.at(0),
    );
    final CupertinoTextField phoneField = tester.widget<CupertinoTextField>(
      cupertinoFields.at(1),
    );
    final EditableText name = tester.widget<EditableText>(
      find.descendant(of: fields.at(0), matching: find.byType(EditableText)),
    );
    final EditableText phone = tester.widget<EditableText>(
      find.descendant(of: fields.at(1), matching: find.byType(EditableText)),
    );
    expect(name.textInputAction, TextInputAction.next);
    expect(nameField.autofillHints, contains(AutofillHints.name));
    expect(phone.keyboardType, TextInputType.phone);
    expect(phone.textInputAction, TextInputAction.done);
    expect(phoneField.autofillHints, contains(AutofillHints.telephoneNumber));
  });

  testWidgets('非法手机号不能保存，合法号码可通过原返回链路', (WidgetTester tester) async {
    final _AddressApi api = _AddressApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          addressApiProvider.overrideWithValue(api),
        ].cast(),
        child: const MaterialApp(home: AddressEditPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder fields = find.byType(CupertinoTextFormFieldRow);
    await tester.enterText(fields.at(0), '林野');
    await tester.enterText(fields.at(1), '123');
    await tester.pump();
    final CupertinoButton invalid = tester.widget<CupertinoButton>(
      find.byKey(const Key('address-save-participant')),
    );
    expect(invalid.onPressed, isNull);
    expect(api.saveCalls, 0);

    await tester.enterText(fields.at(1), '13800008001');
    await tester.pump();
    await tester.tap(find.byKey(const Key('address-save-participant')));
    await tester.pumpAndSettle();
    expect(api.saveCalls, 1);
  });

  testWidgets('200% 动态字号下两个系统输入和保存入口仍可访问', (WidgetTester tester) async {
    final _AddressApi api = _AddressApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          addressApiProvider.overrideWithValue(api),
        ].cast(),
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AddressEditPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CupertinoTextFormFieldRow), findsNWidgets(2));
    expect(find.byKey(const Key('address-save-participant')), findsOneWidget);
  });
}
