// 门禁:弹窗一律走 iOS 原生呈现,且**任何时候都得有可点的出口**。
//
// ★ 为什么值得一道闸(两条都是这轮 cy-popup-native 查出来的):
//   1. 自绘浮层(showGeneralDialog / showModalBottomSheet / Material 遮罩卡)
//      没有系统转场、没有系统材质、没有系统避让 —— 每写一处就多一处「像 iOS 但不是」。
//      底子已经收干净了(全仓 0 处),别让它长回来。
//   2. `showCupertinoSheet` 生成的 `CupertinoSheetRoute` **遮罩点不动**
//      (SDK: `barrierColor => CupertinoColors.transparent` + `barrierDismissible => false`,
//      packages/flutter/lib/src/cupertino/sheet.dart:777-781)。
//      所以 `enableDrag: false` 的 sheet 一旦没有关闭/取消按钮,**唯一的出口是「提交成功」**——
//      改错了想放弃都出不去。实证:帖文编辑器(2026-09-19 修)就是这么一张 trap。
//      「只能靠下滑关掉」同样不合格:滑动不是可点出口,视障与外接键鼠用户点不到。
//
// 负控:文件末尾那条合成源码必须被扫出来 —— 扫不出来等于闸是空的。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 允许出现 `DraggableScrollableSheet` 的位置 → 理由。
/// ⚠️ 加豁免前先确认它**不是弹窗**:常驻面板没有遮罩、不弹不关,是页面布局的一部分。
const Map<String, String> kDraggableSheetAllowlist = <String, String>{
  'lib/feature/map/map_page.dart':
      '地图页常驻「附近」底栏(D7:地图是 App 自有体验)。它不是弹窗:没有遮罩、'
      '不弹不关,是 Stack 里的页面结构;改成模态 sheet 会砍掉地图页的主交互。',
};

/// 自绘浮层路由:一律禁(系统弹窗请用 showCupertinoDialog / cyConfirm /
/// showCyNativeSheet / showCupertinoSheet / showCupertinoModalPopup)。
final RegExp _handRolledPopup = RegExp(
  r'\b(showGeneralDialog|showModalBottomSheet|showBottomSheet|showDialog)\s*[<(]',
);

/// 可点出口的线索:关闭/取消字样或系统关闭图标,且同文件里有 pop。
final RegExp _closeAffordance = RegExp(r'xmark|关闭|取消');
final RegExp _popCall = RegExp(r'\.(pop|maybePop)\(|popSheet');

/// 返回 `文件:行` 列表:`enableDrag: false` 但同文件里找不到可点出口。
List<String> scanTrappedSheets(String path, String src) {
  final List<String> lines = src.split('\n');
  final List<String> offenders = <String>[];
  final bool hasClose =
      _closeAffordance.hasMatch(src) && _popCall.hasMatch(src);
  for (int i = 0; i < lines.length; i++) {
    if (!RegExp(r'enableDrag:\s*false').hasMatch(lines[i])) continue;
    // sheet 的内容控件就在同一个文件里(本仓所有 sheet 都这么写)。
    if (!hasClose) offenders.add('$path:${i + 1}');
  }
  return offenders;
}

void main() {
  test('弹窗一律原生:不许自绘浮层路由;常驻面板按文件豁免', () {
    final List<String> offenders = <String>[];
    final Set<String> usedAllowances = <String>{};
    int scanned = 0;

    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final String src = e.readAsStringSync();

      for (final RegExp r in <RegExp>[_handRolledPopup]) {
        final List<String> lines = src.split('\n');
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i].trimLeft();
          if (line.startsWith('//') || line.startsWith('///')) continue;
          if (r.hasMatch(lines[i])) offenders.add('${e.path}:${i + 1} ${line}');
        }
      }

      if (src.contains('DraggableScrollableSheet')) {
        // 注释里提一嘴("如 DraggableScrollableSheet 提供的控制器")不算自绘。
        final bool inCode = src
            .split('\n')
            .any(
              (String l) =>
                  l.contains('DraggableScrollableSheet') &&
                  !l.trimLeft().startsWith('//'),
            );
        if (!inCode) continue;
        final String? reason = kDraggableSheetAllowlist[e.path];
        if (reason == null) {
          offenders.add('${e.path}:1 DraggableScrollableSheet —— 自绘 sheet,改原生');
        } else {
          usedAllowances.add(e.path);
        }
      }
    }

    expect(scanned, greaterThan(400), reason: '只扫到 $scanned 个文件,目录变了?');
    final Set<String> stale = kDraggableSheetAllowlist.keys.toSet().difference(
      usedAllowances,
    );
    expect(stale, isEmpty, reason: '这些豁免已失效,请从名单删掉:\n${stale.join('\n')}');
    expect(
      offenders,
      isEmpty,
      reason:
          '自绘浮层要换成系统呈现'
          '(居中确认 cyConfirm / 底部走 showCyNativeSheet 或 showCupertinoSheet'
          ' / 短选项 showCupertinoModalPopup + CupertinoActionSheet):\n'
          '${offenders.join('\n')}',
    );
  });

  test('★ 不能拖的 sheet 必须有可点关闭/取消(trap 闸)', () {
    final List<String> offenders = <String>[];
    int sites = 0;
    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      if (!src.contains('enableDrag')) continue;
      final List<String> hits = scanTrappedSheets(e.path, src);
      sites += RegExp('enableDrag:\\s*false').allMatches(src).length;
      offenders.addAll(hits);
    }
    expect(sites, greaterThan(0), reason: '一个 enableDrag:false 都没扫到,闸的判据失效了');
    expect(
      offenders,
      isEmpty,
      reason:
          'showCupertinoSheet 的遮罩点不动(barrierDismissible=false)。'
          '这些 sheet 关不掉,只能提交成功:\n${offenders.join('\n')}',
    );
  });

  test('★ 负控:trap 闸必须扫得出「不能拖又没关闭」的 sheet', () {
    const String trap = '''
Future<void> showX(BuildContext context) => showCupertinoSheet<void>(
  context: context,
  enableDrag: false,
  scrollableBuilder: (BuildContext context, ScrollController c) => ListView(
    children: <Widget>[
      Text('表单'),
      CupertinoButton(onPressed: () {}, child: Text('保存')),
    ],
  ),
);
''';
    expect(scanTrappedSheets('lib/feature/x/trap.dart', trap), <String>[
      'lib/feature/x/trap.dart:3',
    ]);

    const String fixed = '''
Future<void> showX(BuildContext context) => showCupertinoSheet<void>(
  context: context,
  enableDrag: false,
  scrollableBuilder: (BuildContext context, ScrollController c) => ListView(
    children: <Widget>[
      Text('表单'),
      CupertinoButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('取消'),
      ),
      CupertinoButton(onPressed: () {}, child: Text('保存')),
    ],
  ),
);
''';
    expect(scanTrappedSheets('lib/feature/x/ok.dart', fixed), isEmpty);
  });
}
