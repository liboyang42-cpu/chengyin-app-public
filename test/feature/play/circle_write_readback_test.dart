import 'package:chengyin_app/feature/play/circle_write_readback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('记录写入只以服务端卡片中的同 offerId 解除未知态', () {
    const Map<String, dynamic> pending = <String, dynamic>{
      'kind': 'record',
      'offerId': 23,
    };
    expect(
      circleWriteLanded(<String, dynamic>{
        'records': <Map<String, dynamic>>[
          <String, dynamic>{'offerId': 23},
        ],
      }, pending),
      isTrue,
    );
    expect(
      circleWriteLanded(<String, dynamic>{
        'records': <Map<String, dynamic>>[
          <String, dynamic>{'offerId': 24},
        ],
      }, pending),
      isFalse,
    );
  });

  test('回答写入必须同时匹配 stage 和去首尾空格后的 value', () {
    const Map<String, dynamic> pending = <String, dynamic>{
      'kind': 'answer',
      'stage': 'PRE_WISH',
      'value': '  A  ',
    };
    expect(
      circleWriteLanded(<String, dynamic>{
        'answers': <Map<String, dynamic>>[
          <String, dynamic>{'answerStage': 'PRE_WISH', 'answerValue': 'A'},
        ],
      }, pending),
      isTrue,
    );
    expect(
      circleWriteLanded(<String, dynamic>{
        'answers': <Map<String, dynamic>>[
          <String, dynamic>{'answerStage': 'NEXT_PICK', 'answerValue': 'A'},
        ],
      }, pending),
      isFalse,
    );
  });
}
