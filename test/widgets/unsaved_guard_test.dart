// 脏表单返回时的守卫。
//
// ★★ App 此前**一处都没有**;小程序在 6 个编辑面上都挂了。
//   代价不对称:少这道闸,用户填了十分钟、误触返回就全没了,
//   而且**没有任何提示说他刚丢了什么**。多这道闸最坏只是多点一次。
//
// ⚠️ 只在真的脏时拦。没改过还弹确认框,会让「返回」这个最高频的动作变重,
//   用户很快开始盲点确认 —— 那时这道闸对真正该拦的那次也失效了。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/widgets/unsaved_guard.dart';

Widget _app({
  required bool dirty,
  required VoidCallback onPopped,
  TargetPlatform? platform,
}) => MaterialApp(
  theme: platform == null ? null : ThemeData(platform: platform),
  home: Scaffold(
    body: Builder(
      builder: (BuildContext c) => TextButton(
        onPressed: () => Navigator.of(c)
            .push(
              MaterialPageRoute<void>(
                builder: (_) => UnsavedGuard(
                  isDirty: () => dirty,
                  child: Scaffold(
                    appBar: AppBar(title: const Text('编辑')),
                    body: Builder(
                      builder: (BuildContext c2) => TextButton(
                        key: const Key('back'),
                        onPressed: () => Navigator.of(c2).maybePop(),
                        child: const Text('返回'),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .then((_) => onPopped()),
        child: const Text('open'),
      ),
    ),
  ),
);

Widget _appThatBecomesCleanWithoutRebuildingGuard({
  required VoidCallback onPopped,
}) {
  bool dirty = true;
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext c) => TextButton(
          onPressed: () => Navigator.of(c)
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => UnsavedGuard(
                    isDirty: () => dirty,
                    child: Scaffold(
                      appBar: AppBar(title: const Text('编辑')),
                      body: Builder(
                        builder: (BuildContext c2) => Column(
                          children: <Widget>[
                            TextButton(
                              key: const Key('mark-clean'),
                              onPressed: () => dirty = false,
                              child: const Text('恢复原值'),
                            ),
                            TextButton(
                              key: const Key('back'),
                              onPressed: () => Navigator.of(c2).maybePop(),
                              child: const Text('返回'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .then((_) => onPopped()),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Widget _sheetApp({required bool Function() isDirty}) => MaterialApp(
  home: Builder(
    builder: (BuildContext ctx) => TextButton(
      onPressed: () => showCupertinoSheet<void>(
        context: ctx,
        // ⚠️ 用 scrollableBuilder(仓里 79/86 处都是它),内容是**不带内层
        //   滚动条**的短表单 —— 守卫能接住的正是这种结构。内容自带滚动条时,
        //   拖动会先被内层 Scrollable 吃掉,页面侧拦不住(见 unsaved_guard.dart)。
        scrollableBuilder: (BuildContext c, ScrollController controller) =>
            UnsavedGuard(
          isDirty: isDirty,
          child: const Scaffold(
            body: Center(
              child: Text('SHEET-BODY', textDirection: TextDirection.ltr),
            ),
          ),
        ),
      ),
      child: const Text('open-sheet'),
    ),
  ),
);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open-sheet'));
  await tester.pumpAndSettle();
  expect(find.text('SHEET-BODY'), findsOneWidget);
}

Future<void> _swipeDown(WidgetTester tester) async {
  await tester.drag(
    find.text('SHEET-BODY'),
    const Offset(0, 700),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★★ 脏了 ⇒ 拦一下,并说清「返回后本次修改不会保留」', (WidgetTester t) async {
    bool popped = false;
    await t.pumpWidget(_app(dirty: true, onPopped: () => popped = true));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('back')));
    await t.pumpAndSettle();

    expect(find.text(kUnsavedTitle), findsOneWidget);
    expect(
      find.text(kUnsavedContent),
      findsOneWidget,
      reason: '只问「确定吗」不说丢什么,用户没法判断该不该点',
    );
    expect(popped, isFalse, reason: '还没确认就退出去了 —— 闸没起作用');
  });

  testWidgets('★ 确认「放弃修改」才真的退出', (WidgetTester t) async {
    bool popped = false;
    await t.pumpWidget(_app(dirty: true, onPopped: () => popped = true));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('back')));
    await t.pumpAndSettle();
    await t.tap(find.text(kUnsavedConfirm));
    await t.pumpAndSettle();
    expect(popped, isTrue);
  });

  testWidgets('★ 选「继续编辑」留在原页,内容还在', (WidgetTester t) async {
    bool popped = false;
    await t.pumpWidget(_app(dirty: true, onPopped: () => popped = true));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('back')));
    await t.pumpAndSettle();
    await t.tap(find.text(kUnsavedCancel));
    await t.pumpAndSettle();
    expect(popped, isFalse);
    expect(find.text('编辑'), findsOneWidget, reason: '应该还在编辑页');
  });

  testWidgets('★★ 没改过 ⇒ **不拦**,直接退出', (WidgetTester t) async {
    // 拦多了用户会开始盲点确认,那时这道闸对真正该拦的那次也失效了。
    bool popped = false;
    await t.pumpWidget(_app(dirty: false, onPopped: () => popped = true));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('back')));
    await t.pumpAndSettle();
    expect(find.text(kUnsavedTitle), findsNothing);
    expect(popped, isTrue);
  });

  testWidgets('★ iOS 干净编辑页保留 Cupertino 边缘侧滑返回', (WidgetTester t) async {
    bool popped = false;
    await t.pumpWidget(
      _app(
        dirty: false,
        platform: TargetPlatform.iOS,
        onPopped: () => popped = true,
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final TestGesture gesture = await t.startGesture(const Offset(0, 300));
    await gesture.moveBy(const Offset(500, 0));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();

    expect(popped, isTrue, reason: '无未保存修改时应保留 iOS 交互式返回');
  });

  testWidgets('★ 恢复原值后即使守卫没重建,返回也不会被永久吞掉', (WidgetTester t) async {
    bool popped = false;
    await t.pumpWidget(
      _appThatBecomesCleanWithoutRebuildingGuard(onPopped: () => popped = true),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('mark-clean')));
    await t.pump();
    await t.tap(find.byKey(const Key('back')));
    await t.pumpAndSettle();

    expect(find.text(kUnsavedTitle), findsNothing);
    expect(popped, isTrue, reason: '无未保存修改时必须恢复正常返回');
  });

  // ── S2:sheet 的下滑关闭 ─────────────────────────────────────────────
  //
  // ★★ 下滑关闭走的是 `navigator.pop()`(强制 pop),PopScope 拦不住 ——
  //   所以单独钉:脏了要接住,干净了**一点都不许拦**。

  testWidgets('★★ 脏改动 + sheet 下滑关闭 ⇒ 先确认;确认「放弃修改」才真的关', (
    WidgetTester t,
  ) async {
    await t.pumpWidget(_sheetApp(isDirty: () => true));
    await _openSheet(t);

    await _swipeDown(t);

    expect(find.text(kUnsavedTitle), findsOneWidget);
    expect(find.text(kUnsavedContent), findsOneWidget);
    expect(
      find.text('SHEET-BODY'),
      findsOneWidget,
      reason: '还没确认,sheet 不许先关掉',
    );

    await t.tap(find.text(kUnsavedCancel));
    await t.pumpAndSettle();
    expect(find.text('SHEET-BODY'), findsOneWidget, reason: '选「继续编辑」留在 sheet');

    await _swipeDown(t);
    await t.tap(find.text(kUnsavedConfirm));
    await t.pumpAndSettle();
    expect(find.text('SHEET-BODY'), findsNothing, reason: '确认「放弃修改」才真的关');
  });

  testWidgets('★★ 负控:没脏改动 + sheet 下滑关闭 ⇒ **直接关,不弹确认**', (
    WidgetTester t,
  ) async {
    await t.pumpWidget(_sheetApp(isDirty: () => false));
    await _openSheet(t);

    await _swipeDown(t);

    expect(find.text(kUnsavedTitle), findsNothing);
    expect(
      find.text('SHEET-BODY'),
      findsNothing,
      reason: '干净时下滑关闭必须与原生一致,不许被守卫拖住',
    );
  });

  testWidgets('★ 负控:不在 sheet 里 ⇒ 向下拖不弹确认(识别器压根不装)', (
    WidgetTester t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: UnsavedGuard(
          isDirty: () => true,
          child: const Scaffold(
            body: Center(
              child: Text('PLAIN-BODY', textDirection: TextDirection.ltr),
            ),
          ),
        ),
      ),
    );

    await t.drag(
      find.text('PLAIN-BODY'),
      const Offset(0, 700),
      warnIfMissed: false,
    );
    await t.pumpAndSettle();

    expect(find.text(kUnsavedTitle), findsNothing);
  });

  test('文案与小程序逐字一致(pages/club/edit/index.wxml:8)', () {
    expect(kUnsavedTitle, '放弃未保存修改？');
    expect(kUnsavedContent, '返回后，本次修改不会保留。');
    expect(kUnsavedConfirm, '放弃修改');
    expect(kUnsavedCancel, '继续编辑');
  });
}
