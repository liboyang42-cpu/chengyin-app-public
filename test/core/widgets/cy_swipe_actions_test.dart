import 'package:chengyin_app/core/widgets/cy_swipe_actions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 采样用行高：88pt 已经越过「正圆档」（钮高 = 行高 − 28.67，封顶 50.67）。
const double _rowHeight = 88;

/// 测试屏宽（Center 给的松散约束就是它），钮宽封顶要按它算。
const double _screenWidth = 800;

CyContextualAction _action(
  String id, {
  String? label,
  bool destructive = false,
  void Function(String)? onTap,
  bool isEnabled = true,
  String? semanticLabel,
}) {
  return CyContextualAction(
    id: id,
    label: label ?? id,
    semanticLabel: semanticLabel,
    icon: CupertinoIcons.trash,
    destructive: destructive,
    isEnabled: isEnabled,
    onPressed: () => onTap?.call(id),
  );
}

/// 真页面里「同一时刻只开一行」是父级持有 openKey 实现的，这里照搬。
class _Harness extends StatefulWidget {
  const _Harness({
    required this.trailing,
    required this.leading,
    this.rows = 1,
    this.rowHeight = _rowHeight,
    this.rowWidth,
    this.performsFirstActionWithFullSwipe = false,
    this.enabled = true,
  });

  final List<CyContextualAction> Function(String rowKey) trailing;
  final List<CyContextualAction> Function(String rowKey) leading;
  final int rows;
  final double rowHeight;

  /// 不传就是整屏宽；传窄了可以测「文案长过行宽怎么挤」。
  final double? rowWidth;

