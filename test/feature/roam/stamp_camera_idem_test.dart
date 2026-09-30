// 集邮相机的幂等键契约(静态读码)。
//
// ★ 这里不能只测"createStamp 带了 idempotencyKey" —— API 层已经强制要求它了。
//   真正会出错的是**键的生命周期**:
//     · 键跟着**照片**走,不是跟着**这次点击**走;
//     · 存入失败后重试,必须还是**同一个键**(否则用户点两次 = 两枚);
//     · 「重拍」必须**换新键**(否则第二张照片会被当成第一张的重放,直接丢掉)。
//
//   这三条都是"跑起来看不出、上线才发现册子多了/少了一张"的错。
//   Widget 测试要跑真相机/真上传,所以这里读代码结构断言。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  final String src = File(
    'lib/feature/roam/stamp_camera_page.dart',
  ).readAsStringSync();

  // 剥注释后的代码。理由见 test/support/source_text.dart。
  final String code = codeOf('lib/feature/roam/stamp_camera_page.dart');

  /// 取某个方法体(从签名到配对的右花括号)。
  String bodyOf(String signature) {
    final int at = src.indexOf(signature);
    expect(at, greaterThan(0), reason: '找不到 $signature —— 断言写法失效了');
    final int open = src.indexOf('{', at);
    int depth = 1;
    int i = open + 1;
    while (i < src.length && depth > 0) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') depth--;
      i++;
    }
    return src.substring(open + 1, i - 1);
  }

  test('★ 拍到新照片时换新键', () {
    final String b = bodyOf(
      'Future<void> _takePhoto(StampCameraLayout layout, Size viewport)',
    );
    expect(
      b.contains('_newIdemKey()'),
      isTrue,
      reason: '换了照片不换键的话,第二张会被服务端当成第一张的重放而丢掉',
    );
    expect(b.contains('_shot = cropped'), isTrue);
  });

  test('★★ 存入失败后不清键 —— 重试必须还是同一枚', () {
    final String b = bodyOf('Future<void> _save()');
    // 失败分支里出现 _idemKey = 任何东西,都意味着重试会变成新的一枚。
    final int catchAt = b.indexOf('} on RoamApiException');
    expect(catchAt, greaterThan(0));
    final String failurePart = b.substring(catchAt);
    expect(
      failurePart.contains('_idemKey ='),
      isFalse,
      reason: '失败分支动了幂等键 —— 用户点第二次会真的入册第二枚',
    );
  });

  test('★ 存入用的是当前照片的键,不是当场生成的', () {
    final String b = bodyOf('Future<void> _save()');
    expect(
      b.contains('_newIdemKey()'),
      isFalse,
      reason: '_save 里生成键 = 每次点击一个新键 = 双击就是两枚',
    );
    expect(b.contains('idempotencyKey: key'), isTrue);
  });

  test('★ 重拍清空照片与键 —— 下一张是真的新一枚', () {
    final String retake = bodyOf('Future<void> _retake()');
    expect(retake.contains('await _discardShot()'), isTrue);
    final String b = bodyOf('Future<void> _discardShot()');
    expect(b.contains('_shot = null'), isTrue);
    expect(
      b.contains('_idemKey = null'),
      isTrue,
      reason: '重拍留着旧键的话,新照片会被当成旧照片的重放,静默丢弃',
    );
  });

  test('★ 重放命中时文案不能说「又收藏了一枚」', () {
    expect(code.contains('这张已经在册子里了'), isTrue);
    // 册子里并没有多一张,那么说的话用户回去数会对不上。
    expect(code.contains('又收藏了一枚'), isFalse);
  });

  test('★ 本地照片用 Image.file,不是 Image.network', () {
    // 拿 /var/... 本地路径喂 Image.network 会永远加载不出来,
    // 而 errorBuilder 给的灰底看起来像"这张照片有问题"。
    expect(code.contains('Image.file('), isTrue);
    expect(code.contains('Image.network(_shot'), isFalse);
  });
}
