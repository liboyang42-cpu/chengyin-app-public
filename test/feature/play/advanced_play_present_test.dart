// 会话视图根层 `present` 的解析(契约 §1.5,真源 `playkit-view.js#presentOf`)。
// a4-playkit-storyflow 的最小消费面:故事流内嵌段只认这里读出来的值;
// present 的统一解析层在 a4-playkit-present 线上,合流时以那边为准。
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Object? present}) => <String, dynamic>{
  'sessionId': 7,
  'activityId': 3,
  'topicId': 0,
  'nodeId': 11,
  'status': 'RUNNING',
  'version': 1,
  'playKit': <String, Object?>{},
  if (present != null) 'present': present,
};

void main() {
  test('只认 inline;缺失 / 别的值 / 非字符串一律 fullscreen', () {
    expect(AdvancedPlayState.fromJson(_json(present: 'inline')).present, 'inline');
    expect(AdvancedPlayState.fromJson(_json(present: 'inline')).isInlinePresent, isTrue);
    expect(_json().containsKey('present'), isFalse);
    for (final Object? value in <Object?>['fullscreen', 'INLINE', true, 1, '']) {
      final AdvancedPlayState state = AdvancedPlayState.fromJson(
        _json(present: value),
      );
      expect(state.present, 'fullscreen', reason: '$value 不许翻成 inline');
      expect(state.isInlinePresent, isFalse);
    }
  });
}
