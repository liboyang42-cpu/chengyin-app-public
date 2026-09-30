// M9 门禁:Flutter 侧不许用 `BackdropFilter` / `ImageFilter.blur` 仿制 Liquid Glass。
//
// ★ 为什么需要:仿出来的玻璃**永远不像**(没有折射、没有 iOS 27 的光照调校),
//   而且 iOS 26+ 上会和真玻璃(Tab Bar / sheet / 原生桥)并排出现 —— 一眼假。
//   手册 M9 因此全面禁止,材质一律走原生桥回退或 Cupertino 自身。
//
// ★ 内容层的**模糊**不在此列:封面图虚化、故事文字入场这类是「内容滤镜」
//   (等价 CSS filter: blur),不是功能层材质。允许清单逐条写明理由;
//   清单是双向的 —— 登记项消失了也红,逼着人回来清理。
//
// ★ 负控:合成一段含两类调用的假源码,扫描器必须都报出来。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 允许 `ImageFilter.blur(` 的**内容层**文件 → 理由。
const Map<String, String> kContentBlurAllowlist = <String, String>{
  'lib/feature/profile/profile_page.dart': '主页封面图铺底虚化(照片 + 渐变压暗),内容层滤镜不是功能层玻璃',
  'lib/feature/play/free_explore/widgets/story_line_view.dart':
      '故事行入场过渡的模糊(等价 CSS filter: blur),逐帧动画内容',
};

final RegExp _backdrop = RegExp(r'BackdropFilter\s*\(');
final RegExp _imageBlur = RegExp(r'ImageFilter\.blur\s*\(');

String? stripWholeLineComment(String line) {
  final String trimmed = line.trimLeft();
  if (trimmed.startsWith('//')) return null;
  return line;
}

List<String> scan(String path, String source) {
  final List<String> hits = <String>[];
  final List<String> lines = source.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final String? code = stripWholeLineComment(lines[i]);
    if (code == null) continue;
    if (_backdrop.hasMatch(code)) {
      hits.add('$path:${i + 1} BackdropFilter —— M9 禁仿玻璃,改原生桥/Cupertino');
    }
    if (_imageBlur.hasMatch(code) && !kContentBlurAllowlist.containsKey(path)) {
      hits.add('$path:${i + 1} ImageFilter.blur —— 不在内容层允许清单里');
    }
  }
  return hits;
}

void main() {
  test('★ lib/ 里不许出现 BackdropFilter,ImageFilter.blur 只许内容层白名单', () {
    final Directory lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '找不到 lib/,扫描退化为空会把「查不了」伪装成通过');

    final List<String> offenders = <String>[];
    final Map<String, int> allowlistHits = <String, int>{
      for (final String path in kContentBlurAllowlist.keys) path: 0,
    };
    int scanned = 0;

    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      scanned++;
      final String path = entity.path;
      final String source = entity.readAsStringSync();
      offenders.addAll(scan(path, source));
      if (allowlistHits.containsKey(path)) {
        allowlistHits[path] = _imageBlur.allMatches(source).length;
      }
    }

    expect(
      scanned,
      greaterThan(300),
      reason: '只扫到 $scanned 个文件,目录结构变了就把这条闸修好,别静默失效',
    );
    expect(offenders, isEmpty, reason: '仿玻璃调用:\n${offenders.join('\n')}');

    for (final MapEntry<String, int> entry in allowlistHits.entries) {
      expect(
        entry.value,
        greaterThan(0),
        reason:
            '${entry.key} 已不再有 ImageFilter.blur —— 从允许清单里删掉它,'
            '否则清单会变成过期的免死金牌',
      );
    }
  });

  test('负控:BackdropFilter 与清单外的 ImageFilter.blur 都必须被抓到', () {
    const String mutation = '''
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      ),
''';
    final List<String> hits = scan('lib/feature/example/page.dart', mutation);
    expect(hits.length, 2, reason: '扫描器失效:两类调用都要报');
  });

  test('整行注释不算违规(解释规则时提到名字是正常的)', () {
    expect(scan('lib/a.dart', '// 别用 BackdropFilter 仿玻璃'), isEmpty);
  });
}
