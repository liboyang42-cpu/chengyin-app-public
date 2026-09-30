// 故事流里的一行:三种形态共用同一套「由虚到实、由小到大、上浮一行、带一点回弹」的
// 进出场。精确值逐条照搬小程序 `.st-line`(pages/play/index.wxss:1652-1658)。

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_net_image.dart';
import '../story_lines.dart';

/// 正文字号 34rpx。
///
/// ★ 位移的 `em` 也按它算:样机把 `translateY(1.95em)` 写在 `.st-line` 上,
///   标题块与图片块都带这个基类、继承同一个字号 —— 三形态位移量必须一致,
///   否则同一批浮起来的行会参差不齐。
const double kStoryLineFontSize = 17;

/// `line-height:1.95`。
const double kStoryLineHeight = 1.95;

/// 未显形时的位移:`translateY(1.95em)` = 1.95 × 17。
const double kStoryLineShift = kStoryLineFontSize * kStoryLineHeight;

/// 未显形时的缩放:`scale(.78)`。
const double kStoryLineScale = 0.78;

/// `filter:blur(22rpx)`。样机注释:rpx→px 折半,22rpx ≈ 11px。
/// CSS `blur(<length>)` 的长度**就是高斯标准差**,与 Flutter 的 sigma 同义,直接取 11。
const double kStoryLineBlur = 11;

/// 三条过渡都是 `.5s`。
const Duration kStoryLineDuration = Duration(milliseconds: 500);

/// `cubic-bezier(.34,1.46,.5,1)` —— 第二个控制点 y=1.46 > 1,**会冲过头再回来**。
/// 这一点回弹就是样机手感的来源,换成 `Curves.easeOut` 就没了。
const Cubic kStoryLineCurve = Cubic(0.34, 1.46, 0.5, 1);

/// 正文左右各 96rpx。
///
/// ⚠️ 右侧那条是音乐键的通道,但**不能只加右边距** —— 居中排版单边加会把整段推偏,
///   所以两边一起收(样机注释原文)。
const double kStoryTextInset = 48;

/// 段距 400rpx。之所以这么大:让屏幕上**同时只有一段**,
/// 右下角那颗音乐键也因此不会被正文压住。
const double kStoryParaGap = 200;

/// 标题到第一段 260rpx —— 比段距近一档,它是这一段的抬头,不是独立一段。
const double kStoryTitleGap = 130;

/// 图片块:高 400rpx、左右各 40rpx。
const double kStoryImageHeight = 200;
const double kStoryImageInset = 20;

/// 这一行**之后**的段距。
///
/// ⚠️ **段距不画在行自己身上** —— CSS 里 `margin` 在 transform 之外,样机
///   `.st-line{ margin:0 96rpx 400rpx; transform:scale(.78) }` 缩的是文字那个盒子。
///   把 200pt 空白塞进被缩放的盒子里有两个后果,都是静默的:
///   ① `scale(.78)` 绕「文字 + 空白」的中心缩,字会往下掉一截;
///   ② 页面按 `.st-line` 的矩形量显形时机(index.js:1112 `cy = top + height/2 - box.top`),
///      量到的中心低 100pt,整屏显形整体偏晚一档。
///   所以段距由页面在两行之间铺,行只管自己那点内容。
double storyLineGap(StoryLine line) => switch (line) {
  StoryTitleLine() => kStoryTitleGap,
  StoryImageLine() => CyTokens.space5,
  StoryKitLine() => kStoryParaGap,
  StoryTextLine() => kStoryParaGap,
};

/// 一行的三形态 + 进出场。
///
/// [shown] 由页面按「停下来那一刻在不在屏内」算(见 `story_reveal.dart`);
/// [fromTop] 对应样机的 `from-top`:往上滚时字**从上方落下来**,方向跟着手走;
/// [delay] 是同一批错开的 50ms 步进 —— 一起亮就是整块淡入,不是一行一行浮起来。
class StoryLineView extends StatelessWidget {
  const StoryLineView({
    super.key,
    required this.line,
    required this.shown,
    required this.fromTop,
    required this.delay,
    this.measureKey,
    this.child,
  });

  final StoryLine line;
  final bool shown;
  final bool fromTop;
  final Duration delay;

