// CySearchField 行为契约。
//
// 这个组件替换掉 6 处各写一套的 TextField,其中只有 1 处有清除钮。
// 下面每条测的都是「换掉之后最容易悄悄坏掉」的点,不是覆盖率填空。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/cy_search_field.dart';

/// 一个把 value 真的存起来的宿主 —— 受控组件必须放在会回写的容器里测,
/// 拿 `value: ''` 配一个空 onChanged 测,等于测了个永远为空的框。
class _Host extends StatefulWidget {
  const _Host({this.initial = ''});

  final String initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String _v = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: CySearchField(
          value: _v,
          placeholder: '搜索姓名或手机号',
          onChanged: (String s) {
            setState(() => _v = s);
          },
        ),
      ),
    );
  }
}

Color _boxColor(WidgetTester tester) {
  final Container c = tester.widget<Container>(
    find
        .ancestor(
          of: find.byType(CupertinoTextField),
          matching: find.byType(Container),
        )
        .first,
  );
  return (c.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('外部值与框内文字往返一致', (WidgetTester tester) async {
    // ⚠️ **这条测不到「光标弹回开头」**,别把它当那道保险。
    //    受控输入框的经典坑是 didUpdateWidget 无条件回写 value,导致每敲一个字
    //    光标跳回最前。组件里有守卫(只在值真的不同时才写,并恢复光标到末尾),
    //    但我做负控时把守卫整个摘掉,光标位置**一模一样**(实测 sel=2 → sel=2)——
    //    因为 `tester.enterText` 是整段替换,重现不出逐字输入的时序。
    //    也就是说:守卫是有依据的防御,但**目前没有测试盯着它**,改动那段要人工复核。
    //    (真要覆盖得走 integration_test 打真键盘,不在本轮范围。)
    await tester.pumpWidget(const _Host());
    await tester.enterText(find.byType(CupertinoTextField), '张三');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .controller!
          .text,
      '张三',
    );
  });

  testWidgets('清除钮:有内容才出现,点了要把值清空', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    expect(
      find.byIcon(CupertinoIcons.clear),
      findsNothing,
      reason: '空框不该显示清除钮',
    );

    await tester.enterText(find.byType(CupertinoTextField), 'abc');
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.clear), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.clear));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .controller!
          .text,
      '',
    );
    expect(find.byIcon(CupertinoIcons.clear), findsNothing);
  });

  testWidgets('★ 清除钮触达区 44pt —— 不是图标那 16pt', (WidgetTester tester) async {
    // 按图标大小做热区会点不中。小程序侧同样把它撑到 88rpx。
    await tester.pumpWidget(const _Host(initial: 'abc'));
    await tester.pumpAndSettle();
    final Size s = tester.getSize(find.byType(CupertinoButton));
    expect(s.width, greaterThanOrEqualTo(44));
    expect(s.height, greaterThanOrEqualTo(44));
  });

  testWidgets('★ 空态与有内容态底色不同 —— 这是「有没有正在生效的筛选」的唯一线索', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();
    final Color empty = _boxColor(tester);

    await tester.enterText(find.byType(CupertinoTextField), 'x');
    await tester.pumpAndSettle();
    final Color filled = _boxColor(tester);

    expect(
      filled,
      isNot(empty),
      reason:
          'inputBgEmpty / inputBgFilled 两个 token 在 App 里定义了却'
          '一直没人用,这条就是防它再次退化成同一个值',
    );
  });

  testWidgets('loading 时显示转圈,并让位给它不显示清除钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CySearchField(value: 'abc', loading: true, onChanged: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(CupertinoIcons.clear), findsNothing);
  });

  testWidgets('disabled 时不显示清除钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CySearchField(value: 'abc', enabled: false, onChanged: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.clear), findsNothing);
  });

  testWidgets('搜索输入与图标均使用 Cupertino 官方组件', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());

    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('200% 字号与 Reduce Motion 下仍可输入且命中区不小于 44pt', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: CySearchField(value: 'Apple', onChanged: _ignoreChangedValue),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CySearchField)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byType(CupertinoButton)).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });
}

void _ignoreChangedValue(String _) {}
