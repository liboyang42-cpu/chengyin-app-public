import 'package:chengyin_app/core/widgets/cy_image_source_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Driver implements CyNativeImageSourceDriver {
  _Driver({required this.supportsLiquidGlass, this.result, this.error});

  @override
  final bool supportsLiquidGlass;
  final String? result;
  final Object? error;
  List<CyNativeImageSourceAction>? actions;
  int showCount = 0;

  Rect? sourceRect;

  @override
  Future<String?> showActionSheet({
    required BuildContext context,
    required List<CyNativeImageSourceAction> actions,
    Rect? sourceRect,
  }) async {
    showCount += 1;
    this.actions = actions;
    this.sourceRect = sourceRect;
    if (error case final Object value) throw value;
    return result;
  }
}

Future<BuildContext> _context(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  late BuildContext value;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Builder(
          builder: (BuildContext context) {
            value = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return value;
}

/// 让 context 有一个**真实有尺寸**的 RenderBox(触发元素的替身)。
Future<BuildContext> _triggerContext(
  WidgetTester tester, {
  Size size = const Size(120, 44),
}) async {
  late BuildContext value;
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Builder(
            builder: (BuildContext context) {
              value = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  return value;
}

void main() {
  testWidgets('iOS 26 用原生 UIAlertController.actionSheet 并保留三项顺序', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await _context(tester);
    final _Driver driver = _Driver(supportsLiquidGlass: true, result: 'camera');

    final CyImagePickSource? source = await cyChooseImageSource(
      context,
      nativeDriver: driver,
    );

    expect(source, CyImagePickSource.camera);
    expect(driver.showCount, 1);
    expect(
      driver.actions?.map((CyNativeImageSourceAction row) => row.title),
      <String>['拍照', '从相册选择', '取消'],
    );
    expect(driver.actions?.last.isCancel, isTrue);
    expect(find.byType(CupertinoActionSheet), findsNothing);
  });

  testWidgets('原生取消返回 null，不误开第二层 Flutter Sheet', (WidgetTester tester) async {
    final BuildContext context = await _context(tester);
    final _Driver driver = _Driver(supportsLiquidGlass: true, result: null);

    expect(await cyChooseImageSource(context, nativeDriver: driver), isNull);
    expect(driver.showCount, 1);
    expect(find.byType(CupertinoActionSheet), findsNothing);
  });

  testWidgets('旧 iOS 降级 CupertinoActionSheet，44pt、VoiceOver 与取消均可用', (
    WidgetTester tester,
  ) async {
    final BuildContext context = await _context(tester);
    final _Driver driver = _Driver(supportsLiquidGlass: false);

    final Future<CyImagePickSource?> pending = cyChooseImageSource(
      context,
      nativeDriver: driver,
    );
    await tester.pumpAndSettle();

    expect(driver.showCount, 0);
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.bySemanticsLabel('拍照'), findsOneWidget);
    expect(find.bySemanticsLabel('从相册选择'), findsOneWidget);
    expect(
      tester
          .getSize(find.widgetWithText(CupertinoActionSheetAction, '拍照'))
          .height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();
    expect(await pending, CyImagePickSource.gallery);
  });

  testWidgets('原生插件暂不可用时回退，关闭遮罩仍是取消', (WidgetTester tester) async {
    final BuildContext context = await _context(tester);
    final _Driver driver = _Driver(
      supportsLiquidGlass: true,
      error: MissingPluginException(),
    );

    final Future<CyImagePickSource?> pending = cyChooseImageSource(
      context,
      nativeDriver: driver,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(await pending, isNull);
  });

  // ── S4:action sheet 的锚点(sourceView)──────────────────────────────
  //
  // ★ 能断言的是「触发元素的矩形一路传到原生驱动」;
  //   断言不了的是 iPad 上 UIAlertController 最终把 popover 摆在哪 ——
  //   那在 UIKit 里,测试环境到不了(见 PR 说明)。

  testWidgets('★★ S4:锚点透传 —— 触发元素的矩形一路走到原生 action sheet', (
    WidgetTester tester,
  ) async {
    final _Driver driver = _Driver(supportsLiquidGlass: true, result: 'camera');
    final Future<CyImagePickSource?> pending = cyChooseImageSource(
      await _triggerContext(tester),
      sourceRect: const Rect.fromLTWH(24, 88, 120, 44),
      nativeDriver: driver,
    );
    await tester.pumpAndSettle();

    expect(await pending, CyImagePickSource.camera);
    expect(
      driver.sourceRect,
      const Rect.fromLTWH(24, 88, 120, 44),
      reason: '锚点必须跟着调用传进驱动,不能在中间被丢掉',
    );
  });

  testWidgets('★ S4:不显式传锚点 ⇒ 用 context 自身的矩形兜底', (WidgetTester tester) async {
    final _Driver driver = _Driver(supportsLiquidGlass: true, result: null);

    await cyChooseImageSource(
      await _triggerContext(tester),
      nativeDriver: driver,
    );

    expect(driver.sourceRect, const Rect.fromLTWH(0, 0, 120, 44));
  });

  testWidgets('★ S4 负控:显式锚点优先 —— 不许被 context 的矩形顶掉', (WidgetTester tester) async {
    final _Driver driver = _Driver(supportsLiquidGlass: true, result: null);

    await cyChooseImageSource(
      await _triggerContext(tester),
      sourceRect: const Rect.fromLTWH(200, 600, 48, 48),
      nativeDriver: driver,
    );

    expect(
      driver.sourceRect,
      const Rect.fromLTWH(200, 600, 48, 48),
      reason: '传了触发元素矩形就以它为准(页内某个按钮 ≠ 整页)',
    );
  });

  testWidgets('★ S4:< 26 降级路径不锚定 —— 明说的降级,不是假装锚上了', (
    WidgetTester tester,
  ) async {
    final _Driver driver = _Driver(supportsLiquidGlass: false);
    final Future<CyImagePickSource?> pending = cyChooseImageSource(
      await _triggerContext(tester),
      sourceRect: const Rect.fromLTWH(24, 88, 120, 44),
      nativeDriver: driver,
    );
    await tester.pumpAndSettle();

    expect(driver.showCount, 0, reason: '降级不走原生驱动,锚点自然也无处可传');
    expect(find.byType(CupertinoActionSheet), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await pending, isNull);
  });

  testWidgets('Reduce Motion 开启时系统降级仍可操作并取消', (WidgetTester tester) async {
    final BuildContext context = await _context(tester, reduceMotion: true);
    final Future<CyImagePickSource?> pending = cyChooseImageSource(
      context,
      nativeDriver: _Driver(supportsLiquidGlass: false),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await pending, isNull);
  });
}
