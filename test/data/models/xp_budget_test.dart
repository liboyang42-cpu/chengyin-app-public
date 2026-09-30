// 主题 XP 预算(发布前的 budget-bar)。
//
// ★ App 此前**完全没接这条** —— 创作者在发布页看不到自己分配了多少 XP、
//   还剩多少、有没有超。超了只能等**提交之后**被后端拒,
//   而那时整个表单已经填完了。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/xp_budget.dart';

XpBudget _b(Map<String, dynamic> j) => XpBudget.fromJson(j);

void main() {
  test('契约字段逐个解析', () {
    final XpBudget b = _b(<String, dynamic>{
      'budget': 1000,
      'totalXp': 700,
      'over': false,
      'overBy': 0,
      'remain': 300,
      'perNode': <dynamic>[
        <String, dynamic>{'nodeId': 1, 'name': '静安寺', 'xp': 400},
        <String, dynamic>{'nodeId': 2, 'name': '南京西路', 'xp': 300},
      ],
    });
    expect(b.budget, 1000);
    expect(b.totalXp, 700);
    expect(b.remain, 300);
    expect(b.perNode.length, 2);
    expect(b.perNode.first.label, '静安寺');
  });

  test('★ 是否超预算以后端的 over 为准,不前端比大小', () {
    // 边界(相等算不算超)和将来可能的豁免规则都在服务端。
    // 前端自己算一遍,就多了一个会漂移的判据。
    final XpBudget equal = _b(<String, dynamic>{
      'budget': 1000,
      'totalXp': 1000,
      'over': false, // 服务端说相等不算超
    });
    expect(equal.over, isFalse,
        reason: '前端若写 totalXp >= budget 就会和服务端唱反调');

    final XpBudget exempt = _b(<String, dynamic>{
      'budget': 1000,
      'totalXp': 1200,
      'over': false, // 假设服务端有豁免
    });
    expect(exempt.over, isFalse);
  });

  test('超了要能拿到超出多少', () {
    final XpBudget b = _b(<String, dynamic>{
      'budget': 1000,
      'totalXp': 1300,
      'over': true,
      'overBy': 300,
    });
    expect(b.over, isTrue);
    expect(b.overBy, 300);
  });

  test('★ budget 为 0 时 usedRatio 是 null,不是 0', () {
    // 「没有预算」和「预算用了 0%」是两回事 —— 前者根本不该画进度条。
    expect(_b(<String, dynamic>{'budget': 0, 'totalXp': 0}).usedRatio, isNull);
    expect(_b(<String, dynamic>{'budget': 100, 'totalXp': 0}).usedRatio, 0.0);
  });

  test('节点名拿不到时用 #id,不渲空行', () {
    final XpBudget b = _b(<String, dynamic>{
      'perNode': <dynamic>[
        <String, dynamic>{'nodeId': 7, 'xp': 100},
        <String, dynamic>{'nodeId': 8, 'name': '   ', 'xp': 50},
      ],
    });
    expect(b.perNode[0].label, '#7');
    expect(b.perNode[1].label, '#8');
  });
}
