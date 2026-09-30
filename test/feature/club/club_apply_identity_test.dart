// 主理人申请(第 4 步)× 发布者实名 —— 三入口接线之一。
//
// 钉住真源 pages/club/apply/index.js 的形态:
// · 进第 4 屏才查一次状态(_identityStatusRequested),已登记收起字段;
// · 「成为俱乐部主理人」的亮灭由实名三项闸着(校验顺序只有一份);
// · 提交时序 = 先 /api/publisher/identity、后 become-leader,成为一发的
//   payload 里永不含 realName/idCard(隐私红线 + 服务端闸);
// · 登记失败 → 主理人申请不发,页内错误条说原文并可重试。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/publisher_identity_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_apply_page.dart';

import '../../support/fake_publisher_identity.dart';

class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(dummyDioClient());

  Map<String, dynamic>? becomeLeaderPayload;
  Object? becomeLeaderError;

  @override
  Future<void> becomeLeader(Map<String, dynamic> payload) async {
    becomeLeaderPayload = Map<String, dynamic>.from(payload);
    if (becomeLeaderError != null) throw becomeLeaderError!;
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;

  @override
  AuthState build() => _initial;

  @override
  Future<void> refreshRole() async {}
}

Widget _app(List<dynamic> overrides, Widget home) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: home,
  ),
);

