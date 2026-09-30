import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 全仓门禁:**每一个 `context.push('/x')` 的目标路由都必须真实存在**。
///
/// ★ 为什么值得一条专门的门禁:跳到不存在的路由,go_router 的默认行为是
///   什么都不发生(或落到 errorBuilder)—— **不抛异常、不报错、控制台安静**。
///   于是界面上摆着一个按钮,点下去毫无反应,而所有测试都是绿的。
///   我自己就在写商家工作台时干过一次:给「你还不是商家」配了
///   `context.push('/merchant/apply')`,而那个路由根本没建。
void main() {
  test('声明路由解析父绝对 path 与嵌套相对子路由，且不伪造根路由', () {
    const String source = '''
GoRoute(
  path: '/settings',
  routes: <RouteBase>[
    GoRoute(path: 'about', builder: (_, _) => const AboutPage()),
  ],
)
''';

    final Set<String> declared = _declaredRoutes(source);
    expect(declared, contains('/settings/about'));
    expect(declared, isNot(contains('/about')));
    expect(_matches('/settings/privacy', declared), isFalse);
  });

  test('路由比对忽略 query 和 fragment，但仍会抓住真实缺路由', () {
    const Set<String> declared = <String>{'/merchant/ledger', '/club/:id'};
    expect(_matches('/merchant/ledger?view=settlement', declared), isTrue);
    expect(_matches('/club/42#posts', declared), isTrue);
    expect(_matches('/merchant/missing?view=settlement', declared), isFalse);
  });

  test('所有 push/go 的目标路由都在路由表里', () {
    final routerSrc = File(
      'lib/core/router/app_router.dart',
    ).readAsStringSync();

    // 1) 收集路由表里声明的所有 path。
    final Set<String> declared = _declaredRoutes(routerSrc);
    expect(declared.length, greaterThan(20), reason: '路由表解析失败,门禁会假绿');

    // 2) 扫全仓的 context.push / context.go 字面量目标。
    final offenders = <String>[];
    for (final FileSystemEntity f in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      // ★ 两种写法都要扫:`context.push('/x')` 与
      //   `GoRouter.of(context).push('/x')`。第一版只扫前者 ——
      //   我随后正好用后者写了两处跳转,它们**整个落在门禁盲区里**,
      //   跳到不存在的路由照样零报错。门禁报 0 之前先问它扫的是什么范围。
      for (final RegExpMatch m in RegExp(
        r"(?:context|GoRouter\.of\(context\))\.(?:push|go)\(\s*'(/[^'$]*)'",
      ).allMatches(src)) {
        final target = m.group(1)!;
        if (!_matches(target, declared)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${f.path}:$line  →  $target');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '这些跳转的目标路由不存在。go_router 不会报错,'
          '按钮点下去只是毫无反应:\n${offenders.join('\n')}',
    );
  });
}

Set<String> _declaredRoutes(String routerSource) {
  final List<_RouteCall> calls = <_RouteCall>[];
  for (final RegExpMatch match in RegExp(
    r'\bGoRoute\s*\(',
  ).allMatches(routerSource)) {
    final int? end = _balancedGoRouteEnd(routerSource, match.start);
    if (end == null) continue;
    final String block = routerSource.substring(match.start, end);
    final RegExpMatch? path = RegExp(r"\bpath:\s*'([^']+)'").firstMatch(block);
    if (path == null) continue;
    calls.add(_RouteCall(match.start, end, path.group(1)!));
  }

  for (final _RouteCall call in calls) {
    if (call.rawPath.startsWith('/')) {
      call.fullPath = call.rawPath;
      continue;
    }
    final List<_RouteCall> parents = calls
        .where(
          (_RouteCall candidate) =>
              candidate.start < call.start &&
              candidate.end > call.end &&
              candidate.fullPath != null,
        )
        .toList();
    if (parents.isEmpty) continue;
    parents.sort((_RouteCall a, _RouteCall b) => b.start.compareTo(a.start));
    call.fullPath =
        '${parents.first.fullPath!.replaceFirst(RegExp(r'/$'), '')}/${call.rawPath.replaceFirst(RegExp(r'^/'), '')}';
  }
  return calls
      .map((_RouteCall call) => call.fullPath)
      .whereType<String>()
      .toSet();
}

int? _balancedGoRouteEnd(String source, int start) {
  final int openParen = source.indexOf('(', start);
  if (openParen < 0) return null;
  var depth = 0;
  String? quote;
  var escaped = false;
  for (var index = openParen; index < source.length; index++) {
    final String char = source[index];
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
    } else if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return index + 1;
    }
  }
  return null;
}

class _RouteCall {
  _RouteCall(this.start, this.end, this.rawPath);

  final int start;
  final int end;
  final String rawPath;
  String? fullPath;
}

/// 目标是否匹配某条声明。带 `:param` 的路由按段比对。
bool _matches(String target, Set<String> declared) {
  final String targetPath = Uri.parse(target).path;
  if (declared.contains(targetPath)) return true;
  final tSeg = targetPath.split('/');
  for (final String d in declared) {
    final dSeg = d.split('/');
    if (dSeg.length != tSeg.length) continue;
    var ok = true;
    for (var i = 0; i < dSeg.length; i++) {
      if (dSeg[i].startsWith(':')) continue; // 参数段,任意值都算命中
      if (dSeg[i] != tSeg[i]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}
