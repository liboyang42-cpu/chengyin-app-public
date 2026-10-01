import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';

import '../../support/fixed_auth.dart';

class _AddressApi extends Fake implements AddressApi {
  int defaultCalls = 0;

  @override
  Future<List<MemberAddress>> list() async => const <MemberAddress>[
    MemberAddress(
      id: 7,
      fullName: '小李',
      mobilePhone: '13800001111',
      isDefault: true,
    ),
    MemberAddress(id: 8, fullName: '小王', mobilePhone: '13800002222'),
  ];

  @override
  Future<void> setDefault(int id) async {
    defaultCalls++;
  }
}

void main() {
  // Published 3876c842 address.js retains the handler, but address.wxml
  // has no binding and comments out the default badge. Do not manufacture
  // a control merely to make an endpoint scanner count the wrapper as used.
  testWidgets('默认与普通参与人均无隐藏真源之外的默认操作', (tester) async {
    final api = _AddressApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signedInAuthOverride(),
          addressApiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: AddressListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('小李'), findsOneWidget);
    expect(find.text('小王'), findsOneWidget);
    expect(find.text('编辑'), findsNWidgets(2));
    expect(find.text('默认'), findsNothing);
    expect(find.textContaining('设为默认'), findsNothing);
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(api.defaultCalls, 0);
  });
}
