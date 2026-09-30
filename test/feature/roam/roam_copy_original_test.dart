// 文案批(roam 域):这次动过的原句必须逐字留在源码里 —— 改字(含半/全角逗号)就红。
//
// 为什么单开一个文件:这三条缺口里有两条是**widget 测试跑不到的态** ——
// citystamp 的空态副标与读屏文案要真投一张票才出现,stamp-album 的续页
// 「正在读取下一页」要滚到第二页;citynode-code 的缺参态要真的少带一个参数。
// 造这些态要挂网络/路由,不假造 —— 按仓内既有 gate 的做法直接钉源码字面量。
//
// 真源:/tmp/be-master(chengyinhub-xcx)· 逐条出处见下方。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 页 → (App 文件, 该页必须逐字出现的原句)。
const Map<String, String> _kAppFile = <String, String>{
  'subpackageRoam/citystamp/index': 'lib/feature/roam/city_stamp_page.dart',
  'subpackageP3/pages/stamp-album/index/index':
      'lib/feature/roam/stamp_album_page.dart',
  'subpackageRoam/citynode-code/index':
      'lib/feature/roam/city_node_voucher_page.dart',
};

const Map<String, List<String>> _kOriginal = <String, List<String>>{
  // subpackageRoam/citystamp/index.wxml:空态副标、输入框 placeholder 与
  // aria-label、以及「收下,出发」…… 四个字里那个逗号原文是全角。
  'subpackageRoam/citystamp/index': <String>[
    '你留的那句已经投进去了，等下一个人来换。',
    '比如：巷口那家豆浆七点才开，别去早了',
    '留一句给下一个人',
    '收下，出发',
    '（这一位没留字，只留了一张照片）',
  ],
  // subpackageP3/pages/stamp-album/index/index.wxml:空态 sub、续页加载行、
  // 续页重试行的 aria-label(空态副标与续页行是这次改的,重试行只补读屏)。
  'subpackageP3/pages/stamp-album/index/index': <String>[
    '上街拍一张，城市就进你的册子了',
    '正在读取下一页',
    '重试加载这一页',
  ],
  // subpackageRoam/citynode-code/index.wxml:缺参态 sub 与核销卡 desc ——
  // 这两句原文逗号都是**半角**,别好心改成全角(改了就与小程序对不上,对账会红)。
  'subpackageRoam/citynode-code/index': <String>[
    '链接缺少据点参数,请回据点页重新进入',
    '出示给商家扫码,即可领取优惠券',
  ],
};

void main() {
  test('★ roam 域:文案批动过的原句逐字留在源码里', () {
    for (final MapEntry<String, List<String>> entry in _kOriginal.entries) {
      final String src = File(_kAppFile[entry.key]!).readAsStringSync();
      for (final String line in entry.value) {
        expect(
          src.contains(line),
          isTrue,
          reason: '${entry.key} 缺了小程序原句「$line」',
        );
      }
    }
  });
}
