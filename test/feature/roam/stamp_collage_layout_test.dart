// 集邮册散落布局与小程序**逐位对齐**。
//
// ★ 这条测试的意义不是"布局函数没崩",而是**两端算出同一套位置**。
//   期望值不是我写的:是拿小程序自己的 layout.js 在 node 里真跑出来的 ——
//
//     node -e "const L=require('.../stamp-album/index/layout.js');
//              console.log(JSON.stringify(L.collageLayout(7,
//                {cols:4,cellW:90,cellH:112.5,jitter:16,maxRot:12})))"
//
//   若把 _rnd 换成 Random(seed) 之类"更正经"的写法,函数照样能跑、
//   册子照样很乱,但和小程序完全不是同一本册子 —— 只有这条能发现。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/roam/stamp_collage_layout.dart';

void main() {
  // 小程序 layout.js 在 node 里跑出来的真值(cols=4, cellW=90, cellH=112.5,
  // jitter=16, maxRot=12),七枚。
  const List<List<double>> expected = <List<double>>[
    <double>[-5.073338, -7.566323, -5.533556],
    <double>[93.841357, -6.817534, -1.922400],
    <double>[181.030322, -2.172283, -4.884683],
    <double>[269.275988, -2.636774, 9.679020],
    <double>[-3.641588, 119.552431, 2.826179],
    <double>[95.175179, 113.105749, 9.755257],
    <double>[184.045476, 113.600033, 4.514024],
  ];

  test('★ 与小程序 layout.js 逐位一致', () {
    final List<StampSlot> got = collageLayout(
      7,
      cols: 4,
      cellW: 90,
      cellH: 112.5,
    );
    expect(got.length, expected.length);
    for (int i = 0; i < expected.length; i++) {
      expect(got[i].x, closeTo(expected[i][0], 1e-5), reason: 'x #$i');
      expect(got[i].y, closeTo(expected[i][1], 1e-5), reason: 'y #$i');
      expect(got[i].rotDeg, closeTo(expected[i][2], 1e-5), reason: 'rot #$i');
      expect(got[i].z, i, reason: 'z 必须是入册顺序 —— 后来的压在上面');
    }
  });

  test('确定性:同一 index 每次都算出同一个位置', () {
    final a = collageLayout(20, cols: 4, cellW: 90, cellH: 112.5);
    final b = collageLayout(20, cols: 4, cellW: 90, cellH: 112.5);
    for (int i = 0; i < a.length; i++) {
      expect(a[i].x, b[i].x);
      expect(a[i].rotDeg, b[i].rotDeg);
    }
  });

  test('★ 续页只是变长,已渲染那些的位置不许变', () {
    // 加载下一页时若位置重算变了,已经看过的邮票会当场跳位置。
    final first = collageLayout(8, cols: 4, cellW: 90, cellH: 112.5);
    final second = collageLayout(16, cols: 4, cellW: 90, cellH: 112.5);
    for (int i = 0; i < first.length; i++) {
      expect(second[i].x, first[i].x, reason: '第 $i 枚在加载第二页后挪位了');
      expect(second[i].y, first[i].y);
    }
  });

  test('旋转角在 ±maxRot 内', () {
    for (final StampSlot s in collageLayout(64, cols: 4, cellW: 90, cellH: 112.5)) {
      expect(s.rotDeg.abs(), lessThanOrEqualTo(12));
    }
  });
}
