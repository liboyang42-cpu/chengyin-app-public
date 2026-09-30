import 'package:flutter/cupertino.dart';

import '../../../core/theme/cy_tokens.dart';

/// v5.1 半屏那批玩法组件共用的几件小部件(眉标 / 标题 / 波形 / 时间)。
///
/// 为什么单独立一个文件:blindTaste / musicCorner / slowTask 从
/// `advanced_playkit_view.dart` 的内联方法升成独立组件之后,这几件被三个文件
/// 同时要用 —— 留在原文件里就得把私有类复制三份。
///
/// 真源共用层里还有一枚 `.pk-pill`(音乐角右上角那枚「到点」),App 侧**没有**
/// 对应实现:真源那一枚挂在 `wx:if="{{arrived}}"` 上,而 `arrived` 这个属性
/// 两端都没有产生方(页面组装 kit 时不喂)—— 没数据源的徽标等于替服务端宣布
/// 了一件它没说过的事,所以整枚不搬。
///
/// 颜色一律走 [CyTokens]:玩家域**恒暗**(D6③),`CyPalette` 是给会随外观翻转的
/// 页面用的,这两条路不混。
class PlayKitEyebrow extends StatelessWidget {
  const PlayKitEyebrow(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: CyTokens.textSecondary,
      fontSize: CyTokens.typeLabel,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  );
}

class PlayKitTitle extends StatelessWidget {
  const PlayKitTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: CyTokens.textPrimary,
      fontSize: CyTokens.typeSectionTitle,
      fontWeight: FontWeight.w700,
      height: CyTokens.leadingTight,
    ),
  );
}

/// 秒 → `M:SS`。歌曲长度不会到小时(真源 `playkit-musiccorner/index.js#formatTime`)。
String playKitFormatTime(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  final int minutes = safe ~/ 60;
  final int remainder = safe % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

/// 音乐角的波形条。高度是**照抄**真源稿的 17 根,不随机 ——
/// 随机波形每次重渲染都在抖(真源 `playkit-musiccorner/index.js` 的 `BAR_HEIGHTS`)。
class PlayKitWaveform extends StatelessWidget {
  const PlayKitWaveform({super.key, required this.progress});

  final double progress;

  static const List<double> barHeights = <double>[
    16,
    38,
    60,
    30,
    52,
    22,
    44,
    66,
    36,
    58,
    28,
    50,
    20,
    42,
    64,
    34,
    24,
  ];

  @override
  Widget build(BuildContext context) {
    // 点亮几根:0 时一根不亮,播完全亮(真源 `litBarCount`)。
    final int lit = (progress.clamp(0, 1) * barHeights.length).round();
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (int index = 0; index < barHeights.length; index++)
            Expanded(
              child: Center(
                child: Container(
                  width: 3,
                  // 真源的 17 根高到 66rpx(=33pt),这里按同一比例收到 38pt 的盒子里。
                  height: barHeights[index] * 0.55,
                  decoration: BoxDecoration(
                    color: index < lit
                        ? CyTokens.playKitMusic
                        : CyTokens.borderStrong,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
