// cyConfirm 行为契约。
//
// 这个组件替换掉的是**危险动作**的确认弹窗(退出账号、删除项目、删除参与人、
// 注销账号)。这里每条测的都是「错了会让用户误删东西」的点。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/cy_confirm.dart';

/// 把 cyConfirm 的返回值**渲染出来**,测试才能断言它。
///
/// ⚠️ 第一版我把返回值存进局部变量就 return —— 那时弹窗还没关,拿到的恒为 null,
///    于是「点遮罩不能当确认」那条**注入 `r ?? true` 也不红**。
///    断言必须落在真正的返回值上,不能只断言「弹窗关掉了」。
class _Host extends StatefulWidget {
  const _Host({
    required this.danger,
    required this.showCancel,
    this.nativePresenter,
  });

  final bool danger;
  final bool showCancel;
  final CyNativeConfirmPresenter? nativePresenter;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _result = 'none';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('R=$_result'),
            ElevatedButton(
              onPressed: () async {
                final bool r = await cyConfirm(
                  context,
                  title: '删除「静安夜跑」?',
                  content: '删除后无法恢复。',
                  confirmText: '删除',
                  danger: widget.danger,
                  showCancel: widget.showCancel,
                  nativePresenter: widget.nativePresenter,
                );
                setState(() => _result = '$r');
              },
              child: const Text('open'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _open(
  WidgetTester tester, {
  bool danger = false,
  bool showCancel = true,
  bool light = false,
  CyNativeConfirmPresenter? nativePresenter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.merchantLight() : AppTheme.dark(),
      home: _Host(
        danger: danger,
        showCancel: showCancel,
        nativePresenter: nativePresenter,
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class _FakeNativePresenter implements CyNativeConfirmPresenter {
  _FakeNativePresenter(this.result);

  final CyNativeConfirmResult result;
  CyNativeConfirmRequest? request;

  @override
  Future<CyNativeConfirmResult> show(
    BuildContext context,
    CyNativeConfirmRequest request,
  ) async {
    this.request = request;
    return result;
  }
}

class _FakeNativeAlertDriver implements CyNativeAlertDriver {
  _FakeNativeAlertDriver({
    this.supportsLiquidGlass = true,
    this.result,
    this.error,
  });

  @override
  final bool supportsLiquidGlass;
  final String? result;
  final Object? error;
  List<CyNativeAlertAction>? actions;
  int showCount = 0;

  @override
  Future<String?> show({
    required BuildContext context,
    required String title,
    required String? message,
    required List<CyNativeAlertAction> actions,
  }) async {
    showCount += 1;
    this.actions = actions;
    if (error case final Object value) throw value;
    return result;
  }
}

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext value) {
          context = value;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return context;
}

void main() {
  testWidgets('iOS 原生危险确认保留 destructive/cancel 语义并返回 true', (
    WidgetTester tester,
  ) async {
    final _FakeNativePresenter presenter = _FakeNativePresenter(
      CyNativeConfirmResult.confirmed,
    );

    await _open(tester, danger: true, nativePresenter: presenter);

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('R=true'), findsOneWidget);
    expect(presenter.request?.title, '删除「静安夜跑」?');
    expect(presenter.request?.confirmText, '删除');
    expect(presenter.request?.cancelText, '取消');
    expect(presenter.request?.danger, isTrue);
    expect(presenter.request?.showCancel, isTrue);
  });

  testWidgets('原生 presentation 不可用时回退 Cupertino 确认框', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      nativePresenter: _FakeNativePresenter(CyNativeConfirmResult.unavailable),
    );

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(CupertinoDialogAction), findsNWidgets(2));
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('原生取消返回 false 且不再弹 Flutter Dialog', (WidgetTester tester) async {
    await _open(
      tester,
      nativePresenter: _FakeNativePresenter(CyNativeConfirmResult.cancelled),
    );

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('R=false'), findsOneWidget);
  });

  testWidgets('showCancel:false 原样传给原生确认请求', (WidgetTester tester) async {
    final _FakeNativePresenter presenter = _FakeNativePresenter(
      CyNativeConfirmResult.confirmed,
    );

    await _open(tester, showCancel: false, nativePresenter: presenter);

    expect(presenter.request?.showCancel, isFalse);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('原生适配器在系统不支持时返回 unavailable', (WidgetTester tester) async {
    final BuildContext context = await _pumpContext(tester);
    final _FakeNativeAlertDriver driver = _FakeNativeAlertDriver(
      supportsLiquidGlass: false,
    );
    final CyLiquidGlassConfirmPresenter presenter =
        CyLiquidGlassConfirmPresenter(driver: driver);

    final CyNativeConfirmResult result = await presenter.show(
      context,
      const CyNativeConfirmRequest(
        title: '标题',
        content: '内容',
        confirmText: '确定',
        cancelText: '取消',
        danger: false,
        showCancel: true,
      ),
    );

    expect(result, CyNativeConfirmResult.unavailable);
    expect(driver.showCount, 0);
  });

  testWidgets('原生适配器把 PlatformException 收敛为 unavailable', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await _pumpContext(tester);
    final CyLiquidGlassConfirmPresenter presenter =
        CyLiquidGlassConfirmPresenter(
          driver: _FakeNativeAlertDriver(
            error: PlatformException(code: 'present_failed'),
          ),
        );

    final CyNativeConfirmResult result = await presenter.show(
      context,
      const CyNativeConfirmRequest(
        title: '标题',
        content: null,
        confirmText: '确定',
        cancelText: '取消',
        danger: false,
        showCancel: true,
      ),
    );

    expect(result, CyNativeConfirmResult.unavailable);
  });

  testWidgets('danger 只映射到原生确认动作的 destructive 语义', (WidgetTester tester) async {
    final BuildContext context = await _pumpContext(tester);
    final _FakeNativeAlertDriver driver = _FakeNativeAlertDriver(
      result: 'confirm',
    );
    final CyLiquidGlassConfirmPresenter presenter =
        CyLiquidGlassConfirmPresenter(driver: driver);

    final CyNativeConfirmResult result = await presenter.show(
      context,
      const CyNativeConfirmRequest(
        title: '删除?',
        content: null,
        confirmText: '删除',
        cancelText: '取消',
        danger: true,
        showCancel: true,
      ),
    );

    expect(result, CyNativeConfirmResult.confirmed);
    expect(driver.actions, hasLength(2));
    expect(driver.actions?.first.isCancel, isTrue);
    expect(driver.actions?.first.isDestructive, isFalse);
    expect(driver.actions?.last.id, 'confirm');
    expect(driver.actions?.last.isCancel, isFalse);
    expect(driver.actions?.last.isDestructive, isTrue);
  });

  testWidgets('★ 点遮罩关掉 = 取消,绝不能当成确认', (WidgetTester tester) async {
    // Cupertino dialog 在点遮罩时返回 **null**。调用方写 `if (r != false)` 或
    // `r ?? true` 就会把「关掉弹窗」当成「确认删除」。
    // cyConfirm 把 null 收敛成 false,这条盯着那个收敛 —— 所以必须断言
    // **返回值是 false**,只断言「弹窗关掉了」是抓不到的。
    await _open(tester);
    expect(find.text('删除'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // 点弹窗外面 = 点遮罩
    await tester.pumpAndSettle();

    expect(find.text('删除'), findsNothing, reason: '遮罩没关掉弹窗');
    expect(
      find.text('R=false'),
      findsOneWidget,
      reason: '点遮罩必须返回 false;返回 true = 用户没确认却把东西删了',
    );
  });

  testWidgets('确认返回 true,取消返回 false', (WidgetTester tester) async {
    await _open(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('R=true'), findsOneWidget);

    await _open(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('R=false'), findsOneWidget);
  });

  testWidgets('★ 危险动作的确认键保留 Cupertino destructive 语义', (
    WidgetTester tester,
  ) async {
    await _open(tester, danger: true);
    final CupertinoDialogAction confirm = tester.widget(
      find.ancestor(
        of: find.text('删除'),
        matching: find.byType(CupertinoDialogAction),
      ),
    );
    final CupertinoDialogAction cancel = tester.widget(
      find.ancestor(
        of: find.text('取消'),
        matching: find.byType(CupertinoDialogAction),
      ),
    );

    expect(confirm.isDestructiveAction, isTrue);
    expect(confirm.isDefaultAction, isFalse);
    expect(cancel.isDestructiveAction, isFalse);
  });

  testWidgets('非危险动作的确认键是 Cupertino default action', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final CupertinoDialogAction confirm = tester.widget(
      find.ancestor(
        of: find.text('删除'),
        matching: find.byType(CupertinoDialogAction),
      ),
    );
    expect(confirm.isDefaultAction, isTrue);
    expect(confirm.isDestructiveAction, isFalse);
  });

  testWidgets('showCancel:false 时只有一颗按钮', (WidgetTester tester) async {
    await _open(tester, showCancel: false);
    expect(find.text('取消'), findsNothing);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('★ 浅色主题也使用系统 Cupertino 确认框', (WidgetTester tester) async {
    await _open(tester, danger: true, light: true);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    final CupertinoDialogAction confirm = tester.widget(
      find.ancestor(
        of: find.text('删除'),
        matching: find.byType(CupertinoDialogAction),
      ),
    );
    expect(confirm.isDestructiveAction, isTrue);
  });
}
