// coop 三处字段/形状与后端对不上 —— 全是「不报错的错」。
//
// ★★★ 由 T3 worker 在动手前抽查前提时发现,我逐条核实后确认三条都属实。
//   (任务书写的「已核实」只是我的核实、不是免检 —— 这次就是它救了三处。)
//
// ① `/api/coop/candidates/confirm`:App 发 `regId`,后端读
//    `body.get("registrationId")`(ApiCoopController:766)
//    ⇒ **每次都返回「缺少报名」**,跟传的 id 对不对无关。
// ② `/api/coop/list`:后端返的是裸 Map `{sent, received, slots}`(957-961),
//    **不是 getDataTable**。App 读 `data['rows']` ⇒ 永远空列表,且不报错
//    ⇒ 界面一直显示「还没有邀约」,那是假话。
// ③ `/api/coop/review/save`:App 发 `content`,后端域对象字段是
//    `CoopReview.comment`(CoopReview.java:19)⇒ 评语被 Jackson **静默丢弃**,
//    评分照样成功。三条里这条最坏 —— 它连失败都不报。

import 'package:dio/dio.dart';
import 'package:chengyin_app/data/models/coop_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart'
    show CoopHandleAction;

/// 拦下请求,只记录不发出去。断言「发了什么」——这类 bug 只在报文里看得见。
class _Recorder extends Interceptor {
  final List<(String, Object?)> calls = <(String, Object?)>[];
  Map<String, dynamic> reply = <String, dynamic>{};
  Object code = 200;
  String? msg = 'ok';
  bool networkError = false;

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    calls.add((o.path, o.data));
    if (networkError) {
      h.reject(
        DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
          message: 'request:fail',
        ),
      );
      return;
    }
    h.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: o,
        statusCode: 200,
        data: <String, dynamic>{'code': code, 'msg': msg, 'data': reply},
      ),
    );
  }
}

(CoopApi, _Recorder) _api() {
  final rec = _Recorder();
  // TokenStore 在这条链路上用不到(拦截器直接 resolve,不会走到取 token)。
  final client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.interceptors.clear();
  client.dio.interceptors.add(rec);
  return (CoopApi(client), rec);
}