/// 走完前三步落到第 4 屏(资质 + 发布者实名)。
Future<void> _toStep4(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('club-apply-leader-name')),
    '陈晨',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('club-apply-phone')),
    'chenchen_wechat',
  );
  // 「继续」的可用性取 build 时的 canNext —— 不 rebuild 这发 tap 是空点击,
  // 页子会永远停在第 1 步(与 club_pages_behavior_test 不同,这里没经过
  // 其它先 rebuild 的动作)。
  await tester.pump();
  await tester.tap(find.text('继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('5-20场'));
  await tester.pump();
  await tester.tap(find.text('继续'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('继续'));
  await tester.pumpAndSettle();
}

Finder _submitBtn() => find.ancestor(
  of: find.text('成为俱乐部主理人'),
  matching: find.byType(CupertinoButton),
);

CupertinoButton _submitWidget(WidgetTester tester) =>
    tester.widget<CupertinoButton>(_submitBtn());

void main() {
  testWidgets('进第 4 屏查一次状态;已登记的人收起字段、只回显状态', (
    WidgetTester tester,
  ) async {
    final identity = FakePublisherIdentityApi(registered: true);
    final club = _FakeClubApi();
    await tester.pumpWidget(
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(club),
        publisherIdentityApiProvider.overrideWithValue(identity),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(
            AuthState(user: null, initialized: true),
          ),
        ),
      ], const ClubApplyPage()),
    );
    await tester.pumpAndSettle();

    // 前三步不该多发这一发查询(资格还没确认的人不需要)。
    expect(identity.statusCalls, 0);
    await _toStep4(tester);
    expect(identity.statusCalls, 1, reason: '进第 4 屏查且只查一次');
    // 第 4 屏内再泵一帧:登记状态不跟着页面动作重复查。
    await tester.pumpAndSettle();
    expect(identity.statusCalls, 1, reason: '第 4 屏内动作不重复查');

    expect(
      find.text('已登记。如需变更实名信息，请联系平台客服。'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('identity-real-name')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('identity-id-card')),
        findsNothing);

    // 已登记 → 直接发主理人申请,不再发登记请求。
    await tester.tap(_submitBtn());
    await tester.pumpAndSettle();
    expect(identity.registerCalls, isEmpty);
    expect(club.becomeLeaderPayload, isNotNull);
    expect(find.text('已成为主理人'), findsOneWidget);
  });

  testWidgets('未登记:三项不齐「成为主理人」不亮,差什么按顺序说什么', (
    WidgetTester tester,
  ) async {
    final identity = FakePublisherIdentityApi();
    await tester.pumpWidget(
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(_FakeClubApi()),
        publisherIdentityApiProvider.overrideWithValue(identity),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(
            AuthState(user: null, initialized: true),
          ),
        ),
      ], const ClubApplyPage()),
    );
    await tester.pumpAndSettle();
    await _toStep4(tester);

    expect(find.byKey(const ValueKey<String>('identity-real-name')),
        findsOneWidget);
    expect(_submitWidget(tester).onPressed, isNull,
        reason: '空表不能提交');

    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-real-name')),
      '陈晨',
    );
    await tester.pump();
    expect(_submitWidget(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-id-card')),
      '99000019491231019X',
    );
    await tester.pump();
    expect(_submitWidget(tester).onPressed, isNull,
        reason: '没勾单独同意仍然是闸(个保法 §29,默认不勾)');

    await tester.tap(find.byKey(const Key('identity-consent')));
    await tester.pump();
    expect(_submitWidget(tester).onPressed, isNotNull);
  });

  testWidgets('提交:先登记实名、后发主理人申请;业务 payload 不含 PII', (
    WidgetTester tester,
  ) async {
    final identity = FakePublisherIdentityApi();
    final club = _FakeClubApi();
    await tester.pumpWidget(
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(club),
        publisherIdentityApiProvider.overrideWithValue(identity),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(
            AuthState(user: null, initialized: true),
          ),
        ),
      ], const ClubApplyPage()),
    );
    await tester.pumpAndSettle();
    await _toStep4(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-real-name')),
      ' 陈晨 ',
    );
    // 格子按真源 maxlength=18 硬顶(微信 type=idcard 同口径),带内部空白的
    // 归一化用例归 rules 测试,这里测的是「末位小写 x 当场被认」。
    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-id-card')),
      '99000019491231019x',
    );
    await tester.tap(find.byKey(const Key('identity-consent')));
    await tester.pump();
    await tester.tap(_submitBtn());
    await tester.pumpAndSettle();

    expect(identity.registerCalls, <Map<String, Object?>>[
      <String, Object?>{
        'realName': '陈晨',
        'idCard': '99000019491231019X',
        'consent': true,
        'source': 'club_apply',
      },
    ]);
    expect(club.becomeLeaderPayload, isNotNull,
        reason: '登记成功当场续发申请');
    expect(club.becomeLeaderPayload!.containsKey('realName'), isFalse);
    expect(club.becomeLeaderPayload!.containsKey('idCard'), isFalse);

    // 值不再回显:登记成功后字段收起、清空。
    expect(find.byKey(const ValueKey<String>('identity-id-card')),
        findsNothing);
    final controllerTexts = identity.registerCalls.single['idCard'];
    expect('$controllerTexts'.contains('990000'), isTrue,
        reason: '登记那一发本身带值(服务端唯一入口),除此之外不回显');
  });

  testWidgets('登记失败:主理人申请不发,页内错误条说原文、重试续走', (
    WidgetTester tester,
  ) async {
    final identity = FakePublisherIdentityApi()
      ..registerError = const PublisherIdentityException(
        '实名信息已登记,如需变更请联系平台客服',
      );
    final club = _FakeClubApi();
    await tester.pumpWidget(
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(club),
        publisherIdentityApiProvider.overrideWithValue(identity),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(
            AuthState(user: null, initialized: true),
          ),
        ),
      ], const ClubApplyPage()),
    );
    await tester.pumpAndSettle();
    await _toStep4(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-real-name')),
      '陈晨',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-id-card')),
      '99000019491231019X',
    );
    await tester.tap(find.byKey(const Key('identity-consent')));
    await tester.pump();

    await tester.tap(_submitBtn());
    await tester.pumpAndSettle();

    // ★ 登记这一发没过,主理人申请永不能发出去(时序是服务端闸定的)。
    expect(identity.registerCalls.length, 1);
    expect(club.becomeLeaderPayload, isNull);
    expect(find.byKey(const Key('apply-submit-error')), findsOneWidget);
    expect(find.text('提交没有完成'), findsOneWidget);
    expect(
      find.text('实名信息已登记,如需变更请联系平台客服'),
      findsOneWidget,
      reason: '错误条说的是接口原文,不是笼统的"失败请重试"',
    );
    // 失败时字段原地保留让用户改 —— 这是填写态,不是登记后的回显态。
    expect(
      find.byKey(const ValueKey<String>('identity-id-card')),
      findsOneWidget,
    );

    identity.registerError = null; // 服务端放行(同证同人幂等)
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(identity.registerCalls.length, 2);
    expect(club.becomeLeaderPayload, isNotNull);
    expect(find.text('已成为主理人'), findsOneWidget);
    expect(find.byKey(const Key('apply-submit-error')), findsNothing);
  });

  testWidgets('登记失败落页内错误条:提交没有完成 + 原文 + 重试不重发登记', (
    WidgetTester tester,
  ) async {
    final identity = FakePublisherIdentityApi();
    final club = _FakeClubApi();
    // 让登记成功、become-leader 失败,错误条归业务失败档。
    club.becomeLeaderError = ClubApiException('资料不全,请补齐');
    await tester.pumpWidget(
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(club),
        publisherIdentityApiProvider.overrideWithValue(identity),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(
            AuthState(user: null, initialized: true),
          ),
        ),
      ], const ClubApplyPage()),
    );
    await tester.pumpAndSettle();
    await _toStep4(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-real-name')),
      '陈晨',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-id-card')),
      '99000019491231019X',
    );
    await tester.tap(find.byKey(const Key('identity-consent')));
    await tester.pump();
    await tester.tap(_submitBtn());
    await tester.pumpAndSettle();

    expect(find.byKey(Key('apply-submit-error')), findsOneWidget);
    expect(find.text('提交没有完成'), findsOneWidget);
    expect(find.text('资料不全,请补齐'), findsOneWidget);
    // 实名已登记成功 —— 重试不再发第二发登记,只续业务。
    expect(identity.registerCalls.length, 1);

    club.becomeLeaderError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(identity.registerCalls.length, 1, reason: '重试只补业务那一发');
    expect(find.text('已成为主理人'), findsOneWidget);
  });
}