  final bool performsFirstActionWithFullSwipe;
  final bool enabled;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Object? open;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: CupertinoPageScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final int i in List<int>.generate(widget.rows, (i) => i))
                SizedBox(
                  width: widget.rowWidth,
                  height: widget.rowHeight,
                  child: CySwipeActionsRow(
                    key: Key('row-$i'),
                    rowKey: '$i',
                    openKey: open,
                    onOpenChanged: (Object? v) => setState(() => open = v),
                    leading: widget.leading('$i'),
                    trailing: widget.trailing('$i'),
                    performsFirstActionWithFullSwipe:
                        widget.performsFirstActionWithFullSwipe,
                    enabled: widget.enabled,
                    child: ColoredBox(
                      color: CupertinoColors.systemBackground.resolveFrom(
                        context,
                      ),
                      child: Semantics(
                        key: Key('content-$i'),
                        label: '内容 $i',
                        button: true,
                        onTap: () => setState(() {}),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _swipeLeft(WidgetTester tester, String rowKey, double dx) async {
  await tester.drag(find.byKey(Key(rowKey)), Offset(dx, 0), touchSlopY: 0);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('收起时不构建动作钮，行内容照常可点', (WidgetTester tester) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', destructive: true, onTap: ran.add),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('swipe-action-del-0')), findsNothing);
    expect(find.byKey(const Key('content-0')), findsOneWidget);
  });

  testWidgets('左滑过阈值 → 露出 trailing 动作', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('share-$k'),
          _action('del-$k', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();

    await _swipeLeft(tester, 'row-0', -120);
    expect(find.byKey(const Key('swipe-action-del-0')), findsOneWidget);
    expect(find.byKey(const Key('swipe-action-share-0')), findsOneWidget);
  });

  testWidgets('滑不过一半 → 回弹收起', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('share-$k'),
          _action('del-$k', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();

    // 两个正圆钮的面板宽 ~133，只滑 20 远不到一半。
    await _swipeLeft(tester, 'row-0', -20);
    expect(find.byKey(const Key('swipe-action-del-0')), findsNothing);
  });

  testWidgets('★ 划到底不自动执行 —— 必须点（默认策略）', (WidgetTester tester) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('share-$k', onTap: ran.add),
          _action('del-$k', destructive: true, onTap: ran.add),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    final double beforeDx = tester
        .getTopRight(find.byKey(const Key('content-0')))
        .dx;

    await _swipeLeft(tester, 'row-0', -500);

    expect(ran, isEmpty);
    // 划到底只到「完全露出」为止：位移 = 两个钮宽 + 三段缝（含贴边那两段），
    // 不越界。
    final double s = CySwipeActionsRow.spacing(_rowHeight);
    final double panelWidth =
        tester.getSize(find.byKey(const Key('swipe-action-share-0'))).width +
        tester.getSize(find.byKey(const Key('swipe-action-del-0'))).width +
        s * 3;
    expect(
      beforeDx - tester.getTopRight(find.byKey(const Key('content-0'))).dx,
      moreOrLessEquals(panelWidth, epsilon: 0.5),
    );
  });

  testWidgets('点动作 → 执行一次并收起面板', (WidgetTester tester) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', destructive: true, onTap: ran.add),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -200);

    await tester.tap(find.byKey(const Key('swipe-action-del-0')));
    await tester.pumpAndSettle();

    expect(ran, <String>['del-0']);
    expect(find.byKey(const Key('swipe-action-del-0')), findsNothing);
  });

  testWidgets('禁用动作吞掉执行', (WidgetTester tester) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', onTap: ran.add, isEnabled: false),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -200);
    await tester.tap(find.byKey(const Key('swipe-action-del-0')));
    await tester.pumpAndSettle();
    expect(ran, isEmpty);
  });

  testWidgets('整行禁用 → 根本滑不开', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        enabled: false,
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -200);
    expect(find.byKey(const Key('swipe-action-del-0')), findsNothing);
  });

  testWidgets('performsFirstActionWithFullSwipe=true 时划到底执行贴边那个', (
    WidgetTester tester,
  ) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('share-$k', onTap: ran.add),
          _action('del-$k', destructive: true, onTap: ran.add),
        ],
        leading: (String _) => const <CyContextualAction>[],
        performsFirstActionWithFullSwipe: true,
      ),
    );
    await tester.pumpAndSettle();

    await _swipeLeft(tester, 'row-0', -500);
    expect(ran, <String>['del-0']);
  });

  testWidgets('★ 同一时刻只开一行', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        rows: 2,
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();

    await _swipeLeft(tester, 'row-0', -200);
    expect(find.byKey(const Key('swipe-action-del-0')), findsOneWidget);

    await _swipeLeft(tester, 'row-1', -200);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swipe-action-del-1')), findsOneWidget);
    expect(find.byKey(const Key('swipe-action-del-0')), findsNothing);
  });

  testWidgets('右滑露 leading 动作，靠左贴边', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        trailing: (String _) => const <CyContextualAction>[],
        leading: (String k) => <CyContextualAction>[_action('pin-$k')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('row-0')),
      const Offset(200, 0),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('swipe-action-pin-0')), findsOneWidget);
    // 贴边缝 = spacing（实测与钮间距同值），不是 0。
    expect(
      tester.getTopLeft(find.byKey(const Key('swipe-action-pin-0'))).dx,
      moreOrLessEquals(CySwipeActionsRow.spacing(_rowHeight), epsilon: 0.5),
    );
  });

  testWidgets('★ 钮形按实测两档走：高行正圆、矮行胶囊', (WidgetTester tester) async {
    // 高行（≥ ~79pt）→ 钮高封顶 50.67，宽=高 → 正圆。文案短到不参与撑宽。
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', label: '删', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -200);

    final Size tall = tester.getSize(
      find.byKey(const Key('swipe-action-surface-del-0')),
    );
    expect(
      tall.width,
      moreOrLessEquals(CyContextualAction.circleSide, epsilon: 0.6),
    );
    expect(
      tall.height,
      moreOrLessEquals(CyContextualAction.circleSide, epsilon: 0.6),
    );
    expect(
      (tester
                  .widget<DecoratedBox>(
                    find.byKey(const Key('swipe-action-surface-del-0')),
                  )
                  .decoration
              as BoxDecoration)
          .borderRadius,
      BorderRadius.circular(tall.height / 2),
    );
    await tester.pumpWidget(const SizedBox());

    // 矮行（实测 62pt 那档）→ 钮高 33.33、宽 60 的胶囊。
    await tester.pumpWidget(
      _Harness(
        rowHeight: 62,
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', label: '删', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -200);
    final Size short = tester.getSize(
      find.byKey(const Key('swipe-action-surface-del-0')),
    );
    expect(
      short.height,
      moreOrLessEquals(62 - CyContextualAction.heightBudgetLoss, epsilon: 0.6),
    );
    expect(
      short.width,
      moreOrLessEquals(
        short.height + CyContextualAction.pillStretch,
        epsilon: 0.6,
      ),
    );
    // 矮行那档的缝是 10，不是高行的 10.67。
    expect(
      CySwipeActionsRow.panelWidth(
        <CyContextualAction>[_action('del')],
        rowHeight: 62,
        rowWidth: _screenWidth,
      ),
      moreOrLessEquals(
        short.width + CySwipeActionsRow.spacing(62) * 2,
        epsilon: 0.6,
      ),
    );
  });

  testWidgets('动作钮保持 44pt 触达区，破坏性动作用系统语义红', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -200);

    final Finder action = find.byKey(const Key('swipe-action-del-0'));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSize(action).width,
      greaterThanOrEqualTo(CyContextualAction.circleSide),
    );

    final DecoratedBox box = tester.widget<DecoratedBox>(
      find.byKey(const Key('swipe-action-surface-del-0')),
    );
    expect(
      box.decoration,
      isA<BoxDecoration>().having(
        (BoxDecoration d) => d.color,
        'color',
        CupertinoColors.systemRed.resolveFrom(tester.element(action)),
      ),
    );
  });

  testWidgets('★ 收起时动作仍以 accessibility custom action 暴露', (
    WidgetTester tester,
  ) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action(
            'del-$k',
            destructive: true,
            onTap: ran.add,
            semanticLabel: '取消收藏静安',
          ),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();

    final SemanticsHandle handle = tester.ensureSemantics();
    // customSemanticsActions 只在 SemanticsProperties 上可读（不随
    // SemanticsData 出树），这里验的是组件确实挂上了它 —— 出树那一段
    // 由 Flutter 自己负责。
    final Semantics semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const Key('row-0')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      semantics.properties.customSemanticsActions?.keys.map(
        (CustomSemanticsAction a) => a.label,
      ),
      contains('取消收藏静安'),
    );
    handle.dispose();

    // 无障碍动作可以直接触发执行（不必先展开）。
    final CustomSemanticsAction act =
        semantics.properties.customSemanticsActions!.keys.first;
    semantics.properties.customSemanticsActions![act]!();
    await tester.pumpAndSettle();
    expect(ran, <String>['del-0']);
  });

  testWidgets('★ 展开期间行内容让位给动作（iOS：滑开的那一行不能直接点进）', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('del-$k', destructive: true),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();

    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpAndSettle();
    final Finder content = find.bySemanticsLabel('内容 0');
    expect(
      tester
          .getSemantics(content)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await _swipeLeft(tester, 'row-0', -200);
    expect(
      tester
          .getSemantics(content)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('一侧最多 3 个动作', (WidgetTester tester) async {
    expect(
      () => CySwipeActionsRow(
        rowKey: 'a',
        openKey: null,
        onOpenChanged: (_) {},
        trailing: <CyContextualAction>[
          _action('1'),
          _action('2'),
          _action('3'),
          _action('4'),
        ],
        child: const SizedBox(),
      ),
      throwsAssertionError,
    );
  });

  testWidgets('长文案：正圆档不加宽（溢出照排），胶囊档按文案撑宽', (WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        trailing: (String k) => <CyContextualAction>[
          _action('short-$k', label: '删'),
          _action('long-$k', label: '取消收藏这个主题名称很长'),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -600);

    final double shortW = tester
        .getSize(find.byKey(const Key('swipe-action-short-0')))
        .width;
    final double longW = tester
        .getSize(find.byKey(const Key('swipe-action-long-0')))
        .width;
    // 实测系统：142pt 行里 4 字文案（advance 52 > 50.67）钮仍是正圆，
    // 文案溢出到圆外 —— 所以正圆档两个钮等宽，长文案不撑宽。
    expect(
      shortW,
      moreOrLessEquals(CyContextualAction.circleSide, epsilon: 0.6),
    );
    expect(longW, moreOrLessEquals(shortW, epsilon: 0.01));
    final double longLabelW = tester.getSize(find.text('取消收藏这个主题名称很长')).width;
    expect(longLabelW, greaterThan(longW));
    // 面板整体不出行宽（越界会让钮被裁掉）。
    final double rightEdge = tester
        .getRect(find.byKey(const Key('swipe-action-long-0')))
        .right;
    expect(rightEdge, lessThanOrEqualTo(_screenWidth + 0.01));

    await tester.pumpWidget(const SizedBox());

    // 矮行（胶囊档）：文案长过基础宽就把胶囊撑开。
    await tester.pumpWidget(
      _Harness(
        rowHeight: 62,
        trailing: (String k) => <CyContextualAction>[
          _action('c-$k', label: '删'),
          _action('d-$k', label: '取消收藏这个主题名称很长'),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -600);
    final double pillBase = tester
        .getSize(find.byKey(const Key('swipe-action-c-0')))
        .width;
    final double pillLong = tester
        .getSize(find.byKey(const Key('swipe-action-d-0')))
        .width;
    expect(
      pillBase,
      moreOrLessEquals(
        CySwipeActionsRow.pillHeight(62) + CyContextualAction.pillStretch,
        epsilon: 0.6,
      ),
    );
    expect(pillLong, greaterThan(pillBase));

    await tester.pumpWidget(const SizedBox());

    // 行宽挤得过窄时按行宽分：钮不低于基础宽，面板最多就是整行。
    await tester.pumpWidget(
      _Harness(
        rowHeight: 62,
        rowWidth: 150,
        trailing: (String k) => <CyContextualAction>[
          _action('a-$k', label: '取消收藏这个主题名称很长'),
          _action('b-$k', label: '取消收藏这个主题名称很长'),
        ],
        leading: (String _) => const <CyContextualAction>[],
      ),
    );
    await tester.pumpAndSettle();
    await _swipeLeft(tester, 'row-0', -600);
    final double capped = tester
        .getSize(find.byKey(const Key('swipe-action-a-0')))
        .width;
    final double s = CySwipeActionsRow.spacing(62);
    // 挤到只剩行宽可分：两个钮 + 三段缝 = 整行，且不低于基础宽（胶囊档）。
    expect(capped * 2 + s * 3, moreOrLessEquals(150, epsilon: 0.6));
    expect(
      capped,
      greaterThanOrEqualTo(
        CySwipeActionsRow.pillHeight(62) + CyContextualAction.pillStretch,
      ),
    );
    expect(
      CySwipeActionsRow.panelWidth(
        <CyContextualAction>[
          _action('a', label: '取消收藏这个主题名称很长'),
          _action('b', label: '取消收藏这个主题名称很长'),
        ],
        rowHeight: 62,
        rowWidth: 150,
      ),
      moreOrLessEquals(150, epsilon: 0.6),
    );
  });
}
