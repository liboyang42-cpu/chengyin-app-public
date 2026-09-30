// 我发布的券(商家侧)。
//
// ★★ `/api/coupon/mypublishlist` 后端返回的是**券模板**(SmsCoupon:
//   name/publishCount/receiveCount/useCount/status),不是 myrecvlist 那种
//   单张核销记录——之前 `myPublishedList()` 错把它按 CouponRecord 解析,
//   字段完全对不上(couponName vs name),这里锁住正确的字段读法。
// ★ receiveCount 等统计量缺席(null)与真实的 0 不同,缺席显破折号。
// ★ 游客深链 `/merchant/coupons` 页内登录门(b1-sim-coupon P1-1);
//   卡片按真源 `coupon.wxml` 补描述/类型/库存数,「进行中」不摆徽标。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/coupon/my_published_coupons_page.dart';
import 'package:chengyin_app/feature/coupon/coupon_publish_sheet.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import '../../golden/golden_theme.dart' show merchantGoldenTheme;

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

final _loggedIn = AuthState(
  user: User(id: 1, nickname: '店长', avatar: '', role: 'merchant'),
  initialized: true,
);

class _NoopApi implements CouponApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(List<dynamic> overrides, Widget home, {CouponApi? couponApi}) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(() => _FixedAuth(_loggedIn)),
      couponApiProvider.overrideWithValue(couponApi ?? _NoopApi()),
      ...overrides,
    ].cast(),
    child: MaterialApp(theme: merchantGoldenTheme(), home: home),
  );
}

