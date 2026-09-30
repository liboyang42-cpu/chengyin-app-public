// 项目主页 / 玩家名单两页的硬约束。
//
// ★★ ① `host` 与 `join` **可以同时存在** —— 既主办又报名过的人两块都该看到。
//   `role` 只说哪个是主身份,不是二选一。写成 if/else 会让那个人少看到一半。
//
// ★★ ② 联系方式**前端不做脱敏**。后端原话:
//   「前端过滤等于把号码先发出去再假装没发」。
//   拿到就显示、没拿到就整行不显示,不放 **** 占位。
//
// ★★ ③ 看不到号码时必须显示后端给的 contactHint。后端原话:
//   「不能只给一个 false 就完事:商家会以为是 bug。说清为什么、以及该找谁」。
//
// ★ ④ 「已退款」必须单独一态 —— 混进「未到店」的话,
//   商家会一直等一个不会来的人。

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

bool usesRoleToChooseSection(String source) =>
    RegExp(r'\b(?:if|switch)\s*\([^)]*\brole\b').hasMatch(source);

void main() {
  final String home = codeOf('lib/feature/merchant/project_home_page.dart');
  final String players = codeOf(
    'lib/feature/merchant/project_players_page.dart',
  );

  test('★★ host 与 join 两块都渲染,不是 if/else', () {
    expect(home.contains('if (host != null)'), isTrue);
    expect(home.contains('if (join != null)'), isTrue);
    // 出现 else 分支就说明当成二选一了。
    expect(
      home.contains('} else if (join'),
      isFalse,
      reason: '既主办又报名过的人会少看到一半',
    );
    expect(
      usesRoleToChooseSection(home),
      isFalse,
      reason: 'role 只说哪个是主身份,拿它决定显示哪块就会漏掉另一块',
    );
  });

  test('负控：role 真的被用于分支时门禁会红', () {
    expect(usesRoleToChooseSection("if (role == 'host') { host(); }"), isTrue);
    expect(usesRoleToChooseSection('switch (data.role) { }'), isTrue);
    expect(
      usesRoleToChooseSection('role: CyNativeButtonRole.secondary'),
      isFalse,
    );
  });

  test('★★ 玩家名单不做前端脱敏', () {
    for (final String masking in <String>[
      '****',
      'substring(0, 3)',
      'maskPhone',
      'replaceRange',
    ]) {
      expect(
        players.contains(masking),
        isFalse,
        reason: '$masking = 把号码先发出去再假装没发',
      );
    }
    // 拿到就显示,没拿到就整行不显示(不放占位)。
    expect(players.contains('if (phone != null && phone.isNotEmpty)'), isTrue);
  });

  test('★★ contactHint 原样显示', () {
    expect(players.contains("d['contactHint']"), isTrue);
    // 自己写一句「暂无权限」的话,商家不知道该去找谁。
    expect(players.contains('暂无权限'), isFalse);
    expect(players.contains('无权查看'), isFalse);
  });

  test('★ 已退款是独立一态', () {
    expect(players.contains("case 'refunded':"), isTrue);
    expect(players.contains('已退款'), isTrue);
  });

  test('★ 名单页不做销量仪表盘 —— 后端明说「给名单不给统计分析」', () {
    // summary 只做一行小字。出现大号数字组件就跑偏了。
    expect(players.contains('headlineLarge'), isFalse);
    expect(players.contains('headlineMedium'), isFalse);
  });

  test('★ 招商进度用后端给的数,不自己算', () {
    expect(home.contains("recruit['nodeFilled']"), isTrue);
    expect(home.contains("recruit['pendingCount']"), isTrue);
    // pendingCount 同时含待审报名与待确认邀约,前端自己加会算错。
    expect(home.contains('nodeTotal - '), isFalse);
  });
}
