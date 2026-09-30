// AI 起草的解析与校验。三条纪律逐条锁住。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/publish/ai_draft_logic.dart';

Map<String, dynamic> _resp({
  String title = '静安夜行',
  List<Map<String, dynamic>>? nodes,
  Object? traceId,
  Object? remaining,
}) =>
    <String, dynamic>{
      'draft': <String, dynamic>{
        'title': title,
        'subtitle': '两小时',
        'storyline': '从咖啡馆出发',
        'nodes': nodes ??
            <Map<String, dynamic>>[
              <String, dynamic>{'merchantName': '静安咖啡', 'task': '点一杯'},
            ],
      },
      if (traceId != null) 'traceId': traceId,
      if (remaining != null) 'remainingQuota': remaining,
    };

void main() {
  test('正常草稿解析出标题与点位', () {
    final AiDraft d = parseAiDraft(_resp(traceId: 't-1', remaining: 4));
    expect(d.title, '静安夜行');
    expect(d.nodes.single.name, '静安咖啡');
    expect(d.nodes.single.description, '点一杯');
    expect(d.traceId, 't-1');
    expect(d.remainingQuota, 4);
  });

  test('★ 名字三选一的兜底顺序:merchantName → roleText → task', () {
    expect(
        parseAiDraft(_resp(nodes: <Map<String, dynamic>>[
          <String, dynamic>{'roleText': '老板娘', 'task': '聊两句'}
        ])).nodes.single.name,
        '老板娘');
    expect(
        parseAiDraft(_resp(nodes: <Map<String, dynamic>>[
          <String, dynamic>{'task': '拍张照'}
        ])).nodes.single.name,
        '拍张照');
  });

  group('★★ 不完整就整份丢掉 —— 半份草稿比没有更坏', () {
    test('没有标题', () {
      expect(() => parseAiDraft(_resp(title: '  ')), throwsA(isA<AiDraftError>()));
    });
    test('一个点位都没有', () {
      expect(() => parseAiDraft(_resp(nodes: <Map<String, dynamic>>[])),
          throwsA(isA<AiDraftError>()));
    });
    test('任一点位三个名字字段全空', () {
      expect(
          () => parseAiDraft(_resp(nodes: <Map<String, dynamic>>[
                <String, dynamic>{'merchantName': '静安咖啡'},
                <String, dynamic>{'task': '   '},
              ])),
          throwsA(isA<AiDraftError>()));
    });
    test('★ 后端有话就用后端的 —— 它知道是内容安全还是模型没返好', () {
      expect(
          () => parseAiDraft(_resp(title: ''), serverMsg: '内容涉及敏感词'),
          throwsA(predicate((Object e) => e.toString().contains('内容涉及敏感词'))));
    });
  });

  test('★★ 超过 3 个点位整份作废,不截断前 3 个', () {
    // 截断会把 AI 的路线逻辑拦腰砍断,用户拿到一条走不通的路。
    final Map<String, dynamic> r = _resp(nodes: <Map<String, dynamic>>[
      for (int i = 0; i < 4; i++) <String, dynamic>{'task': '点位 $i'},
    ]);
    expect(() => parseAiDraft(r),
        throwsA(predicate((Object e) => e.toString().contains('不超过 3 个点位'))));
  });

  test('remainingQuota 没给时是 null —— 沿用原值,别清零', () {
    expect(parseAiDraft(_resp()).remainingQuota, isNull);
  });

  group('★★ 确认 = 有坐标,不是点过按钮', () {
    test('没坐标不算确认', () {
      expect(const ConfirmedNode(name: 'a', description: '').confirmed, isFalse);
      expect(
          const ConfirmedNode(name: 'a', description: '', longitude: '121.4')
              .confirmed,
          isFalse,
          reason: '只有经度不算');
    });
    test('两个坐标齐了才算', () {
      expect(
          const ConfirmedNode(
                  name: 'a', description: '', longitude: '121.4', latitude: '31.2')
              .confirmed,
          isTrue);
    });
  });

  group('进编辑器要三条都满足', () {
    const ConfirmedNode ok = ConfirmedNode(
        name: 'a', description: '', longitude: '121.4', latitude: '31.2');
    const ConfirmedNode bad = ConfirmedNode(name: 'b', description: '');

    test('全齐 → 可以', () {
      expect(canEnterAiEditor(title: '静安夜行', nodes: <ConfirmedNode>[ok]), isTrue);
    });
    test('标题空 → 不行', () {
      expect(canEnterAiEditor(title: ' ', nodes: <ConfirmedNode>[ok]), isFalse);
    });
    test('没点位 → 不行', () {
      expect(canEnterAiEditor(title: 'x', nodes: const <ConfirmedNode>[]), isFalse);
    });
    test('★ 有一个点位没确认坐标 → 不行(发出去在地图上落不了地)', () {
      expect(canEnterAiEditor(title: 'x', nodes: <ConfirmedNode>[ok, bad]), isFalse);
    });
  });
}
