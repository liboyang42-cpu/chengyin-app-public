import 'package:chengyin_app/feature/play/free_explore/story_lines.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/story_line_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester t, {
  required StoryLine line,
  bool shown = false,
  bool fromTop = false,
  Duration delay = Duration.zero,
  bool reduceMotion = false,
  Key? measureKey,
}) {
  return t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: SizedBox(
            width: 375,
            child: StoryLineView(
              line: line,
              shown: shown,
              fromTop: fromTop,
              delay: delay,
              measureKey: measureKey,
            ),
          ),
        ),
      ),
    ),
  );
}

double _opacity(WidgetTester t) => t
    .widget<Opacity>(
      find.descendant(
        of: find.byType(StoryLineView),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

Matrix4 _matrix(WidgetTester t) => t
    .widget<Transform>(
      find.descendant(
        of: find.byType(StoryLineView),
        matching: find.byType(Transform),
      ),
    )
    .transform;

void main() {
  const StoryTextLine text = StoryTextLine('p0', '巷口那家旧书店');
  const StoryTitleLine title = StoryTitleLine(
    'ttl',
    meta: '第 1 章',
    title: '旧书与唱片',
  );
  const StoryImageLine image = StoryImageLine('img', 'http://x/1.jpg');

  testWidgets('三形态各渲一次:正文 / 标题(眉标+题) / 图片', (WidgetTester t) async {
    await _pump(t, line: text);
    expect(find.text('巷口那家旧书店'), findsOneWidget);

    await _pump(t, line: title);
    expect(find.text('第 1 章'), findsOneWidget);
    expect(find.text('旧书与唱片'), findsOneWidget);

    await _pump(t, line: image);
    // 图片行也吃同一套显形动效 —— 它必须被同样的 Opacity/Transform 包住。
    expect(find.byType(Opacity), findsOneWidget);
    expect(find.byType(Transform), findsOneWidget);
  });

  testWidgets('★未显形:opacity 0、下移一行、缩到 .78', (WidgetTester t) async {
    await _pump(t, line: text);
    expect(_opacity(t), 0);
    final Matrix4 m = _matrix(t);
    expect(m.getTranslation().y, closeTo(kStoryLineShift, 0.001));
    expect(m.entry(0, 0), closeTo(kStoryLineScale, 0.001));
  });

  testWidgets('★fromTop:向上滚时字从上方落下来 —— 位移取负', (WidgetTester t) async {
    await _pump(t, line: text, fromTop: true);
    expect(_matrix(t).getTranslation().y, closeTo(-kStoryLineShift, 0.001));
  });

  testWidgets('★显形后:opacity 1、位移归零、缩放归一', (WidgetTester t) async {
    await _pump(t, line: text);
    await _pump(t, line: text, shown: true);
    await t.pumpAndSettle();
    expect(_opacity(t), 1);
    final Matrix4 m = _matrix(t);
    expect(m.getTranslation().y, closeTo(0, 0.001));
    expect(m.entry(0, 0), closeTo(1, 0.001));
  });

  testWidgets('★transform 带回弹:中途会冲过目标位(scale > 1)', (WidgetTester t) async {
    await _pump(t, line: text);
    await _pump(t, line: text, shown: true);
    // cubic-bezier(.34,1.46,.5,1) 在 .5s 里先冲过头再回来;取靠后的一帧看过冲。
    await t.pump(const Duration(milliseconds: 330));
    expect(
      _matrix(t).entry(0, 0),
      greaterThan(1),
      reason: '换成 easeOut 就没有回弹了,那正是样机手感的来源',
    );
  });

  testWidgets('★delay 期间原地不动 —— 同批错开靠它', (WidgetTester t) async {
    const Duration delay = Duration(milliseconds: 150);
    await _pump(t, line: text, delay: delay);
    await _pump(t, line: text, shown: true, delay: delay);
    await t.pump(const Duration(milliseconds: 140));
    expect(_opacity(t), 0, reason: '延迟没生效的话这一行会跟第一行同时亮');
    expect(_matrix(t).getTranslation().y, closeTo(kStoryLineShift, 0.001));
    // 延迟过后照常走完 500ms
    await t.pump(const Duration(milliseconds: 520));
    expect(_opacity(t), 1);
  });

  testWidgets('★段距不进被缩放的盒子 —— 行只有自己那点高度', (WidgetTester t) async {
    // CSS 的 margin 在 transform 之外。把 200pt 段距塞进被 scale(.78) 的盒子里,
    // 字会绕着「文字 + 空白」的中心缩、往下掉一截;页面按 `.st-line` 的矩形量显形
    // 时机(index.js:1112)也会低 100pt,整屏显形整体偏晚一档。
    await _pump(t, line: text);
    expect(
      t.getSize(find.byType(StoryLineView)).height,
      closeTo(kStoryLineFontSize * kStoryLineHeight, 0.5),
      reason: '行的高度必须只有一行字 —— 段距归页面铺',
    );
    expect(storyLineGap(text), kStoryParaGap);
    expect(storyLineGap(title), kStoryTitleGap);
  });

  testWidgets('★measureKey 挂在 Transform 内侧 —— 量到的必须是变形后的矩形', (
    WidgetTester t,
  ) async {
    final GlobalKey k = GlobalKey();
    await _pump(t, line: text, measureKey: k);
    // 页面就是拿这个锚点算显形时机的(chapter_story_page.dart `_settle`)。
    // 样机量的是 `boundingClientRect()` —— 应用了 translateY(1.95em) scale(.78)
    // 之后的矩形;挂在 Transform 外侧只能拿到未变形的布局矩形。
    final RenderBox ro = k.currentContext!.findRenderObject()! as RenderBox;
    final Rect visual = MatrixUtils.transformRect(
      ro.getTransformTo(null),
      Offset.zero & ro.size,
    );
    final Rect layout = t.getRect(find.byType(StoryLineView));
    expect(
      visual.center.dy - layout.center.dy,
      closeTo(kStoryLineShift, 0.5),
      reason: '锚点在 Transform 外侧的话这里恒等于 0,整屏会早一整行就点亮',
    );
    expect(
      visual.height / layout.height,
      closeTo(kStoryLineScale, 0.01),
      reason: '高度也得是缩放后的 —— 判据量的是行的中点',
    );
  });

  testWidgets('★降低动态下没有 transform,锚点照样在(否则整屏永远量不到)', (
    WidgetTester t,
  ) async {
    final GlobalKey k = GlobalKey();
    await _pump(t, line: text, measureKey: k, reduceMotion: true);
    final RenderBox ro = k.currentContext!.findRenderObject()! as RenderBox;
    final Rect visual = MatrixUtils.transformRect(
      ro.getTransformTo(null),
      Offset.zero & ro.size,
    );
    expect(visual, t.getRect(find.byType(StoryLineView)));
  });

  testWidgets('★降低动态:行恒常显形,不套 Opacity/Transform', (WidgetTester t) async {
    await _pump(t, line: text, reduceMotion: true);
    expect(find.text('巷口那家旧书店'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StoryLineView),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: '降级只「不给过渡」的话,未显形的行会停在 opacity:0,字永远不出现',
    );
  });
}
