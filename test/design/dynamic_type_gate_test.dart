// 动态字体门禁(T4)。
//
// ★ 判据来源:手册 T4(必须支持 Dynamic Type 与粗体文本;大字号下改纵向堆叠、
//   少截断)〔HIG-Type〕。分两层守:
//   ① 静态:lib 里不许出现**锁死**系统字号的写法 —— 固定 `textScaleFactor:`、
//      `TextScaler.noScaling`、自己包一层 `textScaler:` 覆盖系统值。
//      2026-09-17 建账实测:三样都是 0 处(现有代码用 `textScalerOf` 主动适配,
//      方向是对的),这条防的是以后顺手「锁死保平安」。
//   ② 渲染:共用层组件在 textScale 2.0 下不许溢出,关键 CTA 命中区仍 ≥44pt。
//      这才是真判据 —— 静态扫描只能说「没有锁死」,证明不了「放得下」。
//
// ⚠️ ② 的已知盲区:固定高度的小标签(如 CyTag 的 22pt)在大字号下会**裁字但不报错**,
//   渲染回读抓不到 → 归人工清单(§9.3),别把它当已覆盖。
// ★ 负控:文末用真正的溢出组件证明 `takeException()` 抓得到;
//   `takeException() == null` 不是恒绿。静态扫描的负控同上。

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';

import 'scan_support.dart';

/// 锁死动态字号的三种写法。
final List<RegExp> _locks = <RegExp>[
  RegExp(r'textScaleFactor\s*:'),
  RegExp(r'TextScaler\.noScaling'),
  // ③ 自己包一层 `textScaler:` **覆盖**系统值。
  //    但 `textScaler: MediaQuery.textScalerOf(context)` 是**透传同一个值**,
  //    不构成锁死 —— 而且对 `TextPainter` 这类非 widget 是**唯一**正确写法:
  //    它不参与 MediaQuery 继承,不显式传就等于按 noScaling 量,
  //    长文折叠的 maxLines 判定会在大字号下算错。所以这里用否定前瞻把
  //    透传排除,只留真覆盖。
  //    ⚠️ 别把这条再改宽:`textScaler: TextScaler.linear(...)` 等真覆盖必须仍被扫到
  //    (负控里钉了正反两面)。
  //    `(?=\S)` 是必需的:`\s*` 会回溯到 0 宽,让前瞻落在空白上而误判命中。
  RegExp(r'textScaler\s*:\s*(?!MediaQuery\.textScalerOf\()(?=\S)'),
];

Widget _gallery() {
  return CupertinoApp(
    home: CupertinoPageScaffold(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const CyPageTitle('我的订单中心', subtitle: '订单、票券与资产都在这里'),
            CySectionTitle('最近的活动与订单', trailing: const CyTag(label: '新')),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                CyChip(label: '全部', selected: true),
                CyChip(label: '进行中', selected: false),
                CyTag(label: '限时'),
                CyAvatar(fallback: '城'),
              ],
            ),
            const CyField(label: '昵称', child: Text('城瘾用户')),
            CyCell(title: '我的订单', subtitle: '3 个进行中', onTap: () {}),
            SizedBox(
              height: 320,
              child: StatusView(
                message: '还没有内容',
                sub: '去逛逛吧',
                icon: CupertinoIcons.tray,
                onRetry: () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 命中区(渲染回读):文字所在的那个可点控件的宽高都要 ≥44pt。
///
/// 判据是**命中区**,不是控件类型 —— 所以这里认两种真的可点件:
///   · `CupertinoButton`(按钮类 CTA,如 StatusView 的「重试」);
///   · `CupertinoListTile`(列表行;CyCell 自 #56 起把行本体交给系统
///     `CupertinoListTile`,按压高亮与 disclosure 都归系统,不再套一层
///     CupertinoButton)。
/// 两者都必须 ≥44pt,换成别的控件(裸 GestureDetector / Semantics)会在这里
/// 直接炸 —— 那正是要拦的:语义层不给命中区。
double _hitSide(WidgetTester tester, String label) {
  final Finder button = find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (Widget w) => w is CupertinoButton || w is CupertinoListTile,
        ),
      )
      .first;
  final Size size = tester.getSize(button);
  return size.width < size.height ? size.width : size.height;
}

void main() {
  test('★ lib 里不许锁死动态字号', () {
    final List<String> offenders = <String>[];
    int scanned = 0;
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final String code = codeOfFile(e.path);
      for (final RegExp lock in _locks) {
        if (lock.hasMatch(code)) offenders.add('${e.path} :: ${lock.pattern}');
      }
    }
    expect(
      scanned,
      greaterThanOrEqualTo(300),
      reason: '只扫到 $scanned 个文件,目录结构变了就先修这条闸',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          '锁死字号 = 用户调大系统字号后这页不变,而别的页会变 —— 一致性直接坏掉。'
          '要适配大字号请用 MediaQuery.textScalerOf(context) 主动改布局:\n${offenders.join('\n')}',
    );
  });

  test('负控:锁死写法必须被扫到', () {
    expect(_locks.any((RegExp r) => r.hasMatch('textScaleFactor: 1.0')), isTrue);
    expect(
      _locks.any((RegExp r) => r.hasMatch('textScaler: TextScaler.noScaling')),
      isTrue,
    );
    expect(
      _locks.any(
        (RegExp r) =>
            r.hasMatch('MediaQuery.textScalerOf(context).scale(16)'),
      ),
      isFalse,
      reason: 'textScalerOf 是主动适配,不是锁死',
    );
    expect(
      _locks.any(
        (RegExp r) => r.hasMatch('textScaler: MediaQuery.textScalerOf(context)'),
      ),
      isFalse,
      reason: '透传环境字号(TextPainter 量长文必须这么写)不是锁死',
    );
    expect(
      _locks.any(
        (RegExp r) => r.hasMatch('textScaler: TextScaler.linear(1.5)'),
      ),
      isTrue,
      reason: '真覆盖必须仍被扫到 —— 这条防的是把 ③ 改宽成恒不命中',
    );
  });

  for (final double scale in <double>[1.0, 2.0]) {
    testWidgets('共用层在 textScale $scale 下不溢出,CTA 命中区 ≥44pt', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_gallery());
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'textScale $scale 下共用层溢出了 —— 大字号是系统设置,不是边缘情况',
      );
      expect(
        _hitSide(tester, '重试'),
        greaterThanOrEqualTo(44),
        reason: 'textScale $scale 下错误态重试钮命中区小于 44pt',
      );
      expect(
        _hitSide(tester, '我的订单'),
        greaterThanOrEqualTo(44),
        reason: 'textScale $scale 下双行行高小于 44pt',
      );
    });
  }

  testWidgets('负控:真实溢出必须被 takeException 抓到(证明上面不是恒绿)', (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            SizedBox(width: 600, height: 10, child: ColoredBox(color: Color(0xFF000000))),
            SizedBox(width: 600, height: 10, child: ColoredBox(color: Color(0xFF000000))),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNotNull, reason: '溢出没被捕获,说明渲染回读是恒绿的');
  });

  testWidgets('负控:小于 44pt 的命中区必须被回读抓到', (WidgetTester tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () {},
              child: const Text('太小了'),
            ),
          ),
        ),
      ),
    );
    expect(_hitSide(tester, '太小了'), lessThan(44));
  });
}
