// CRM 导出任务的解析与文案。
//
// ★★ 这个模型的全部价值在 `tryParse` 的**严格**上:它对着小程序
//   `shapeExportTask`(pages/merchant/customer/index.js:1241)来的 ——
//   那是一张白名单,不是"取个默认值"。回到 null 的含义是
//   "这一帧状态不可信",调用方应保留上一帧并重查,
//   而不是把界面落到一个编造的态上(比如把 SUCCESS 少个 rowCount
//   显示成"导出已就绪(0 行)")。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant_crm_export.dart';

void main() {
  MerchantCrmExportTask? parse(Map<String, dynamic> json) =>
      MerchantCrmExportTask.tryParse(json);

  Map<String, dynamic> base({int id = 12, String status = 'PENDING'}) =>
      <String, dynamic>{'id': id, 'status': status};

  group('白名单:五个态', () {
    for (final String s in <String>[
      'PENDING',
      'RUNNING',
      'SUCCESS',
      'FAILED',
      'EXPIRED',
    ]) {
      test('$s 认', () {
        final MerchantCrmExportTask? t = parse(<String, dynamic>{
          ...base(status: s),
          if (s == 'SUCCESS') 'rowCount': 3,
        });
        expect(t, isNotNull);
        expect(t!.status, s);
      });
    }
  });

  group('★★ 不可信的一帧 → null(别编状态)', () {
    test('没 id / id 不是正数', () {
      expect(parse(<String, dynamic>{'status': 'PENDING'}), isNull);
      expect(parse(base(id: 0)), isNull);
      expect(parse(base(id: -1)), isNull);
    });

    test('未知状态码', () {
      expect(parse(base(status: 'QUEUED')), isNull);
      expect(parse(base(status: 'success')), isNull, reason: '大小写不宽容');
      expect(parse(base(status: '')), isNull);
    });

    test('★★ SUCCESS 却没有行数', () {
      expect(
        parse(base(status: 'SUCCESS')),
        isNull,
        reason: '落成"导出已就绪(0 行)"是把没读到说成读到了',
      );
      expect(
        parse(<String, dynamic>{...base(status: 'SUCCESS'), 'rowCount': -1}),
        isNull,
      );
    });

    test('非 SUCCESS 的态可以不带行数', () {
      expect(parse(base(status: 'RUNNING'))?.rowCount, isNull);
    });
  });

  group('轮询收口判据', () {
    test('只有 PENDING / RUNNING 要继续轮询', () {
      expect(parse(base())!.isRunning, isTrue);
      expect(parse(base(status: 'RUNNING'))!.isRunning, isTrue);
      for (final String s in <String>['SUCCESS', 'FAILED', 'EXPIRED']) {
        final MerchantCrmExportTask t = parse(<String, dynamic>{
          ...base(status: s),
          if (s == 'SUCCESS') 'rowCount': 1,
        })!;
        expect(
          t.isRunning,
          isFalse,
          reason: '继续轮询一个已经收口的任务 = 白打后端,而且状态永远不会变',
        );
      }
    });
  });

  group('文案(逐字对齐 wxml:89-92)', () {
    test('生成中说清"可以继续浏览客户",不是干等', () {
      expect(
        parse(base())!.statusLabel,
        '正在生成脱敏 Excel,可继续浏览客户',
      );
    });

    test('成功要带行数', () {
      expect(
        parse(<String, dynamic>{...base(status: 'SUCCESS'), 'rowCount': 37})!
            .statusLabel,
        '导出已就绪(37 行)',
      );
    });

    test('过期要说"重新创建",失败就说失败', () {
      expect(
        parse(base(status: 'EXPIRED'))!.statusLabel,
        '导出已过期,请重新创建',
      );
      expect(parse(base(status: 'FAILED'))!.statusLabel, '导出失败');
    });
  });

  group('下载凭证', () {
    test('★ 从**创建**响应里解析出来', () {
      expect(
        parse(<String, dynamic>{...base(), 'downloadToken': 'tok-1'})
            ?.downloadToken,
        'tok-1',
      );
    });

    test('★ 轮询响应通常不带它 —— 缺席保持 null,不是空串', () {
      expect(parse(base())?.downloadToken, isNull);
    });

    test('失败原因从 errorMessage 读', () {
      expect(
        parse(<String, dynamic>{...base(status: 'FAILED'), 'errorMessage': '模板损坏'})
            ?.errorMessage,
        '模板损坏',
      );
    });
  });
}
