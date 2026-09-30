// 界面文案里不许出现开发者黑话。
//
// ★ 为什么值得一道闸:这类字符串**在本机永远不会出现**(key 注好了、后端通着),
//   只有真机、审核员、或配置缺失时才浮出来 —— 而那正是最不该出问题的时刻。
//   本轮实测抓到 9 条,最狠的两条是:
//     · 「高德地图 Key 未配置,请使用 --dart-define 注入」 ← App 的**第一屏**
//       (initialLocation = '/map'),等于把构建命令写给审核员看
//     · 「微信登录暂未开放(开放平台移动应用 appid 未配置)」← 把内部配置状态摊开
//   其余 7 条是「…拉取失败(后端未连接或未登录)」——「后端」对用户是无意义的词,
//   读起来就是「这 App 坏了」。
//
// 开发者需要的定位信息不是不能有,而是**不该走 UI**:走 assert + debugPrint,
// release 构建会整体剥掉。
//
// 判据只看**字符串字面量**,不看注释 —— 注释里写 --dart-define 是正常的。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 绝不该出现在用户可见文案里的词。
const Map<String, String> _banned = <String, String>{
  'dart-define': '构建命令,用户看不懂也用不上',
  'localhost': '本机地址泄漏',
  '127.0.0.1': '本机地址泄漏',
  '后端': '内部构件名;用户不知道什么是后端',
  'appid': '内部配置项',
  'TODO': '未完成标记不该出现在界面上',
  'FIXME': '同上',
};

/// 允许豁免的文件(不含用户可见 UI 文案的)。
const List<String> _skipPaths = <String>['lib/core/config/env.dart'];

/// 取出一行里的字符串字面量;整行是注释的直接跳过。
Iterable<String> _literals(String line) sync* {
  final String t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) return;
  for (final RegExpMatch m in RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(line)) {
    yield m.group(1) ?? '';
  }
}

void main() {
  test('lib/ 的界面文案里没有开发者黑话', () {
    final List<String> hits = <String>[];

    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (_skipPaths.any((String s) => e.path.endsWith(s.substring(4)))) continue;

      final List<String> lines = e.readAsLinesSync();
      // debugPrint(...) 里的字符串是**给开发者的**,而且都包在 assert 里、
      // release 构建会剥掉 —— 那正是本闸推荐的做法,不能反过来判它违规。
      // 语句可能跨多行,所以从 `debugPrint(` 起一直跳到该语句的 `);`。
      bool inDevPrint = false;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('debugPrint(')) inDevPrint = true;
        final bool skipThisLine = inDevPrint;
        if (inDevPrint && lines[i].contains(');')) inDevPrint = false;
        if (skipThisLine) continue;
        for (final String lit in _literals(lines[i])) {
          // 只查「像给人看的话」的字面量:含中文,或明显是句子。
          final bool userFacing =
              RegExp(r'[一-龥]').hasMatch(lit) || lit.contains(' ');
          if (!userFacing) continue;
          _banned.forEach((String bad, String why) {
            // 词边界匹配:`avg.toDouble()` 小写后含子串 `todo`,但不是未完成标记。
            // 前后邻字母判为词内子串,放行;`TODO: xxx` 这类独立词照常抓。
            final RegExp re = RegExp(
              '(?<![A-Za-z])${RegExp.escape(bad)}(?![A-Za-z])',
              caseSensitive: false,
            );
            if (re.hasMatch(lit)) {
              hits.add('${e.path}:${i + 1}  「$lit」 ← $bad($why)');
            }
          });
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason: '这些文案会出现在用户/审核员眼前:\n${hits.join('\n')}\n'
          '开发者需要的信息请走 assert + debugPrint(release 会剥掉)',
    );
  });
}
