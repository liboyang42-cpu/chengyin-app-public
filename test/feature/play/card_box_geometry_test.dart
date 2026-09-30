import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/play/free_explore/card_box_geometry.dart';

void main() {
  test('松手吸附到最近的正/背面', () {
    expect(snapRy(0), 0);
    expect(snapRy(40), 0);
    expect(snapRy(95), 180);
    expect(snapRy(179), 180);
    expect(snapRy(200), 180);
    expect(snapRy(-95), -180);
  });

  test('★正背面切换:超过 90° 才该画背面', () {
    expect(showsBack(0), isFalse);
    expect(showsBack(89), isFalse);
    expect(showsBack(91), isTrue);
    expect(showsBack(180), isTrue);
    expect(showsBack(269), isTrue);
    expect(showsBack(271), isFalse, reason: '转过一圈回到正面这一侧');
    expect(showsBack(-91), isTrue, reason: '反向转同样要换面');
  });

  test('showsBack 临界点:90/270/-90 都不算背面(> 才算,不含等于)', () {
    expect(showsBack(90), isFalse);
    expect(showsBack(270), isFalse);
    expect(showsBack(-90), isFalse);
  });

  test('snapRy 等距平局:90 与 -90 离两面正好一样近', () {
    // (ry/180).round() 在 0.5 上按 Dart 的「四舍五入远离零」取整——
    // 90/180=0.5→1→180,-90/180=-0.5→-1→-180。等距平局往哪边归都不算错,
    // 这里钉住当前行为防回归。
    expect(snapRy(90), 180);
    expect(snapRy(-90), -180);
  });

  test('edgeOn:只看得见厚度的角度(照搬小程序 turnedAt:8°..172°)', () {
    expect(edgeOn(0), isFalse);
    expect(edgeOn(8), isFalse);
    expect(edgeOn(9), isTrue);
    expect(edgeOn(90), isTrue);
    expect(edgeOn(171), isTrue);
    expect(edgeOn(173), isFalse);
    expect(edgeOn(180), isFalse);
    expect(edgeOn(-90), isTrue, reason: '负角度要先归一化');
  });

  test('拖动累加:横向位移 × 0.8', () {
    expect(dragRy(0, 100), closeTo(80, 0.001));
    expect(dragRy(30, -50), closeTo(-10, 0.001));
  });
}
