import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 开发者家目录绝对路径,例:`/Users/<用户名>/...`。
///
/// 两台机器的家目录不同(执行机 fanning / 主控机 arlan),写死任何一个都会让门禁
/// 只在作者那台机器上跑得通 —— 而它通常表现为「本机绿、别人红」或者更坏的
/// 「被 needs-local-env 排除掉,谁都没跑」。这里扫全仓,不逐个文件点名。
final RegExp _developerHome = RegExp(r'/Users/[A-Za-z0-9._-]+/');

/// 有意保留的历史路径引用:**当前为空**。要加白名单,必须写明理由(哪条路径、
/// 为什么删不掉),不要放宽成「跳过整类文件」—— 那等于把门禁关掉。
const Map<String, String> _allowedHistoricalPaths = <String, String>{};

void main() {
  test('test/tool/lib 里不许出现开发者绝对路径', () {
    final List<String> offenders = <String>[];
    for (final String root in <String>['test', 'tool', 'lib']) {
      for (final FileSystemEntity entity in Directory(
        root,
      ).listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!<String>['.dart', '.py', '.sh'].any(entity.path.endsWith)) {
          continue;
        }
        final List<String> lines = entity.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final RegExpMatch? hit = _developerHome.firstMatch(lines[i]);
          if (hit == null) continue;
          if (_allowedHistoricalPaths.containsKey(hit.group(0))) continue;
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '这些文件绑定了开发者的家目录,换台机器就跑不了(修法:用 env 或 '
          'test/support/backend_repo.dart 的候选解析):\n${offenders.join('\n')}',
    );
  });
}