void main() {
  test('★★★ ① 确认候选发的 key 是 registrationId,不是 regId', () async {
    final (CoopApi api, _Recorder rec) = _api();
    await api.confirmCandidate(42);
    final Map<String, dynamic> body = (rec.calls.single.$2 as Map)
        .cast<String, dynamic>();
    expect(body['registrationId'], 42);
    expect(
      body.containsKey('regId'),
      isFalse,
      reason: '后端读的是 registrationId —— 发 regId 每次都回「缺少报名」',
    );
  });

  test('★★★ ② coop/list 返的是裸 Map{sent,received,slots},不是分页 rows', () async {
    final (CoopApi api, _Recorder rec) = _api();
    rec.reply = <String, dynamic>{
      'sent': <dynamic>[
        <String, dynamic>{'id': 1},
      ],
      'received': <dynamic>[
        <String, dynamic>{'id': 2},
      ],
      'slots': <String, dynamic>{'byGame': <String, dynamic>{}},
    };
    final Map<String, dynamic> data = await api.inviteList();
    // 三样都在同一次响应里 —— 读 data['rows'] 的旧写法会恒空且不报错,
    // 界面就会一直说「还没有邀约」,那是假话。
    expect((data['sent'] as List<dynamic>).length, 1);
    expect((data['received'] as List<dynamic>).length, 1);
    expect(data['slots'], isA<Map<String, dynamic>>());
    expect(
      data.containsKey('rows'),
      isFalse,
      reason: '后端根本没有 rows 这层 —— 谁再按分页去读都会恒空',
    );
    // ⚠️ 只调了**一次**:三样是一次响应的三半,拆成两个方法取就是白打请求。
    expect(rec.calls.length, 1);
  });

  test('★★★ ③ 评价发的 key 是 comment,不是 content', () async {
    final (CoopApi api, _Recorder rec) = _api();
    await api.saveReview(topicId: 1, toId: 2, rating: 5, content: '很靠谱');
    final Map<String, dynamic> body = (rec.calls.single.$2 as Map)
        .cast<String, dynamic>();
    expect(
      body['comment'],
      '很靠谱',
      reason: '后端字段是 CoopReview.comment —— 发 content 会被静默丢弃',
    );
    expect(body.containsKey('content'), isFalse);
    expect(body['rating'], 5);
  });

  test('★ 没写评语时不发这个 key(而不是发空串)', () async {
    final (CoopApi api, _Recorder rec) = _api();
    await api.saveReview(topicId: 1, toId: 2, rating: 5);
    final Map<String, dynamic> body = (rec.calls.single.$2 as Map)
        .cast<String, dynamic>();
    expect(body.containsKey('comment'), isFalse);
  });

  test('★★★ ④ 处理邀约的理由 key 按动作分岔:接受/拒绝 handleReason,取消 message', () async {
    // 后端 ApiCoopController.handle 读的字段名两个动作不同(`CoopInvite` 上
    // handleReason 与 message 互相独立)。统一发一个 key 的后果不是报错,
    // 而是**接受/拒绝时写的那句回复被静默丢掉** —— 和小程序审查记的 C1 同型。
    for (final (CoopHandleAction action, String key)
        in <(CoopHandleAction, String)>[
          (CoopHandleAction.accept, 'handleReason'),
          (CoopHandleAction.reject, 'handleReason'),
          (CoopHandleAction.cancel, 'message'),
        ]) {
      final (CoopApi api, _Recorder rec) = _api();
      await api.handleInvite(inviteId: 9, action: action, reason: '理由');
      final Map<String, dynamic> body = (rec.calls.single.$2 as Map)
          .cast<String, dynamic>();
      expect(body[key], '理由', reason: '${action.name} 应该走 $key');
      expect(
        body.containsKey(
          action == CoopHandleAction.cancel ? 'handleReason' : 'message',
        ),
        isFalse,
        reason: '发错的 key 只会让后端当没填 —— 不报错、也不生效',
      );
      expect(body['id'], 9);
      expect(body['status'], action.wire);
    }
  });

  test('★ 没写理由时不发理由 key(而不是发空串)', () async {
    final (CoopApi api, _Recorder rec) = _api();
    await api.handleInvite(inviteId: 9, action: CoopHandleAction.cancel);
    final Map<String, dynamic> body = (rec.calls.single.$2 as Map)
        .cast<String, dynamic>();
    expect(body.containsKey('message'), isFalse);
    expect(body.containsKey('handleReason'), isFalse);
  });

  test('保证金 App 支付只调用独立 APP 建单端点', () async {
    final (CoopApi api, _Recorder rec) = _api();
    rec.reply = <String, dynamic>{
      'appId': 'wx-app',
      'partnerId': 'merchant',
      'prepayId': 'prepay',
      'packageValue': 'Sign=WXPay',
      'nonceStr': 'nonce',
      'timeStamp': '1700000000',
      'sign': 'signature',
    };

    final Map<String, String> params = await api.createDeposit(42);

    expect(rec.calls.single.$1, '/api/coop/deposit/create/app');
    expect(rec.calls.single.$2, <String, dynamic>{'inviteId': 42});
    expect(params['packageValue'], 'Sign=WXPay');
    expect(params['prepayId'], 'prepay');
  });

  test('保证金支付回读传原 inviteId，只接受后端四种终态', () async {
    final (CoopApi api, _Recorder rec) = _api();
    rec.reply = <String, dynamic>{'inviteId': 42, 'paymentStatus': 'success'};

    expect(await api.depositStatus(42), 'success');
    expect(rec.calls.single.$1, '/api/coop/deposit/status');
    expect(rec.calls.single.$2, <String, dynamic>{'inviteId': 42});

    rec
      ..calls.clear()
      ..reply = <String, dynamic>{'paymentStatus': 'invented'};
    expect(await api.depositStatus(42), 'unknown');
  });

  // 保证金退款重试的「可确认成功」三闸(真源 pages/coop/list/index.js:909-928):
  // code 200 + data.refundState 是字符串 + msg 非空 —— 缺一个都不能当成
  // 退款已重发。状态未知时催用户去核对,不给他「再点一次也许就成了」的错觉。
  test('退款重试:只有 code200+refundState+非空 msg 才算可确认成功', () async {
    final (CoopApi api, _Recorder rec) = _api();
    rec
      ..msg = '退款已重新发起'
      ..reply = <String, dynamic>{'refundState': 'processing'};
    expect(await api.retryDepositRefund(42), '退款已重新发起');
    expect(rec.calls.single.$1, '/api/coop/deposit/refund/retry');
    expect(rec.calls.single.$2, <String, dynamic>{'inviteId': 42});

    // refundState 不是字符串(后端没给终态)→ 不可确认。
    rec
      ..calls.clear()
      ..reply = <String, dynamic>{'refundState': 1};
    await expectLater(
      api.retryDepositRefund(42),
      throwsA(predicate((Object e) => '$e'.contains('退款结果暂无法确认，请先核对，勿重复提交'))),
    );

    // msg 空白 → 同样不可确认。
    rec
      ..calls.clear()
      ..msg = '  '
      ..reply = <String, dynamic>{'refundState': 'processing'};
    await expectLater(
      api.retryDepositRefund(42),
      throwsA(predicate((Object e) => '$e'.contains('退款结果暂无法确认，请先核对，勿重复提交'))),
    );
  });

  test('退款重试:业务失败透传后端原话,没原话才用兜底', () async {
    final (CoopApi api, _Recorder rec) = _api();
    rec
      ..code = 500
      ..msg = '退款单不存在'
      ..reply = <String, dynamic>{'refundState': 'processing'};
    await expectLater(
      api.retryDepositRefund(42),
      throwsA(predicate((Object e) => '$e'.contains('退款单不存在'))),
    );

    rec
      ..calls.clear()
      ..msg = '';
    await expectLater(
      api.retryDepositRefund(42),
      throwsA(predicate((Object e) => '$e'.contains('退款重试失败'))),
    );
  });

  test('退款重试:网络失败也报「暂无法确认」,不冒充没发出去', () async {
    final (CoopApi api, _Recorder rec) = _api();
    rec.networkError = true;
    await expectLater(
      api.retryDepositRefund(42),
      throwsA(predicate((Object e) => '$e'.contains('退款结果暂无法确认，请先核对，勿重复提交'))),
    );
  });
  test('missing messages are local while identical server wording remains external', () async {
    final (api, rec) = _api();
    rec
      ..code = 500
      ..msg = null;
    await expectLater(api.pool(), throwsA(isA<CoopFailure>()
        .having((e) => e.isLocalFallback, 'local origin', isTrue)
        .having((e) => e.kind, 'kind', CoopFailureKind.operation)));
    for (final message in ['操作失败', '  English business rejection  ', '']) {
      rec.msg = message;
      await expectLater(api.pool(), throwsA(isA<CoopFailure>()
          .having((e) => e.isLocalFallback, 'server origin', isFalse)
          .having((e) => e.message, 'verbatim', message)));
    }
  });

  test('refund receipt preserves original whitespace and unknown failure provenance', () async {
    final (api, rec) = _api();
    rec..msg = '  Pending manual verification  '
       ..reply = {'refundState': 'processing'};
    expect(await api.retryDepositRefund(42), '  Pending manual verification  ');
    rec.reply = {'refundState': 4};
    await expectLater(api.retryDepositRefund(42), throwsA(isA<CoopFailure>()
        .having((e) => e.kind, 'unknown refund', CoopFailureKind.refundUnknown)
        .having((e) => e.isLocalFallback, 'local origin', isTrue)));
  });

}
