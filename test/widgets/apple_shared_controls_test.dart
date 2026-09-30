import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('共享错误态使用 Apple 加载与原生按钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Expanded(
                child: StatusView(message: '失败', onRetry: () {}),
              ),
              const LoadingView(),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CyNativeButton), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('CyChip 可视 32pt 但按钮命中区不小于 44pt', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyChip(label: '附近', selected: true, onTap: () {}),
        ),
      ),
    );

    final Finder button = find.byType(CupertinoButton);
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('CyCell 使用系统 CupertinoListTile 命中层且保留点击业务', (
    WidgetTester tester,
  ) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CyCell(title: '订单', onTap: () => tapped = true),
        ),
      ),
    );

    // P3(CyCell)起,行本体是系统的 `CupertinoListTile`(按压高亮/行高交给系统),
    // 不再是自绘 + `CupertinoButton` 包一层。
    final Finder tile = find.byType(CupertinoListTile);
    expect(tile, findsOneWidget);
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
    expect(find.byType(InkWell), findsNothing);
    await tester.tap(find.text('订单'));
    expect(tapped, isTrue);
  });
}
