import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/play_ending.dart';

void main() {
  group('★ 空结局不是错误', () {
    test('一个节点都没走完 → opener 空串 + 无碎片', () {
      final e = PlayEnding.fromJson(<String, dynamic>{
        'opener': '',
        'fragments': <dynamic>[],
      });
      expect(e.hasStory, isFalse, reason: '这是「还没有故事」,界面该说这个,不是「加载失败」');
      expect(e.opener, '');
    });
    test('字段整个缺失也不抛', () {
      final e = PlayEnding.fromJson(<String, dynamic>{});
      expect(e.hasStory, isFalse);
      expect(e.fragments, isEmpty);
    });
  });

  group('碎片', () {
    EndingFragment f(Map<String, dynamic> m) => EndingFragment.fromJson(
      <String, dynamic>{'step': 1, 'name': 'N', ...m},
    );

    test('★ 正文为空 → 只保留标题,不渲染空段落', () {
      expect(f(<String, dynamic>{}).body, isNull);
      expect(f(<String, dynamic>{'text': '   '}).body, isNull);
    });
    test('有正文 → 裁掉两端空白', () {
      expect(f(<String, dynamic>{'text': '  夜色刚起。 '}).body, '夜色刚起。');
    });
    test('地点名兜底', () {
      expect(
        EndingFragment.fromJson(<String, dynamic>{'step': 1, 'name': ''}).name,
        '未命名地点',
      );
    });
    test('按完成顺序保序', () {
      final e = PlayEnding.fromJson(<String, dynamic>{
        'fragments': <dynamic>[
          <String, dynamic>{'step': 1, 'name': 'A'},
          <String, dynamic>{'step': 2, 'name': 'B'},
          <String, dynamic>{'step': 3, 'name': 'C'},
        ],
      });
      expect(e.fragments.map((EndingFragment x) => x.name).toList(), <String>[
        'A',
        'B',
        'C',
      ]);
      expect(e.hasStory, isTrue);
    });
  });
}
