import 'dart:async';

import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/core/role_provider.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/models/deregistration.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/role_info.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/account/deregister_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/profile/profile_edit_page.dart';
import 'package:chengyin_app/feature/withdrawal/withdrawal_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixed_auth.dart';
import '../../support/funds_stages_fixture.dart';

Widget _host({
  required List<dynamic> overrides,
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      builder: (BuildContext context, Widget? builtChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: builtChild!,
      ),
      home: child,
    ),
  );
}

/// 编辑资料这一页整页要登录:表单只属于登录态,游客态是登录引导
/// (test/feature/profile/profile_edit_guest_gate_test.dart)。
class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 7, nickname: '城市漫游者', avatar: '', role: 'player'),
    initialized: true,
  );
}

ProfileDetail _profile() => ProfileDetail(
  id: 7,
  nickname: '城市漫游者',
  avatar: '',
  introduction: '用脚步认识城市',
  levelId: 1,
  point: 20,
  balance: 128.5,
  followNum: 0,
  fansNum: 0,
  likeNum: 0,
  topicNum: 0,
  activityNum: 0,
);

RoleInfo _role({required bool withdrawable}) =>
    RoleInfo.fromJson(<String, dynamic>{
      'role': 'player',
      'permission': <String, dynamic>{'withdrawable': withdrawable},
      'usage': <String, dynamic>{},
      'isClubLeader': false,
      'isMerchant': false,
      'ownedClubCount': 0,
      'maxOwnedClubs': 0,
      'ownedClubs': <dynamic>[],
      'joinedClubIds': <dynamic>[],
    });

class _EligibleAccountApi extends Fake implements AccountApi {
  @override
  Future<DeregistrationStatus> deregisterStatus() async =>
      const DeregistrationStatus(status: 'NORMAL', blockers: <String>[]);

  @override
  Future<DeregistrationStatus> deregisterPrecheck() async =>
      const DeregistrationStatus(status: 'ELIGIBLE', blockers: <String>[]);

  @override
  Future<void> agreeCancellationNotice(String requestId) async {}
}

void main() {
  testWidgets('编辑资料使用 Cupertino 表单、姓名键盘和自然语言输入', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          myProfileProvider.overrideWith((ref) async => _profile()),
        ],
        child: const ProfileEditPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);

    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].keyboardType, TextInputType.name);
    expect(fields[0].autofillHints, contains(AutofillHints.nickname));
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[1].keyboardType, TextInputType.multiline);
    expect(fields[1].textInputAction, TextInputAction.newline);
    expect(fields[1].textCapitalization, TextCapitalization.sentences);
    expect(find.widgetWithText(CyNativeButton, '没有改动'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CyNativeButton)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('注销验证使用 Cupertino 勾选、手机键盘和验证码自动填充', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        overrides: <dynamic>[
          // 注销页现在先挡登录门(B1 P1-2):这里测的是登录后的流程。
          signedInAuthOverride(),
          accountApiProvider.overrideWithValue(_EligibleAccountApi()),
        ],
        child: const DeregisterPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoCheckbox), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.bySemanticsLabel('我已阅读并同意账号注销须知'), findsOneWidget);
    await tester.tap(find.byType(CupertinoCheckbox));
    await tester.pump();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].keyboardType, TextInputType.phone);
    expect(fields[0].autofillHints, contains(AutofillHints.telephoneNumber));
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[1].keyboardType, TextInputType.number);
    expect(fields[1].autofillHints, contains(AutofillHints.oneTimeCode));
    expect(fields[1].textInputAction, TextInputAction.done);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.widgetWithText(CyNativeButton, '提交注销申请'), findsOneWidget);
  });

  // ★ R10(2026-09-17):提现不再收银行卡信息,这一页不再有金融信息表单。
  //   保留的断言是「资格没确认时连余额都不拉」——不然会在没有提现资格时
  //   仍然请求一次资金数据,白花一次隐私与流量。
  testWidgets('提现资格未确认或不允许时:不加载余额,也不展示可提现金额', (WidgetTester tester) async {
    for (final Future<RoleInfo> Function() role
        in <Future<RoleInfo> Function()>[
          () => Completer<RoleInfo>().future,
          () async => _role(withdrawable: false),
        ]) {
      int balanceLoads = 0;
      await tester.pumpWidget(
        _host(
          overrides: <dynamic>[
            authControllerProvider.overrideWith(
              () => FixedAuth(signedInAuthState()),
            ),
            roleInfoProvider.overrideWith((ref) => role()),
            fundsStagesProvider.overrideWith(
              (ref) async => kFundsStagesFixture,
            ),
            withdrawableBalanceProvider.overrideWith((ref) async {
              balanceLoads += 1;
              return 328.6;
            }),
          ],
          child: const WithdrawalPage(),
        ),
      );
      await tester.pump();

      expect(find.byType(CupertinoTextField), findsNothing);
      expect(find.text('可提现余额'), findsNothing);
      expect(balanceLoads, 0);
    }
  });

  testWidgets('Dynamic Type 放大时主操作随字号增高', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          myProfileProvider.overrideWith((ref) async => _profile()),
        ],
        textScaler: const TextScaler.linear(2),
        child: const ProfileEditPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(CyNativeButton)).height, greaterThan(44));
  });
}
