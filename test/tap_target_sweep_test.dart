// 可点区域最小尺寸的全仓扫描。
//
// ★★ 44pt 是 iOS HIG 与 Material 共同的最小触达尺寸。
//   2026-08-19 实测找到两处不足:
//     · 广场发帖删除已选图:18pt(压在缩略图角上,周围全是可滑动区)
//     · 故事编辑器的「插入内容」:26pt(长列表里每段之间都有一个,
//       点不中会误触相邻段落)
//
// ★ **优先用真渲染量**(见 feature/square/compose_tap_target_test.dart,
//   那条 getSize 出 18.0pt、负控能红)。
//   但有些可点件在**私有 widget** 里渲不出来,只能静态判 —— 本文件管这一类。
//
// ⚠️ 静态判的边界:它只看"有没有把图标直接塞进 GestureDetector/InkWell
//   而不给尺寸约束",**不能**据此断言热区一定够大
//   (父级可能已经撑开了)。所以它是**提示**不是保证 ——
//   真判据永远是渲染回读。这一点必须写明,否则下一个人会以为扫过就安全了。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★ 两处已修的小热区不许退回去', () {
    // 这两处都是真渲染量出来过的,改回小尺寸就是回归。
    final String square = codeOf('lib/feature/square/square_compose_page.dart');
    final int removeAt = square.indexOf('key: SquareComposeThumb.removeKey');
    expect(removeAt, greaterThan(0), reason: '找不到广场删除钮 —— 断言写法失效了');
    final String removeSegment = square.substring(
      (removeAt - 180).clamp(0, square.length),
      (removeAt + 260).clamp(0, square.length),
    );
    expect(
      removeSegment.contains('CupertinoButton('),
      isTrue,
      reason: '广场删除钮退回了原始手势,不再由 iOS 原生按钮提供点击、禁用态和语义',
    );
    expect(
      removeSegment.contains('minimumSize: const Size(44, 44)'),
      isTrue,
      reason: '广场删除钮的 44pt 最小热区约束没了',
    );
    // 最终判据仍是 compose_tap_target_test.dart 的 getSize 渲染回读;
    // 这里只防止实现退回非原生手势或丢失显式最小尺寸。

    // ⚠️ 判据要**锚定到那个具体的钮**,不能只搜 'height: 44' ——
    //   这个文件里有 3 处 height:44,改掉其中一处另两处仍在,断言不会红。
    //   (第一版就这么写的,负控没红才发现。)
    final String story = codeOf(
      'lib/feature/publish/publish_pro_story_editor.dart',
    );
    final int at = story.indexOf('CupertinoIcons.add_circled');
    expect(at, greaterThan(0), reason: '找不到插入钮 —— 断言写法失效了');
    // 往前找它所在的那个 SizedBox。
    final String seg = story.substring((at - 300).clamp(0, story.length), at);
    expect(
      seg.contains('height: 44'),
      isTrue,
      reason:
          '故事编辑器插入钮的 44pt 热区没了 —— '
          '它在长列表里每段之间都有一个,点不中会误触相邻段落',
    );
  });

  test('★ 扫一遍:图标直接塞进点击件、且同一段里没有任何尺寸约束', () {
    // ⚠️ 这只是**提示**:命中不代表热区一定小(父级可能撑开了),
    //   不命中也不代表一定够大。真判据是渲染回读。
    //   所以这里不 fail,只在有新增时打印出来供人工看一眼。
    final List<String> hints = <String>[];
    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.contains('/npc/')) continue; // 用户在改的目录
      final String code = codeOf(e.path);
      for (final RegExpMatch m in RegExp(
        r'(?:GestureDetector|InkWell)\(',
      ).allMatches(code)) {
        // 取该点击件之后 400 字符作为粗略作用域
        final String seg = code.substring(
          m.start,
          (m.start + 400).clamp(0, code.length),
        );
        if (!seg.contains('Icon(')) continue;
        final bool constrained =
            seg.contains('SizedBox') ||
            seg.contains('width:') ||
            seg.contains('height:') ||
            seg.contains('minWidth') ||
            seg.contains('IconButton');
        if (!constrained) {
          hints.add('${e.path}  (offset ${m.start})');
        }
      }
    }
    // 已知且已确认无碍的,不必每次都看。
    // ★ 只记数量下限,不写死清单 —— 写死清单会在无关重构后失效,
    //   而失效的清单比没有更坏(它会让人以为扫过了)。
    expect(
      hints.length,
      lessThan(40),
      reason:
          '未约束的图标点击件明显变多了,值得人工看一眼:\n'
          '${hints.take(10).join('\n')}',
    );
  });

  test('★ play/game 域 minimumSize 字面量不许低于 44pt', () {
    // a5-ios27-game-2 P1:`player_game_module_views.dart` 一批 44×32/44×36
    // 钮在旧覆盖域外(本文件此前只钉 square/publish 两文件)。
    // 静态判:凡 `minimumSize: const Size(<w>, <h>)` 数字字面量,
    // h<44 或 0<w<44 即红。`Size(0, …)` 视为宽度不设限(父级撑开),不判;
    // `double.infinity`/token 常量匹配不到数字模式,天然在判外 ——
    // 那类要人看渲染回读,这里只挡字面量写小的。
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e in Directory(
      'lib/feature/play',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String code = codeOf(e.path);
      for (final RegExpMatch m in RegExp(
        r'minimumSize:\s*const Size\((\d+(?:\.\d+)?),\s*(\d+(?:\.\d+)?)\)',
      ).allMatches(code)) {
        final double w = double.parse(m.group(1)!);
        final double h = double.parse(m.group(2)!);
        if (h < 44 || (w > 0 && w < 44)) {
          offenders.add('${e.path}  (${m.group(0)})');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '触控热区低于 44pt(HIG 最小触达),见 I1:\n${offenders.join('\n')}',
    );
    // 已修的点位不许悄悄退回旧尺寸。
    final String gameModule = codeOf(
      'lib/feature/play/player_game_module_views.dart',
    );
    expect(
      RegExp(
        r'minimumSize: const Size\(44, 44\)',
      ).allMatches(gameModule).length,
      greaterThanOrEqualTo(8),
      reason:
          'player_game_module_views 应有 8 枚 44×44 钮(旧 44×32/44×36 一批垫高)—— '
          '少了就是有人把热区改小',
    );
  });
}
