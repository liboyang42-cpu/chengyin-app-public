// 商家资金域四条查询。
//
// ★★ 这一批全是钱,而钱的错法和别处不同:**不会崩、不会空,只会数不对**。
//   三条最要命的:
//   ① 金额是 String,不能 parse 成 double 再格式化 ——
//      后端用 String 正是为了避开浮点误差,前端转一圈等于把它请回来;
//   ② `signedAmount` **带符号**,调整项是负数。丢了符号,
//      一笔扣款就显示成一笔收入,而总账还"对得上"(错的只是这一行的方向);
//   ③ 金额缺席时是 null,不是 "0.00"。兜成零 = 把"没这个数"说成"零元"。
//
// 另有一条越权语义:批次详情查别人的批次,后端回 error("记录不可见")——
// 那是保护,不是"这条没了",提示要照原文。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import '../../support/source_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({MerchantApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: MerchantApi(c), sent: sent);
  }

  group('已成立收入与调整明细', () {
    test('★★ 负数分录的符号必须留着', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{
              'entryKey': 'e1',
              'signedAmount': '128.50',
              'entryKind': 'EARNING',
            },
            <String, dynamic>{
              'entryKey': 'e2',
              'signedAmount': '-30.00',
              'entryKind': 'ADJUSTMENT',
            },
          ],
          'total': 2,
          'pageNum': 1,
          'pageSize': 20,
        },
      });
      final page = await r.api.settlementEntries();
      expect(page.rows[0].signedAmount, '128.50');
      expect(page.rows[1].signedAmount, '-30.00', reason: '丢了负号,这笔扣款会显示成收入');
      expect(page.rows[1].isDeduction, isTrue);
      expect(page.rows[0].isDeduction, isFalse);
    });

    test('★★ 金额原样保留,不做 double 往返', () async {
      // 0.1+0.2 这类在 double 上会飘;这里用一个 double 无法精确表示的值。
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{'entryKey': 'e1', 'signedAmount': '1234567.89'},
          ],
          'total': 1,
          'pageNum': 1,
          'pageSize': 20,
        },
      });
      final page = await r.api.settlementEntries();
      expect(
        page.rows.single.signedAmount,
        '1234567.89',
        reason: '只要中间转过 double,这里就可能变成 1234567.8899999999',
      );
    });

    test('★ 金额缺席是 null,不是 "0.00"', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{'entryKey': 'e1'},
          ],
          'total': 1,
          'pageNum': 1,
          'pageSize': 20,
        },
      });
      expect(
        (await r.api.settlementEntries()).rows.single.signedAmount,
        isNull,
        reason: '兜成零 = 把「没这个数」说成「零元」',
      );
    });

    test('默认 source=all,与后端默认一致', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'rows': <dynamic>[], 'total': 0},
      });
      await r.api.settlementEntries();
      final Map<String, dynamic> sent = (r.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(sent['source'], 'all');
    });

    test('分页 hasMore', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[],
          'total': 41,
          'pageNum': 2,
          'pageSize': 20,
        },
      });
      expect((await r.api.settlementEntries(pageNum: 2)).hasMore, isTrue);
    });
  });

  group('对公结算批次', () {
    test('★ netDirection 缺席保持 null —— 猜方向会把应付显示成应收', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{'batchId': 'B1', 'amountTotal': '900.00'},
          ],
          'total': 1,
          'pageNum': 1,
          'pageSize': 20,
        },
      });
      final PublicTransferBatch b =
          (await r.api.publicTransferBatches()).rows.single;
      expect(b.netDirection, isNull);
      expect(b.amountTotal, '900.00');
    });

    test('★ 批次详情:收入与调整**分成两个列表**,不合并', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'batch': <String, dynamic>{'batchId': 'B1'},
          'earningEntries': <dynamic>[
            <String, dynamic>{'entryKey': 'e1', 'signedAmount': '100.00'},
          ],
          'adjustments': <dynamic>[
            <String, dynamic>{'entryKey': 'a1', 'signedAmount': '-10.00'},
          ],
        },
      });
      final PublicTransferBatchDetail d = await r.api.publicTransferBatchDetail(
        1,
      );
      expect(d.earningEntries.length, 1);
      expect(
        d.adjustments.single.isDeduction,
        isTrue,
        reason: '合并成一个列表就看不出哪些是扣减了',
      );
    });

    test('★★ 查别人的批次 → 「记录不可见」原文透传,不是「加载失败」', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '记录不可见'});
      await expectLater(
        r.api.publicTransferBatchDetail(999),
        throwsA(predicate((Object e) => e.toString().contains('记录不可见'))),
      );
    });
  });

  group('核销详情', () {
    test('★ recordType 后端只认 "redemption",默认就发它', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'recordKey': 'r1'},
      });
      await r.api.redemptionDetail(recordId: '7');
      final Map<String, dynamic> sent = (r.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(sent['recordType'], 'redemption', reason: '别的值后端一律当查不到,返回「记录不可见」');
      expect(sent['recordId'], '7');
    });

    test('★ noCashReason 非空时要能拿到 —— 否则商家看到 ¥0.00 以为算错了', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'recordKey': 'r1',
          'settlementAmount': '0.00',
          'noCashReason': '本场为零现金开售,权益由平台补贴',
        },
      });
      final MerchantRedemptionView v = await r.api.redemptionDetail(
        recordId: '7',
      );
      expect(v.noCashReason, isNotNull);
      expect(v.settlementAmount, '0.00');
    });

    test('顾客名原样透传 —— 后端已按 PII 规则处理过', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'recordKey': 'r1',
          'customerDisplayName': '王**',
          'verificationCodeTail': '4821',
        },
      });
      final v = await r.api.redemptionDetail(recordId: '7');
      expect(v.customerDisplayName, '王**');
      expect(v.verificationCodeTail, '4821');
    });
  });

  test('★★ 四条的金额字段在代码里都不许出现 double 解析', () {
    // 这条盯的是**将来**有人"顺手格式化一下"。
    // ★ 剥注释再扫 —— 注释里必然写着被禁的写法(它正在解释为什么不能那么写)。
    final String src = codeOf('lib/data/models/merchant_finance.dart');
    for (final String bad in <String>[
      'double.parse',
      'double.tryParse',
      'toStringAsFixed',
      'num.parse',
    ]) {
      expect(
        src.contains(bad),
        isFalse,
        reason:
            '$bad 会把后端刻意避开的浮点误差请回来 —— '
            '要显示就原样显示,要比大小才临时解析',
      );
    }
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
