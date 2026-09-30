import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/city_resolve.dart';

void main() {
  CityResolveResult r(Map<String, dynamic> m) =>
      CityResolveResult.fromJson(m);

  group('★ 降级不是失败', () {
    test('限流 → 需要手填,且值得稍后再试', () {
      final x = r(<String, dynamic>{
        'city': '',
        'manualInputRequired': true,
        'reason': 'MAP_RATE_LIMITED',
      });
      expect(x.resolved, isFalse);
      expect(x.manualInputRequired, isTrue);
      expect(x.worthRetrying, isTrue, reason: '限流是暂时的');
      expect(x.hint, contains('稍后可再试'));
    });

    test('★ 服务不可用 → 需要手填,但不值得反复试', () {
      final x = r(<String, dynamic>{
        'city': '',
        'manualInputRequired': true,
        'reason': 'MAP_UNAVAILABLE',
      });
      expect(x.worthRetrying, isFalse,
          reason: '服务不可用时反复试没有意义,给重试是骗人');
      expect(x.hint, isNot(contains('稍后可再试')));
    });

    test('两种原因的说法必须不同', () {
      final a = r(<String, dynamic>{'reason': 'MAP_RATE_LIMITED'});
      final b = r(<String, dynamic>{'reason': 'MAP_UNAVAILABLE'});
      expect(a.hint, isNot(b.hint));
    });

    test('未知原因也给兜底说明,不留空', () {
      expect(r(<String, dynamic>{'manualInputRequired': true}).hint.trim(),
          isNotEmpty);
    });
  });

  group('★ resolved 以城市名为准', () {
    test('拿到城市 → resolved', () {
      expect(r(<String, dynamic>{'city': '上海'}).resolved, isTrue);
    });
    test('城市名是空白 → 不算拿到', () {
      expect(r(<String, dynamic>{'city': '   '}).resolved, isFalse);
    });
    test('后端只置了 manualInputRequired 但给了城市 → 仍以城市为准', () {
      final x = r(<String, dynamic>{'city': '上海', 'manualInputRequired': true});
      expect(x.resolved, isTrue,
          reason: '有城市名就是有,以更可靠的那个信号为准');
    });
    test('字段全缺 → 不算拿到,也不崩', () {
      expect(r(<String, dynamic>{}).resolved, isFalse);
    });
  });
}