  /// [StoryKitLine] 的内容由页面供给(玩法组件要挂会话控制器,不在纯分段里造)。
  /// 其余行型忽略它。
  final Widget? child;

  /// 页面量显形时机用的锚点。★ **挂在 [Transform] 的内侧**:样机量的是
  /// `boundingClientRect()`,那是**应用了 `translateY(1.95em) scale(.78)` 之后**的
  /// 矩形(index.wxss:1655)。挂在外侧只能拿到未变形的布局矩形,未显形的行会被判成
  /// 「已经进屏了」—— 整屏比样机早 33.15pt([kStoryLineShift])的滚动距离就点亮,
  /// 而出屏那一侧 transform 已归零、两端一致 ⇒ 样机「进得晚、出得准」的迟滞没了。
  final Key? measureKey;

  @override
  Widget build(BuildContext context) {
    final Widget content = switch (line) {
      StoryTitleLine(:final String? meta, :final String title) => _title(
        meta,
        title,
      ),
      StoryTextLine(:final String text) => _text(text),
      StoryImageLine(:final String url) => _image(url),
      StoryKitLine() => child ?? const SizedBox.shrink(),
    };

    // 降低动态:样机 `.play--reduced-motion .st-line{ transition:none; opacity:1;
    // transform:none; filter:none }` —— 行**恒常显形**。
    // ⚠️ 不能只是「不给过渡」:那样未显形的行会停在 opacity:0 上,字永远不出现。
    // 降级下没有 transform,布局矩形本身就是可见矩形 —— 锚点直接包住正文。
    if (MediaQuery.disableAnimationsOf(context)) {
      return KeyedSubtree(key: measureKey, child: content);
    }

    final Duration total = delay + kStoryLineDuration;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: shown ? 1 : 0),
      duration: total,
      // 曲线在 builder 里按属性分别取,这里只要一根匀速的时间轴。
      curve: Curves.linear,
      child: content,
      builder: (BuildContext context, double t, Widget? child) {
        // CSS `transition-delay`:前 delay 段原地不动,剩下的 500ms 才走各自的曲线。
        final double raw =
            ((t * total.inMicroseconds - delay.inMicroseconds) /
                    kStoryLineDuration.inMicroseconds)
                .clamp(0.0, 1.0);
        final double move = kStoryLineCurve.transform(raw); // 可能 > 1:回弹
        final double fade = Curves.ease.transform(raw);

        final double dy = (fromTop ? -kStoryLineShift : kStoryLineShift) *
            (1 - move);
        final double scale = kStoryLineScale + (1 - kStoryLineScale) * move;
        final double sigma = kStoryLineBlur * (1 - fade);

        Widget w = child!;
        if (sigma > 0.01) {
          w = ImageFiltered(
            // decal:模糊到边缘就淡出,别把边上的像素抹开 —— 那会在纯黑底上拖出一圈灰。
            imageFilter: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.decal,
            ),
            child: w,
          );
        }
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform(
            // CSS 是 `translateY(...) scale(...)`,原点默认在中心。
            transform: Matrix4.identity()
              ..translateByDouble(0, dy, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1),
            alignment: Alignment.center,
            // ★ 锚点在 Transform **里面**:页面要量的是变形之后的矩形。
            //   位置固定在这一层(不跟着 ImageFiltered 的有无来回搬),
            //   GlobalKey 才不会在模糊消失那一帧被当成换了位置。
            child: KeyedSubtree(key: measureKey, child: w),
          ),
        );
      },
    );
  }

  Widget _text(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kStoryTextInset),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: kStoryLineFontSize,
        height: kStoryLineHeight,
        color: CyTokens.textPrimary,
      ),
    ),
  );

  Widget _title(String? meta, String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kStoryTextInset),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (meta != null && meta.isNotEmpty)
          Text(
            meta,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: CyTokens.typeCaption,
              letterSpacing: 1.5, // 3rpx
              color: CyTokens.textTertiary,
            ),
          ),
        const SizedBox(height: CyTokens.space2),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: CyTokens.typePageTitle,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: CyTokens.textPrimary,
          ),
        ),
      ],
    ),
  );

  Widget _image(String url) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kStoryImageInset),
    child: CyNetImage(
      url,
      height: kStoryImageHeight,
      width: double.infinity,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
    ),
  );
}
