// R10 门禁:提现出口**只有一处**。
//
// 背景(P1-1 / P1-2,PR #227 问题清单):同一个客服号原来写了两遍 ——
// 共用件 `withdrawal_contact_dialog.dart` 一份、club 结算页内联一份,
// 文案也各写一套。将来换号(§9 还可能改成对方微信号)**改一处漏一处,
// 用户拿到错号就是线下汇款汇错人**。所以钉两件事:
//   ① 号码字面量全仓(lib,已剥注释)恰好一处;
//   ② 弹窗话术逐字等于小程序真源 `chengyinhub-xcx/utils/withdraw-cs.js`
//      (标题 / 正文 / 复制成功提示),两端口径不许各说一套。
//
// 弹窗**行为**(不发提现请求 / 「复制」写剪贴板 / 「返回」只关窗)由
// `withdrawal_r10_dialog_test.dart` 盯,这里不重复造。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/withdrawal/withdrawal_contact_dialog.dart';

import '../../support/source_text.dart';

const String _kDialogPath =
    'lib/feature/withdrawal/withdrawal_contact_dialog.dart';

void main() {
  test('★ 客服微信号全仓只有一处字面量(R10 出口唯一化)', () {
    final String needle = kWithdrawalContactWechatId;
    expect(
      needle,
      matches(RegExp(r'^\d{8,}$')),
      reason: '常量必须是真实微信号形态 —— 换成占位值这条门禁就失效了',
    );

    final List<String> hits = <String>[];
    int scanned = 0;
    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      if (codeOf(e.path).contains(needle)) hits.add(e.path);
    }

    expect(
      scanned,
      greaterThan(100),
      reason: '只扫到 $scanned 个 lib 文件 —— 断言写法失效了(工作目录不对?)',
    );
    expect(
      hits,
      <String>[_kDialogPath],
      reason:
          '提现入口的号只能有一个来源,多出来的地方就是「换号漏改」的坑'
          '(旧的两套实现见 PR #227 P1-1):\n${hits.join('\n')}',
    );
  });

  test('★ 弹窗话术逐字等于小程序真源(chengyinhub-xcx/utils/withdraw-cs.js)', () {
    final String src = codeOf(_kDialogPath);
    // 真源:`utils/withdraw-cs.js` 的 showWithdrawCsPopup ——
    //   标题「联系平台客服提现」/ 正文「客服微信号：<号>\n添加客服微信，核对金额后线下处理」
    //   / 复制成功 toast「已复制微信号」。
    for (final String expected in <String>[
      '联系平台客服提现',
      '添加客服微信，核对金额后线下处理',
      '返回',
      '复制',
      '已复制微信号',
    ]) {
      expect(
        src.contains(expected),
        isTrue,
        reason: 'App 弹窗缺了真源话术「$expected」—— 文案要跟小程序 1:1,别自己另写一套',
      );
    }
  });
}
