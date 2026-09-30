// 「取消活动并退款」的三条硬约束。
//
// 这个动作会给所有已报名(未核销)用户全额退款、活动同时下架、不可撤销。
//
// ★★★ ① 判不准主办方就**不给入口**。判据是 hostMemberId(后端 CmsActivity.memberId)——
//     ⚠️ 不是 ownerId:本仓库里 ownerId 指的是**活动 ID**(票/报名的 owner 是活动),
//     CmsActivity 压根没有 ownerId 字段。拿错字段判会让**每个人**都看到这个按钮。
// ★★★ ② 成功后必须**原样显示后端那句话**。后端在 msg 里区分了
//     退了几笔 / 一笔没退 / 有几笔含已核销票要人工跟进 —— 自己写「已取消」会把这些盖掉。
// ★★  ③ 理由必填(会展示给每一位已报名用户),空理由不给提交。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/activity/cancel_activity_sheet.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
}

class _FakeActivityApi implements ActivityApi {
  _FakeActivityApi(this.msg, {this.paidPlayers = 3, this.previewError});
  final String msg;
  final int? paidPlayers;
  final Object? previewError;
  String? sentReason;
  int previewCalls = 0;

  @override
  Future<int> cancelPreview({required int activityId, String? scope}) async {
    previewCalls++;
    if (previewError != null) throw previewError!;
    return paidPlayers!;
  }

  @override
  Future<String> cancelActivity({
    required int activityId,
    required String reason,
  }) async {
    sentReason = reason;
    return msg;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pumpEntry(
  WidgetTester t, {
  required int? hostMemberId,
  required int? myId,
  _FakeActivityApi? api,
}) async {
  await t.binding.setSurfaceSize(const Size(390, 800));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              user: myId == null
                  ? null
                  : User(id: myId, nickname: '我', avatar: '', role: 'player'),
              initialized: true,
            ),
          ),
        ),
        if (api != null) activityApiProvider.overrideWithValue(api),
      ].cast(),
      child: MaterialApp(
        home: Scaffold(
          body: CancelActivityEntry(activityId: 5, hostMemberId: hostMemberId),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  group('★★★ 判不准就不给入口', () {
    test('纯判据', () {
      expect(canCancelActivity(hostMemberId: 7, myMemberId: 7), isTrue);
      expect(canCancelActivity(hostMemberId: 7, myMemberId: 8), isFalse);
      // 三种"判不准":后端没下发 / 没登录 / 值是 0
      expect(
        canCancelActivity(hostMemberId: null, myMemberId: 7),
        isFalse,
        reason: '后端没给主办方 id ⇒ 宁可让真主办方少一个入口',
      );
      expect(canCancelActivity(hostMemberId: 7, myMemberId: null), isFalse);
      expect(
        canCancelActivity(hostMemberId: 0, myMemberId: 0),
        isFalse,
        reason: '两个 0 相等 —— 不判 >0 的话游客会看到这个按钮',
      );
    });

    testWidgets('不是主办方 ⇒ 整块不存在(不是禁用)', (WidgetTester t) async {
      await _pumpEntry(t, hostMemberId: 7, myId: 8);
      expect(find.byKey(const Key('cancel-activity-entry')), findsNothing);
    });

    testWidgets('是主办方 ⇒ 有入口', (WidgetTester t) async {
      await _pumpEntry(t, hostMemberId: 7, myId: 7);
      expect(find.byKey(const Key('cancel-activity-entry')), findsOneWidget);
    });
  });

  testWidgets('★★ 理由必填,空理由不给提交', (WidgetTester t) async {
    final api = _FakeActivityApi('已为 3 笔订单全额退款');
    await _pumpEntry(t, hostMemberId: 7, myId: 7, api: api);
    await t.tap(find.byKey(const Key('cancel-activity-entry')));
    await t.pumpAndSettle();

    final Finder submit = find.byKey(const Key('cancel-activity-submit'));
    expect(
      t.widget<CupertinoButton>(submit).onPressed,
      isNull,
      reason: '理由会展示给每一位已报名用户,后端空值直接拒',
    );

    await t.enterText(find.byType(CupertinoTextField), '场地临时不可用');
    await t.pumpAndSettle();
    expect(t.widget<CupertinoButton>(submit).onPressed, isNotNull);
  });

  testWidgets('★★★ 成功后原样显示后端那句话,不许自己写「已取消」', (WidgetTester t) async {
    // 这是后端三种情况里最容易被前端盖掉的那种:一笔都没自动退。
    const String backendMsg = '无可自动退款的已付款报名;另有 2 笔订单含已核销的票,无法自动退款,平台将人工跟进';
    final api = _FakeActivityApi(backendMsg);
    await _pumpEntry(t, hostMemberId: 7, myId: 7, api: api);

    await t.tap(find.byKey(const Key('cancel-activity-entry')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(CupertinoTextField), '场地临时不可用');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cancel-activity-submit')));
    await t.pumpAndSettle();

    // 二次确认
    await t.tap(find.text('取消并退款'));
    await t.pumpAndSettle();

    expect(api.sentReason, '场地临时不可用');
    expect(
      find.text(backendMsg),
      findsOneWidget,
      reason: '后端这句话区分了退了几笔、有没有要人工跟进的 —— 盖掉它主办方就不知道了',
    );
    expect(find.text('已全额退款给所有已报名用户'), findsNothing, reason: '不许自己编一句好听的');
  });

  group('取消预览(9-18 拍板:确认框必须写明退款给 N 位已付款玩家)', () {
    testWidgets('打开面板就问 cancel_preview,确认框写明 N,确认前不发取消', (
      WidgetTester t,
    ) async {
      final api = _FakeActivityApi('活动已取消', paidPlayers: 5);
      await _pumpEntry(t, hostMemberId: 7, myId: 7, api: api);
      await t.tap(find.byKey(const Key('cancel-activity-entry')));
      await t.pumpAndSettle();
      expect(api.previewCalls, greaterThan(0), reason: 'N 由服务端算,前端不从报名数推');

      await t.enterText(find.byType(CupertinoTextField), '天气原因');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cancel-activity-submit')));
      await t.pumpAndSettle();

      expect(
        find.textContaining('将给 5 位已付款玩家全额退款'),
        findsOneWidget,
        reason: '确认框不写明人数,主办方就是在不知道退款规模时点「不可撤销」',
      );
      expect(api.sentReason, isNull, reason: '确认前不许发取消');
    });

    testWidgets('预览算不出 ⇒ 不弹确认、不发取消,原文说明', (WidgetTester t) async {
      final api = _FakeActivityApi(
        '不该被用到',
        previewError: Exception('暂时算不出退款人数，请稍后重试'),
      );
      await _pumpEntry(t, hostMemberId: 7, myId: 7, api: api);
      await t.tap(find.byKey(const Key('cancel-activity-entry')));
      await t.pumpAndSettle();

      await t.enterText(find.byType(CupertinoTextField), '天气原因');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('cancel-activity-submit')));
      await t.pumpAndSettle();

      expect(
        find.byKey(const Key('cancel-activity-preview-error')),
        findsOneWidget,
        reason: '错误要留在页面上说清楚,不是一晃而过的 toast',
      );
      expect(find.text('取消并退款'), findsNothing, reason: '拿不到 N 就不弹确认');
      expect(api.sentReason, isNull, reason: '拿不到 N 就不发取消');
    });
  });
}
