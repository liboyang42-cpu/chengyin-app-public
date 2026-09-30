// sheet 里包了 `UnsavedGuard` ⇒ 这个 sheet **必须** `enableDrag: false`。
//
// ★ 为什么得这么管:`CupertinoSheetRoute` 的下滑关闭走的是
//   `navigator.pop()`(强制 pop,不看 `popDisposition`),
//   `PopScope` 拦不住;而内容自带滚动条时拖动还会先被内层 `Scrollable`
//   吃掉 —— 页面侧没有可靠的拦截点(两条路径都实测过)。
//   于是「脏了也不静默丢数据」的唯一可靠口径就是:**别让这个 sheet 能拖**。
//
// ⚠️ 这条不是判「现在有没有违规」(现在两处 UnsavedGuard 都在普通路由页上),
//   是判「以后也别配出『守卫 + 可拖动』这个组合」—— 那种组合的失败方式是
//   静默丢数据,没有报错、没有日志,靠人眼评审很容易放过。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 返回违规描述。抽成纯函数是为了给负控用(见本文件末尾两条用例)。
List<String> unsavedGuardSheetViolations(String fileName, String source) {
  final List<String> violations = <String>[];
  const String needle = 'showCupertinoSheet';
  int index = source.indexOf(needle);
  while (index >= 0) {
    final int open = source.indexOf('(', index + needle.length);
    if (open < 0) break;
    int depth = 0;
    int end = open;
    for (int i = open; i < source.length; i++) {
      final String ch = source[i];
      if (ch == '(') depth += 1;
      if (ch == ')') {
        depth -= 1;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    final String call = source.substring(index, end + 1);
    if (call.contains('UnsavedGuard') && !call.contains('enableDrag: false')) {
      final int line = '\n'.allMatches(source.substring(0, index)).length + 1;
      violations.add('$fileName:$line 的 sheet 包了 UnsavedGuard 但没关拖动');
    }
    index = source.indexOf(needle, end + 1);
  }
  return violations;
}

void main() {
  test('★★ 门禁:sheet 里包 UnsavedGuard ⇒ 必须 enableDrag: false', () {
    final List<String> violations = <String>[];
    for (final FileSystemEntity entity in Directory('lib').listSync(
      recursive: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      violations.addAll(
        unsavedGuardSheetViolations(
          entity.path,
          entity.readAsStringSync(),
        ),
      );
    }
    expect(
      violations,
      isEmpty,
      reason:
          '守卫在场还让 sheet 能拖 = 下滑静默丢未保存的修改。'
          '要么把 enableDrag 关掉(退出走守卫接住的取消/返回),'
          '要么别在这个 sheet 里放 UnsavedGuard。',
    );
  });

  test('★ 负控:真违规必须被这条门禁抓到(证明上面不是恒绿)', () {
    const String violating = '''
Future<void> open(BuildContext context) => showCupertinoSheet<void>(
  context: context,
  enableDrag: true,
  scrollableBuilder: (BuildContext c, ScrollController s) => UnsavedGuard(
    isDirty: () => true,
    child: Form(),
  ),
);
''';
    expect(
      unsavedGuardSheetViolations('fixture.dart', violating),
      hasLength(1),
    );
  });

  test('★ 负控:合规写法不许误报', () {
    const String compliant = '''
Future<void> open(BuildContext context) => showCupertinoSheet<void>(
  context: context,
  enableDrag: false,
  scrollableBuilder: (BuildContext c, ScrollController s) => UnsavedGuard(
    isDirty: () => true,
    child: Form(),
  ),
);
''';
    expect(unsavedGuardSheetViolations('fixture.dart', compliant), isEmpty);
  });
}
