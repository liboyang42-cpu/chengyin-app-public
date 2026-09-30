import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/completed_play.dart';

void main() {
  CompletedPlay c(Map<String, dynamic> m) =>
      CompletedPlay.fromJson(<String, dynamic>{'name': 'X', ...m});

  group('★ 落点:拿不到可用 id 就不给跳', () {
    test('有 activityId → 走活动详情', () {
      expect(c(<String, dynamic>{'activityId': 9}).route, '/activity/9');
    });
    test('只有 topicId → 走主题详情(自由探索没有 activityId)', () {
      expect(c(<String, dynamic>{'topicId': 5}).route, '/topic/5');
    });
    test('activityId 优先于 topicId', () {
      expect(
        c(<String, dynamic>{'activityId': 9, 'topicId': 5}).route,
        '/activity/9',
      );
    });
    test('★ 两个都没有 → null,调用方不给跳转', () {
      expect(
        c(<String, dynamic>{}).route,
        isNull,
        reason: '跳到 /activity/0 会进一个永远加载失败的页面',
      );
    });
    test('★ id 是 0 也当没有', () {
      expect(c(<String, dynamic>{'activityId': 0, 'topicId': 0}).route, isNull);
    });
    test('activityId 为 0 时回退到 topicId', () {
      expect(
        c(<String, dynamic>{'activityId': 0, 'topicId': 5}).route,
        '/topic/5',
      );
    });
  });

  group('★ 进度:total 为 0 不显示', () {
    test('没有节点数 → null', () {
      expect(
        c(<String, dynamic>{}).progressText,
        isNull,
        reason: '「0/0」既没信息,又让人以为这局是空的',
      );
      expect(
        c(<String, dynamic>{'total': 0, 'doneCount': 0}).progressText,
        isNull,
      );
    });
  });

  group('★ 进度三档必须说法不同 —— 原来三档渲出来一模一样', () {
    // 2026-08-19 拍 my_plays 基准图时发现:6/6、3/8、0/5 三条长得完全一样,
    // 状态全靠用户心算;而这页叫「我走过的」,里面却混着一条一个点都没走的。
    // `completed` 字段一直解析着但没人消费 —— 后端说了完没完,界面看不出来。
    test('走完 → 说「已走完」,不再是一个分数', () {
      expect(
        c(<String, dynamic>{
          'total': 6,
          'doneCount': 6,
          'completed': true,
        }).progressText,
        '已走完 · 6 个点',
      );
    });

    test('★ doneCount 够了但后端没标 completed,也算走完', () {
      // 两个来源都可能是权威的,取「或」而不是只信一个 ——
      // 只信 completed 会把已走满却漏标的显示成「还差 0 个点」。
      expect(
        c(<String, dynamic>{'total': 6, 'doneCount': 6}).progressText,
        '已走完 · 6 个点',
      );
    });

    test('走了一半 → 说还差几个(比说已走几个更贴近下一步)', () {
      expect(
        c(<String, dynamic>{'total': 8, 'doneCount': 3}).progressText,
        '还差 5 个点 · 已走 3',
      );
    });

    test('★ 一个点都没走 → 「还没开始」,不是「0 / 5 个点」', () {
      expect(
        c(<String, dynamic>{'total': 5, 'doneCount': 0}).progressText,
        '还没开始 · 共 5 个点',
      );
    });

    test('三档两两不同 —— 防止以后被改回同一个模板', () {
      final Set<String> all = <String>{
        c(<String, dynamic>{'total': 6, 'doneCount': 6}).progressText!,
        c(<String, dynamic>{'total': 6, 'doneCount': 3}).progressText!,
        c(<String, dynamic>{'total': 6, 'doneCount': 0}).progressText!,
      };
      expect(all.length, 3, reason: '三档说法撞了:$all');
    });
  });

  test('名字兜底', () {
    expect(CompletedPlay.fromJson(<String, dynamic>{'name': '  '}).name, '未命名');
  });
}
