import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../core/theme/cy_tokens.dart';
import 'fullscreen/playkit_step_row.dart';
import 'playkit_projection.dart';
import 'playkit_sheet_parts.dart';

/// `blindTaste`(闭眼味觉师 · 盲品)的专属组件。
///
/// 真源 = 小程序 `pages/play/components/playkit-blindtaste/`:
/// - `index.wxml`:眉标 + 标题 + 猫向导 + **图标步骤行** + 选项 + 脚注(hint / XP);
/// - `index.js`:点中哪一项就是作答 —— 只有 `answer` 一个事件,**不本地判对错**
///   (「对错是服务端的事,前端自己判就等于把答案发到客户端」)。
///
/// 图标步骤行的读屏文案照真源保留:`stepsA11y` 是图形化的代价,
/// 丢掉就是让读屏用户听不到步骤。
class PlayKitBlindTasteView extends StatelessWidget {
  const PlayKitBlindTasteView({
    super.key,
    required this.card,
    required this.enabled,
    this.acting = false,
    this.onAction,
  });

  final PlayKitCard card;
  final bool enabled;
  final bool acting;
  final ValueChanged<PlayKitAction>? onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      PlayKitEyebrow(card.eyebrow),
      const SizedBox(height: CyTokens.space2),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: PlayKitTitle(card.title)),
          const SizedBox(width: CyTokens.space2),
          // 真源 `cy-mascot mode="blindfold" size="192"`(rpx,1rpx=0.5pt):
          // 盒宽 96pt,高按 mascot 契约 110/120 等比 = 88pt。
          // 此前是 72pt 占位盘 + eye_slash_fill 图标,现按真源素材几何上屏。
          const _BlindfoldMascot(),
        ],
      ),
      const SizedBox(height: CyTokens.space4),
      // 图标步骤行与 `cy-playkit-steps` 同源(真源 `utils/playkit-steps.js`)
      PlayKitStepRow(
        kind: PlayKitKind.blindTaste,
        a11yLabel: '玩法步骤：${card.stepsA11y}',
      ),
      const SizedBox(height: CyTokens.space4),
      for (final PlayKitAction choice in card.choices) ...<Widget>[
        _BlindOption(
          action: choice,
          selected: card.selectedKey == '${choice.payload['key']}',
          enabled: enabled && !acting && !card.complete,
          onPressed: () => onAction?.call(choice),
        ),
        const SizedBox(height: CyTokens.space2),
      ],
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              card.hint,
              // 真源 `.pk-foot__hint`:label 档 + tertiary(比正文说明再降一档,
              // 收尾旁白不该和选项抢注意力)。
              style: const TextStyle(
                color: CyTokens.textTertiary,
                fontSize: CyTokens.typeLabel,
                height: CyTokens.leadingNormal,
              ),
            ),
          ),
          if (card.rewardLabel.isNotEmpty) ...<Widget>[
            const SizedBox(width: CyTokens.space2),
            Text(
              card.rewardLabel,
              // 真源 `.pk-foot__xp` → `.bt .pk-foot__xp`:caption + 斜体 +
              // `--cy-color-playkit-taste`(茶汤绿)。真源注释:XP 走玩法主题色,
              // 「不再借 status-info(那是"信息"语义)」。
              // w900 按手册 T3 封顶在 w700。
              style: const TextStyle(
                color: CyTokens.playKitTaste,
                fontSize: CyTokens.typeCaption,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

class _BlindOption extends StatelessWidget {
  const _BlindOption({
    required this.action,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final PlayKitAction action;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final String key = '${action.payload['key']}';
    // 真源 `.pk-option`:常态是「`--cy-color-play-surface-subtle`(#111)软底
    // + rgba(255,255,255,.14) 描边 + 14rpx 圆角」的卡。App 半屏页底是
    // `bgPage`(#000),此前选项用同色底 = 行悬在黑上、没有卡的轮廓 ——
    // 补 `bgSurfaceSubtle`(#141416)还原真源的卡底。
    // 选中态走**玩法主题色**:真源 `playkit-blindtaste/index.wxss` 以 `.bt`
    // 作用域覆盖共用层 —— `.pk-option--on` 描边/软底(rgba(51,199,115,.14))
    // 与 `.pk-option--on .pk-option__key` 描边+字色都是
    // `--cy-color-playkit-taste`(茶汤绿),「不再借 status-info(那是"信息"语义)」。
    // 禁用必须有呈现(CupertinoButton 只下 `onPressed:null` 不会变暗,
    // 与同族 `PlayKitStageButton` busy 0.55 同一契约)。
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: '选择 $key ${action.label}',
        child: ExcludeSemantics(
          child: CupertinoButton(
            key: Key('playkit-blind-option-$key'),
            minimumSize: const Size.fromHeight(56),
            padding: EdgeInsets.zero,
            onPressed: enabled ? onPressed : null,
            // 真源 `.pk-option` 的底与描边是同一个盒(`surface-subtle` 底 +
            // 1rpx `play-line` 描边 + radius-md),`--on` 两处一起转
            // playkit-taste。CupertinoButton 的 `color` 只能画底、画不了描边,
            // 所以底/描边一起挂在这个 child 上(此前只有底 → 未选中行
            // 在黑页底上看不出卡轮廓)。
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
              decoration: BoxDecoration(
                color: selected
                    ? CyTokens.playKitTaste.withValues(alpha: 0.14)
                    : CyTokens.bgSurfaceSubtle,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                border: Border.all(
                  color: selected
                      ? CyTokens.playKitTaste
                      : CyTokens.borderStrong,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: <Widget>[
                  // 真源 `.pk-option__key` = 48rpx(24pt)圆。
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                      border: Border.all(
                        color: selected
                            ? CyTokens.playKitTaste
                            : CyTokens.borderStrong,
                      ),
                    ),
                    child: Text(
                      key,
                      // 真源 `.pk-option__key`:caption 档 w900 → 手册封顶 w700。
                      style: TextStyle(
                        color: selected
                            ? CyTokens.playKitTaste
                            : CyTokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space3),
                  Expanded(
                    child: Text(
                      action.label,
                      // 真源 `.pk-option__label`:body 档 **w700**(不是 900,
                      // 原稿就写死 700),此前落成 w600 低一档。
                      style: const TextStyle(
                        color: CyTokens.textPrimary,
                        fontSize: CyTokens.typeBody,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `cy-mascot mode="blindfold"` · 蒙眼猫向导(盲品挑战的身份图示)。
///
/// 真源 `pages/play/components/playkit-blindtaste/index.wxml:8`
/// (`<cy-mascot mode="blindfold" size="192" />`),组件契约在
/// `pages/play/components/mascot/index.js`:盒宽 192rpx,高按 `MASCOT_RATIO
/// = 110/120` 等比 = 176rpx;素材是 `/images/mascot-cat-blind.svg`
/// (Figma v5.1 node 45:261,wxss 注释:「图形走 Figma 导出的 SVG,不手绘」)。
/// App 侧照 `playkit_woodfish.dart` 对真源 SVG 的先例做法:同一组几何逐值
/// 绘制,不引 `flutter_svg`(AGENTS.md:新第三方包 Ask first)。
///
/// 真源 `<image aria-hidden="true">` —— 装饰件,「盲品」语义由标题承担。
/// 颜色是素材切图的固定美术值(猫白脸/墨线/系统红点缀);play 域恒暗
/// (D10① 玩家角色),不随主题翻转 —— 同 `_kWfInk` 先例。
class _BlindfoldMascot extends StatelessWidget {
  const _BlindfoldMascot();

  /// 192rpx / 176rpx(1rpx = 0.5pt)。
  static const double _boxW = 96;
  static const double _boxH = 88;

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: _boxW,
      height: _boxH,
      child: CustomPaint(painter: _BlindfoldMascotPainter()),
    ),
  );
}

class _BlindfoldMascotPainter extends CustomPainter {
  const _BlindfoldMascotPainter();

  /// `mascot-cat-blind.svg` 的 viewBox(97.6506×88.8949)。
  static const double _viewW = 97.6506;
  static const double _viewH = 88.8949;

  static const Color _ink = Color(0xFF0A0A0B); // SVG stroke/fill `#0A0A0B`
  static const Color _face = Color(0xFFFFFFFF); // SVG fill `white`
  static const Color _accent = Color(0xFFFF3B30); // SVG fill `#FF3B30`

  @override
  void paint(Canvas canvas, Size size) {
    // 真源 `<image mode="aspectFit">`:viewBox 等比适配进盒,居中。
    final double s = math.min(size.width / _viewW, size.height / _viewH);
    canvas.translate(
      (size.width - _viewW * s) / 2,
      (size.height - _viewH * s) / 2,
    );
    canvas.scale(s);

    // 双耳:白填 + 2.4 墨描边,画在脸之前(耳根被脸盖住,与 SVG 图层序一致)。
    final Path leftEar = _triangle(
      const Offset(29.1777, 26.3512),
      const Offset(12.9121, 22.8939),
      const Offset(24.0391, 10.5359),
    );
    final Path rightEar = _triangle(
      const Offset(82.5634, 14.704),
      const Offset(66.2979, 18.1614),
      const Offset(71.4364, 2.34603),
    );
    for (final Path ear in <Path>[leftEar, rightEar]) {
      canvas.drawPath(ear, _fill()..color = _face);
      canvas.drawPath(ear, _stroke(_ink, 2.4));
    }

    // 脸:椭圆 (12.6004,16.6953) 70.7998×61.1996,白填 + 2.8 墨描边。
    final Rect face = Rect.fromLTWH(12.6004, 16.6953, 70.7998, 61.1996);
    canvas.drawOval(face, _fill()..color = _face);
    canvas.drawOval(face, _stroke(_ink, 2.8));

    // 下颌红带(44.8×8 rx4)。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(25.6, 74.4949, 44.8, 8),
        const Radius.circular(4),
      ),
      _fill()..color = _accent,
    );
    // 蒙眼带(67.2×14.4 rx7.2)+ 右端结翅三角。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(14.4, 36.0949, 67.2, 14.4),
        const Radius.circular(7.2),
      ),
      _fill()..color = _ink,
    );
    canvas.drawPath(
      _triangle(
        const Offset(78.4, 32.0949),
        const Offset(86.8, 27.2452),
        const Offset(86.8, 36.9447),
      ),
      _fill()..color = _ink,
    );
    // 带下红色小尖(蒙眼带的「鼻子露出」记号)。
    canvas.drawPath(
      _triangle(
        const Offset(40, 52.0949),
        const Offset(36.5359, 47.2949),
        const Offset(43.4641, 47.2949),
      ),
      _fill()..color = _accent,
    );
    // 胡须 4 根(14.4×2 rx0.8):SVG `rotate(deg x y)` 绕矩形左上角,
    // 屏幕系顺时针为正 —— Flutter 同号直接映射。
    const List<(double, double, double)> whiskers = <(double, double, double)>[
      (6.4, 47.2949, -8),
      (6.4, 55.2949, 4),
      (83.2, 47.2949, 8),
      (83.2, 55.2949, -4),
    ];
    for (final (double x, double y, double deg) in whiskers) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(deg * math.pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 14.4, 2),
          const Radius.circular(0.8),
        ),
        _fill()..color = _ink,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BlindfoldMascotPainter oldDelegate) => false;

  static Paint _fill() => Paint()..style = PaintingStyle.fill;

  static Paint _stroke(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..color = color
    ..strokeWidth = width;

  static Path _triangle(Offset a, Offset b, Offset c) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..close();
}
