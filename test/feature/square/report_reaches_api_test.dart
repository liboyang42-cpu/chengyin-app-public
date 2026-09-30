// 举报必须真的发出去。
//
// ★★ 2026-08-20 抓到:两处举报都写着 `if (ok != true) return;`,
//   而 showReportSheet 返回的是 `Future<String?>`(举报理由,取消时 null)。
//   String? 永远 != true ⇒ **每次举报都在调接口之前 return**。
//   弹窗照开、理由照选,一条都没发出去 —— 而这功能正是为
//   Apple 审核指南 1.2 加的,审核时点一次就露馅。
//
// ★ 2026-09-17 改口径:后端 `/api/creativesquare/report` 与 `/api/comment/report`
//   都**不收理由**(见 `contract/openapi-v1.json` 与后端 ReportController),
//   所以界面不再让用户选一个会被丢掉的理由,改成 `cyConfirm` 确认一次。
//   理由单没了,这条门禁要锁的东西不变 —— 「确认之后,举报真的发出去了」,
//   只是锚点从 `_chooseReportReason` 换成 `cyConfirm`。
//   行为断言(点确认 → report:7 / reportComment:3;点取消 → 零请求)在
//   `test/feature/square/square_interactions_test.dart`。
//
// ⚠️ 为什么以前没抓到:analyzer 早就在报 unrelated_type_equality_checks,
//   但它是 **info** 级,淹在输出里没人看。类型系统给了信号,门禁没接住。
//   所以这条测试不只锁行为,还锁「不许再出现 `!= true` 那种写法」。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  test('★★ 举报:确认一次之后真的打出去,不许点一下就 return', () {
    final String src = codeOf('lib/feature/square/square_detail_page.dart');
    // 动态和评论两个举报入口都必须受这条门禁保护。
    const List<({String handler, String call})> entrances =
        <({String handler, String call})>[
          (handler: '_report', call: '.report(widget.postId)'),
          (handler: '_reportComment', call: '.reportComment(commentId)'),
        ];
    for (final ({String handler, String call}) entrance in entrances) {
      final int start = src.indexOf('Future<void> ${entrance.handler}(');
      expect(start, isNonNegative, reason: '${entrance.handler} 入口不见了');
      final int end = src.indexOf('\n  }\n', start);
      expect(end, greaterThan(start), reason: '${entrance.handler} 收不到函数体');
      final String body = src.substring(start, end);
      expect(
        body.contains('await cyConfirm('),
        isTrue,
        reason: '${entrance.handler}:举报前要确认一次(Apple 1.2 / 小程序同口径)',
      );
      expect(
        body.contains('!= true'),
        isFalse,
        reason: '又写成跟 true 比了 —— 举报会在调接口前 return,一条都发不出去',
      );
      expect(
        body.contains(entrance.call),
        isTrue,
        reason: '${entrance.handler}:确认之后必须真的打到接口,不能只弹个窗',
      );
    }
    expect(
      RegExp(r'CommunityReportSelection').hasMatch(src),
      isFalse,
      reason: '后端不收理由了,别再让用户选一个会被丢掉的理由',
    );
  });

  test('★ analyzer 的 unrelated_type_equality_checks 不许再有', () {
    // info 级警告淹在输出里没人看,这里把它升级成会红的断言。
    final ProcessResult r = Process.runSync('dart', <String>[
      'analyze',
      'lib/feature/square/square_detail_page.dart',
    ]);
    expect(
      r.stdout.toString().contains('unrelated_type_equality_checks'),
      isFalse,
      reason: '类型系统已经在提示了,别再让它是 info:\n${r.stdout}',
    );
  });
}
