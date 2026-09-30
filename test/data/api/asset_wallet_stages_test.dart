// 余额三段:`POST /api/wallet/stages`。
//
// ★ 这块的全部逻辑是「如实」:字段缺失 / 不是数 / 日期坏 ⇒ 整块判「取不到」,
//   **绝不把缺失渲染成 ¥0**。口径逐条对齐小程序
//   `components/cy/funds-stages/view-model.js`(它有自己的 node:test 用例)。
// ★ 后端是 `@RequestBody` 端点 —— 发成表单会 415,三段就恒「取不到」;
//   小程序侧为这条专门有一条 header 契约测试,这里钉同一件事。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/asset_api.dart';
import 'package:chengyin_app/data/models/funds_stages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  group('三段口径', () {
    test('三段 + 涉诉单列:客诉期按可提现日逐条标「X月X日可提现」', () {
      final FundsStages? stages = buildFundsStages(<String, dynamic>{
        'amountsKnown': true,
        'pendingSettlement': 90,
        'complaintPeriod': <dynamic>[
          <String, dynamic>{'amount': 45.5, 'availableDate': '2026-09-24'},
          <String, dynamic>{'amount': 0, 'availableDate': '2026-09-25'},
        ],
        'disputed': '18.00',
        'withdrawable': 12,
      });
      expect(stages, isNotNull);
      expect(stages!.pending, '90.00');
      // 金额为 0 的那条不画(小程序 `amount > 0` 才 push)。
      expect(stages.complaintPeriod.length, 1);
      expect(stages.complaintPeriod.single.label, '客诉期中 · 9月24日可提现');
      expect(stages.complaintPeriod.single.amountText, '45.50');
      expect(stages.disputed, '18.00');
      expect(stages.withdrawable, '12.00');
      expect(stages.amountsKnown, isTrue);
    });

    test('0 是合法金额:照常算出三段,只是 ≤0 的那几段文本为空(不画)', () {
      final FundsStages? stages = buildFundsStages(<String, dynamic>{
        'amountsKnown': true,
        'pendingSettlement': 0,
        'complaintPeriod': <dynamic>[],
        'disputed': 0,
        'withdrawable': 0,
      });
      expect(stages, isNotNull);
      expect(stages!.pending, '');
      expect(stages.disputed, '');
      expect(stages.withdrawable, '0.00');
    });

    test('字段缺失/非数/日期坏 ⇒ null(页面说取不到,不显示 ¥0)', () {
      final Map<String, dynamic> ok = <String, dynamic>{
        'pendingSettlement': 0,
        'complaintPeriod': <dynamic>[],
        'disputed': 0,
        'withdrawable': 0,
      };
      expect(buildFundsStages(ok), isNotNull);
      expect(buildFundsStages(null), isNull);
      expect(
        buildFundsStages(<String, dynamic>{...ok}..remove('withdrawable')),
        isNull,
      );
      expect(
        buildFundsStages(<String, dynamic>{...ok, 'disputed': 'abc'}),
        isNull,
      );
      expect(
        buildFundsStages(<String, dynamic>{...ok}..remove('complaintPeriod')),
        isNull,
      );
      expect(
        buildFundsStages(<String, dynamic>{
          ...ok,
          'complaintPeriod': <dynamic>[
            <String, dynamic>{'amount': 1, 'availableDate': '9/24'},
          ],
        }),
        isNull,
      );
    });

    test('后端说费率算不出(amountsKnown=false)时如实提示,不编数', () {
      final FundsStages? stages = buildFundsStages(<String, dynamic>{
        'amountsKnown': false,
        'pendingSettlement': 0,
        'complaintPeriod': <dynamic>[],
        'disputed': 0,
        'withdrawable': 5,
      });
      expect(stages!.amountsKnown, isFalse);
      expect(stages.pending, '');
    });
  });

  group('报文', () {
    ({AssetApi api, List<RequestOptions> sent}) build(
      Map<String, dynamic> reply,
    ) {
      final DioClient client = DioClient(
        TokenStore(const FlutterSecureStorage()),
      );
      final List<RequestOptions> sent = <RequestOptions>[];
      client.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
        sent.add(o);
        return reply;
      });
      return (api: AssetApi(client), sent: sent);
    }

    test('POST /api/wallet/stages,JSON 体(不是 FormData —— 发错 = 415)', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'amountsKnown': true,
          'pendingSettlement': 1,
          'complaintPeriod': <dynamic>[],
          'disputed': 0,
          'withdrawable': 2,
        },
      });
      await r.api.walletStages();

      final RequestOptions sent = r.sent.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/wallet/stages');
      expect(sent.data, isA<Map<String, dynamic>>());
      expect(sent.data, isNot(isA<FormData>()));
    });

    test('业务码非 200 抛后端原文;data 读不懂 = 取不到(null),不抛', () async {
      final failed = build(<String, dynamic>{'code': 401, 'msg': '登录状态已失效'});
      await expectLater(
        failed.api.walletStages(),
        throwsA(predicate((Object e) => '$e'.contains('登录状态已失效'))),
      );

      final junk = build(<String, dynamic>{'code': 200, 'data': 'not-a-map'});
      expect(await junk.api.walletStages(), isNull);
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
