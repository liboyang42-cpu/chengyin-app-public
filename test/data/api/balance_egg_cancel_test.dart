// 余额流水 / 取消活动 / 收集彩蛋。
//
// 三条各代表一类"静默错":
//   ① 余额流水的参数名是 **change_type**(下划线)。写成驼峰绑不上,
//      筛选静默失效 —— 界面标着「只看支出」,返回的却是全部。
//   ② 取消活动成功后那句话**必须原样透传**。后端在里面区分了三种情况,
//      而且注释写明了为什么不能合并成「无已付款报名」——
//      全部单都含已核销票被跳过时 refundedOrders=0,那句话是假的。
//   ③ 收集彩蛋后端只回 success(),**没有任何 data** ——
//      前端不能说「+N 经验」或「首次收集」之类它并不知道的话。
//
// 另有一条数据语义:余额的 changeType(方向)与 eventType(事由)是两回事。
// 用 eventType 猜方向会错:提现申请(3)是支出、提现驳回(4)是收入,方向相反。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/balance_detail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({DioClient client, List<RequestOptions> sent}) stub(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (client: c, sent: sent);
  }

  Map<String, String> form(RequestOptions o) => <String, String>{
    for (final MapEntry<String, String> e in (o.data as FormData).fields)
      e.key: e.value,
  };

  group('余额流水', () {
    // ⚠️⚠️ 2026-08-20 重写。这里原来有两条测试,断言发的是 `change_type`、
    //   断言 data 是裸 List —— **两条都和后端对不上**,它们把错的行为锁住了,
    //   而且一直是绿的。这就是那个 bug 活了三个月的原因:
    //   测试对着客户端自己的假设写,没对着后端写。
    //   `/api/user/balance/list` 的真实签名是
    //   `ApiUmsMemberController.getBalanceList(String eventType)`,
    //   走 startPage()+getDataTable()。收 change_type、返裸 List 的是
    //   **另一个端点** `/api/balance/list`(ApiBalanceController)。
    test('★★ 参数名是 eventType(事由),不是 change_type —— 后者被后端整个忽略', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'rows': <dynamic>[]},
      });
      await RegistrationApi(
        s.client,
      ).incomeDetail(filter: IncomeEventFilter.brand);
      expect(form(s.sent.single)['eventType'], '2');
      expect(
        form(s.sent.single).containsKey('change_type'),
        isFalse,
        reason: '发 change_type = 界面标着筛选、返回的是全部',
      );
    });

    test('全部时不发 eventType(后端 isNotEmpty 才生效)', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'rows': <dynamic>[]},
      });
      await RegistrationApi(s.client).incomeDetail();
      expect(form(s.sent.single).containsKey('eventType'), isFalse);
    });

    test('★★ 方向看 changeType,不能用 eventType 猜', () {
      // 提现申请(3)是支出、提现驳回(4)是收入 —— 同一件事的两半,方向相反。
      final BalanceDetail apply = BalanceDetail.fromJson(<String, dynamic>{
        'id': 1,
        'eventType': 3,
        'changeType': 2,
        'changeBalance': '100.00',
      });
      final BalanceDetail reject = BalanceDetail.fromJson(<String, dynamic>{
        'id': 2,
        'eventType': 4,
        'changeType': 1,
        'changeBalance': '100.00',
      });
      expect(apply.isExpense, isTrue);
      expect(reject.isIncome, isTrue);
      expect(apply.eventLabel, '提现申请');
      expect(reject.eventLabel, '提现驳回');
    });

    test('★ 符号由 changeType 给 —— 后端存的是绝对值', () {
      final BalanceDetail out = BalanceDetail.fromJson(<String, dynamic>{
        'id': 1,
        'changeType': 2,
        'changeBalance': '30.00',
      });
      expect(out.signedAmount, '-30.00', reason: '按金额自身有没有负号来判的话,所有支出都会显示成收入');
      final BalanceDetail income = BalanceDetail.fromJson(<String, dynamic>{
        'id': 2,
        'changeType': 1,
        'changeBalance': '30.00',
      });
      expect(income.signedAmount, '30.00');
    });

    test('★ 金额缺席是 null,不是 0', () {
      final BalanceDetail d = BalanceDetail.fromJson(<String, dynamic>{
        'id': 1,
        'changeType': 1,
      });
      expect(d.changeBalance, isNull);
      expect(d.signedAmount, isNull);
    });

    test('★ 未知 eventType 说「其他」,不编一个名字', () {
      final BalanceDetail d = BalanceDetail.fromJson(<String, dynamic>{
        'id': 1,
        'eventType': 99,
      });
      expect(d.eventLabel, '其他', reason: '编出来的名字会一直错下去而没人发现');
    });

    test('★★ data 是 getDataTable 的 {rows,total} —— 按裸 List 解析恒空', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'total': 1,
          'rows': <dynamic>[
            <String, dynamic>{
              'id': 1,
              'changeType': 1,
              'changeBalance': '5.00',
            },
          ],
        },
      });
      final r = await RegistrationApi(s.client).incomeDetail();
      expect(
        r.rows.single.id,
        1,
        reason:
            '按裸 List 解析的话这里恒为空 —— 页面显示「暂无收益记录」,'
            '而库里其实有钱',
      );
      expect(r.total, 1);
    });
  });

  group('取消活动', () {
    test('★★ 成功文案原样透传 —— 三种情况后端分好了', () async {
      for (final String msg in <String>[
        '活动已取消,已为 3 笔订单全额退款(原路退回,预计1-3个工作日)',
        '活动已取消(无可自动退款的已付款报名)',
        '活动已取消(无可自动退款的已付款报名);另有 2 笔订单含已核销的票,'
            '无法自动退款,平台将人工跟进处理',
      ]) {
        final s = stub(<String, dynamic>{'code': 200, 'msg': msg});
        expect(
          await ActivityApi(
            s.client,
          ).cancelActivity(activityId: 1, reason: '天气原因'),
          msg,
          reason: '自己写一句"已取消"会把"还有 N 笔要人工跟进"这件事吞掉',
        );
      }
    });

    test('★ reason 必发 —— 它会展示给已报名用户', () async {
      final s = stub(<String, dynamic>{'code': 200, 'msg': '活动已取消'});
      await ActivityApi(
        s.client,
      ).cancelActivity(activityId: 7, reason: '场地临时关闭');
      expect(form(s.sent.single), <String, String>{
        'id': '7',
        'reason': '场地临时关闭',
      });
    });

    test('非主理人被拒 —— 原文透传', () async {
      final s = stub(<String, dynamic>{'code': 500, 'msg': '仅俱乐部主理人可发布活动'});
      await expectLater(
        ActivityApi(s.client).cancelActivity(activityId: 1, reason: 'x'),
        throwsA(predicate((Object e) => e.toString().contains('仅俱乐部主理人'))),
      );
    });

    test('空原因被拒 —— 原文透传', () async {
      final s = stub(<String, dynamic>{
        'code': 500,
        'msg': '请填写取消原因,它会展示给已报名的用户',
      });
      await expectLater(
        ActivityApi(s.client).cancelActivity(activityId: 1, reason: ''),
        throwsA(predicate((Object e) => e.toString().contains('展示给已报名的用户'))),
      );
    });
  });

  group('取消预览(/api/activity/cancel_preview)', () {
    test('N 从 data.paidPlayers 取 —— 确认框「将给 N 位已付款玩家全额退款」的数据源', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'paidPlayers': 12},
      });
      expect(await ActivityApi(s.client).cancelPreview(activityId: 7), 12);
      expect(form(s.sent.single), <String, String>{'id': '7'});
    });

    test('scope 透传(商家主办身份),个人不传', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'paidPlayers': '3'},
      });
      expect(
        await ActivityApi(
          s.client,
        ).cancelPreview(activityId: 7, scope: 'MERCHANT'),
        3,
        reason: '后端 RuoYi 可能把数字回成字符串,解析要认',
      );
      expect(form(s.sent.single), <String, String>{
        'id': '7',
        'scope': 'MERCHANT',
      });
    });

    test('算不出人数 ⇒ 抛后端原文,不回落 0', () async {
      // 「将给 0 位玩家退款」是句假话:0 与"没查出来"必须分得开。
      final s = stub(<String, dynamic>{'code': 500, 'msg': '无权取消该活动'});
      await expectLater(
        ActivityApi(s.client).cancelPreview(activityId: 1),
        throwsA(predicate((Object e) => e.toString().contains('无权取消该活动'))),
      );

      final s2 = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await expectLater(
        ActivityApi(s2.client).cancelPreview(activityId: 1),
        throwsA(predicate((Object e) => e.toString().contains('算不出退款人数'))),
      );
    });
  });

  group('主题取消(/api/topic/cancel + /api/topic/cancel_preview)', () {
    test('[C8-05] 取消主题:表单带 id/reason/scope,成功文案原样透传', () async {
      const String backendMsg = '主题已取消,已为 4 笔订单全额退款(原路退回,预计1-3个工作日)';
      final s = stub(<String, dynamic>{'code': 200, 'msg': backendMsg});
      expect(
        await TopicApi(
          s.client,
        ).cancel(topicId: 9, reason: '主办方取消主题', scope: 'MERCHANT'),
        backendMsg,
        reason: 'msg 里区分了退了几笔/含已核销票要人工跟进,盖掉就丢了',
      );
      expect(form(s.sent.single), <String, String>{
        'id': '9',
        'reason': '主办方取消主题',
        'scope': 'MERCHANT',
      });
    });

    test('取消被拒 —— 后端写给主办方的话原文透传', () async {
      final s = stub(<String, dynamic>{
        'code': 500,
        'msg': '请填写取消原因,它会展示给已付款的玩家',
      });
      await expectLater(
        TopicApi(s.client).cancel(topicId: 1, reason: ''),
        throwsA(predicate((Object e) => e.toString().contains('展示给已付款的玩家'))),
      );
    });

    test('预览:N 从 data.paidPlayers 取;算不出抛原文不回落 0', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'paidPlayers': 6},
      });
      expect(await TopicApi(s.client).cancelPreview(topicId: 9), 6);
      expect(form(s.sent.single), <String, String>{'id': '9'});

      final s2 = stub(<String, dynamic>{'code': 500, 'msg': '系统繁忙，请稍后重试'});
      await expectLater(
        TopicApi(s2.client).cancelPreview(topicId: 9),
        throwsA(predicate((Object e) => e.toString().contains('系统繁忙'))),
      );
    });
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);
  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(onRequest(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