void main() {
  test('券模板状态字典', () {
    expect(couponPublishStatusText(0), '未开始');
    expect(couponPublishStatusText(1), '进行中');
    expect(couponPublishStatusText(2), '已结束');
    expect(couponPublishStatusText(3), '已失效');
    expect(couponPublishStatusText(4), '已停发');
    expect(couponPublishStatusText(9), '状态 9');
    expect(couponPublishStatusText(null), '');
    // 停发入口只在前两档:真源 `coupon.js:34 canStop` = status in (0,1)。
    expect(couponCanStop(0), isTrue);
    expect(couponCanStop(1), isTrue);
    for (final int closed in <int>[2, 3, 4]) {
      expect(couponCanStop(closed), isFalse, reason: '已结束/已失效/已停发不该再摆停发');
    }
  });

  testWidgets('★ 游客深链:页内登录门,不发 mypublishlist(P1-1)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    var listCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(
            () => _FixedAuth(const AuthState(initialized: true)),
          ),
          couponApiProvider.overrideWithValue(_NoopApi()),
          myPublishedCouponsProvider.overrideWith((ref) async {
            listCalls += 1;
            return <Map<String, dynamic>>[];
          }),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MyPublishedCouponsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('coupon-published-login-gate')),
      findsOneWidget,
    );
    expect(find.text('登录后查看我发布的券'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(listCalls, 0, reason: '游客拉商家列表 = 注定 401 的请求');
  });

  testWidgets('★★ 按 SmsCoupon 的字段读:name(不是 couponType 字段名对不上)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        myPublishedCouponsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'name': '开业九折券',
              'status': 1,
              'couponType': 1,
              'startTime': '2026-09-01 00:00:00',
              'endTime': '2026-09-30 23:59:59',
              'publishCount': 100,
              'receiveCount': 40,
              // useCount 故意缺席
            },
          ],
        ),
      ], const MyPublishedCouponsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('开业九折券'), findsOneWidget);
    // 真源:「进行中」是常态,卡片不摆徽标。
    expect(find.text('进行中'), findsNothing);
    // ★ 真源卡片字段:类型文案 + 库存数(发行-已领)+ 日期只到日。
    expect(find.text('9折券'), findsOneWidget);
    expect(find.text('60 库存数'), findsOneWidget);
    expect(find.text('2026.09.01 – 2026.09.30'), findsOneWidget);
    // 缺说明显「未填写说明」,不空行(真源 D13 教训)。
    expect(find.text('未填写说明'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    // ★ useCount 缺席 → 破折号,不是「0」。
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('★ 已失效徽标(danger 口径)照常摆出;couponType=-1 回落「优惠券」', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        myPublishedCouponsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'name': '被撤的券',
              'status': 3,
              'couponType': -1,
              'description': '到店出示',
              'publishCount': 10,
              'receiveCount': 10,
              'useCount': 2,
            },
          ],
        ),
      ], const MyPublishedCouponsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('已失效'), findsOneWidget);
    expect(
      find.text(couponTypeLabel(-1)),
      findsOneWidget,
      reason: '存量无类型不冒充「请选择」',
    );
    expect(find.text('到店出示'), findsOneWidget);
    expect(find.text('0 库存数'), findsOneWidget, reason: '钳到 0,不出负数');
  });

  testWidgets('已核销确实是 0 时照实显示 0,不是破折号', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        myPublishedCouponsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'name': '新客立减',
              'status': 1,
              'couponType': 3,
              'description': '体验一把',
              'startTime': '2026-09-01',
              'endTime': '2026-09-30',
              'publishCount': 50,
              'receiveCount': 5,
              'useCount': 0,
            },
          ],
        ),
      ], const MyPublishedCouponsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    // 体验卡发得出去、列表认得回来(b1-sim-coupon P1-5)。
    expect(find.text('体验卡'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('空列表:还没有发布过优惠券', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        myPublishedCouponsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[],
        ),
      ], const MyPublishedCouponsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有发布过优惠券'), findsOneWidget);
  });

  testWidgets('发布入口是 44pt Apple 原生纯图标按钮且具有 VoiceOver 名称', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        myPublishedCouponsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[],
        ),
      ], const MyPublishedCouponsPage()),
    );
    await tester.pumpAndSettle();

    final Finder entry = find.byKey(const Key('coupon-publish-entry'));
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is CyNativeIconButton &&
            widget.key == const Key('coupon-publish-entry'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('发布优惠券'), findsOneWidget);
    expect(tester.getSize(entry), const Size(44, 44));
  });

  // ── 停发(`POST /api/coupon/stop`,真源 subpackageMember/coupon/coupon.js:163-195)
  //    二次确认(不可撤销)→ 停发 → **成功失败都回读列表**。

  testWidgets('★★ 停发:确认后才打接口(couponId),打完回读列表', (WidgetTester tester) async {
    final _FakeStopApi api = _FakeStopApi();
    await tester.pumpWidget(_stopApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coupon-stop-开业九折券')));
    await tester.pumpAndSettle();

    expect(find.text('停发「开业九折券」?'), findsOneWidget);
    expect(api.stopped, isEmpty, reason: '确认框还没点,不许先把不可撤销的请求发出去');

    await _tapInDialog(tester, '停发该券');

    expect(api.stopped, <int>[7]);
    expect(api.listCalls, 2, reason: '停发后回读,列表才不是说谎的旧快照');
    expect(find.text('已停发「开业九折券」'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('停发点「取消」:一个请求都不发', (WidgetTester tester) async {
    final _FakeStopApi api = _FakeStopApi();
    await tester.pumpWidget(_stopApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coupon-stop-开业九折券')));
    await tester.pumpAndSettle();
    await _tapInDialog(tester, '取消');

    expect(api.stopped, isEmpty);
    expect(api.listCalls, 1, reason: '取消没改任何东西,不用回读');
  });

  testWidgets('★ 停发失败:点名后端原因,且照样回读(别对着旧状态再点一次)', (WidgetTester tester) async {
    final _FakeStopApi api = _FakeStopApi(failStop: true);
    await tester.pumpWidget(_stopApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coupon-stop-开业九折券')));
    await tester.pumpAndSettle();
    await _tapInDialog(tester, '停发该券');

    expect(find.text('这张券已被停发，请刷新后重试'), findsOneWidget);
    expect(api.listCalls, 2);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('已结束 / 已失效 / 已停发的券不摆停发入口', (WidgetTester tester) async {
    final _FakeStopApi api = _FakeStopApi(couponStatus: 4);
    await tester.pumpWidget(_stopApp(api));
    await tester.pumpAndSettle();
    expect(find.text('已停发'), findsOneWidget);
    expect(find.byKey(const Key('coupon-stop-开业九折券')), findsNothing);
  });
}

/// 确认框里的键要点得准:页面上的按钮文案跟确认键同名(「停发该券」)。
Future<void> _tapInDialog(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _stopApp(CouponApi api) {
  return _app(
    <dynamic>[],
    const MyPublishedCouponsPage(),
    couponApi: api,
  );
}

class _FakeStopApi implements CouponApi {
  _FakeStopApi({this.failStop = false, this.couponStatus = 1});

  final bool failStop;
  final int couponStatus;
  final List<int> stopped = <int>[];
  int listCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> myPublishedList({String? keyword}) async {
    listCalls += 1;
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 7,
        'name': '开业九折券',
        'status': couponStatus,
        'publishCount': 100,
        'receiveCount': 40,
        'useCount': 3,
      },
    ];
  }

  @override
  Future<void> stop(int couponId) async {
    stopped.add(couponId);
    if (failStop) throw Exception('这张券已被停发，请刷新后重试');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
