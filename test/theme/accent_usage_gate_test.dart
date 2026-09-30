// 强调色只许做点缀,不许当一屏之主。
//
// ★ 起因(2026-08-18,App 第一次真正跑起来时才发现):
//   `map_page` 的高德授权门用了 `AppColors.nodeGlow`(#00E5D4 青)画一个 52pt 图标 ——
//   而那是 App 的**第一屏**(initialLocation = '/map'),那个图标是整屏最大的视觉元素。
//   城瘾是黑白系、品牌色就是文字色;`nodeGlow` 自己的定义里写着
//   「⚠️ 黑白系里彩色只做点缀,不要拿来做按钮底或主色」—— **注释禁止的事,代码在做。**
//
// ★ 为什么 153 个测试 + 几十张 golden 全都放过了:
//   golden 渲染的是**单个页面组件**,授权门与 tab 栏从没进过基线;
//   而对比度守卫管的是 token 之间的关系,管不到「某处用了不该用的 token」。
//   **这条只有把 App 真跑起来、看第一屏才会暴露。** 现在把它变成静态可查的。
//
// 判据:强调色允许出现在小尺寸装饰里,但不许出现在**大图标 / 按钮底 / 大字**上。
// 这里用一个保守而明确的代理判据:强调色不得与 `size:` ≥ 32 的 Icon 同处一个构造。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 只许做点缀的强调色。名字取自 AppColors。
const List<String> _accents = <String>['nodeGlow', 'accentViolet'];

/// 大图标的门槛(pt)。低于它算装饰,不管。
const int _bigIconPt = 32;

/// 返回 [(file, line, 片段)]。
List<List<String>> _scan() {
  final List<List<String>> hits = <List<String>>[];
  final RegExp iconRe = RegExp(r'Icon\(([^;]{0,400}?)\)', dotAll: true);
  final RegExp sizeRe = RegExp(r'size:\s*(\d+)');

  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    // 主题/调色板文件本身当然会提到这些名字,那是**定义**不是**使用**。
    if (e.path.contains('/theme/')) continue;
    final String src = e.readAsStringSync();

    for (final RegExpMatch m in iconRe.allMatches(src)) {
      final String body = m.group(1) ?? '';
      final RegExpMatch? sz = sizeRe.firstMatch(body);
      if (sz == null) continue;
      final int pt = int.parse(sz.group(1)!);
      if (pt < _bigIconPt) continue;
      for (final String accent in _accents) {
        if (body.contains(accent)) {
          final int line =
              '\n'.allMatches(src.substring(0, m.start)).length + 1;
          hits.add(<String>[e.path, '$line', '${pt}pt 图标用了 $accent']);
        }
      }
    }
  }
  return hits;
}

void main() {
  test('强调色不许用在 ≥${_bigIconPt}pt 的图标上', () {
    final List<List<String>> hits = _scan();
    expect(
      hits,
      isEmpty,
      reason: '强调色只许做点缀,这些地方把它当成了一屏之主:\n'
          '${hits.map((h) => '  ${h[0]}:${h[1]}  ${h[2]}').join('\n')}\n'
          '城瘾是黑白系,品牌色就是文字色 —— 大图标请用 textPrimary / textSecondary。',
    );
  });

  test('自检:构造出来的违规必须被抓到,合法用法不许误伤', () {
    // 这条是闸的负控。判据一旦被改松(比如门槛调到 999),它会先红。
    const String bad = "Icon(Icons.map_outlined, size: 52, color: AppColors.nodeGlow)";
    const String smallOk = "Icon(Icons.star, size: 14, color: AppColors.nodeGlow)";
    const String bigOk = "Icon(Icons.map_outlined, size: 52, color: CyTokens.textSecondary)";

    final RegExp iconRe = RegExp(r'Icon\(([^;]{0,400}?)\)', dotAll: true);
    final RegExp sizeRe = RegExp(r'size:\s*(\d+)');
    bool violates(String code) {
      for (final RegExpMatch m in iconRe.allMatches(code)) {
        final String body = m.group(1) ?? '';
        final RegExpMatch? sz = sizeRe.firstMatch(body);
        if (sz == null) continue;
        if (int.parse(sz.group(1)!) < _bigIconPt) continue;
        if (_accents.any(body.contains)) return true;
      }
      return false;
    }

    expect(violates(bad), isTrue, reason: '52pt + nodeGlow 没被抓到');
    expect(violates(smallOk), isFalse, reason: '14pt 的点缀被误伤了');
    expect(violates(bigOk), isFalse, reason: '大图标用 token 色被误判为违规');
  });
}
