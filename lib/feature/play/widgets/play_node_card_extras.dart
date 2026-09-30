import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cy_tokens.dart';
import '../../../data/models/checkin_models.dart';
import '../play_session_controller.dart' show PlaySessionKey;

/// 节点卡上的**会话内附加物**。在小程序里它们都是 `pages/play/index.js` 的 page data:
/// * `woodfishCount` —— 木鱼计数,敲一下本地 +1,不落库、不参与结算(index.js:4745-4748);
/// * `sheet.node.aiScore` —— 照片回执带回的 AI 参考分(`_applyAiScore` 挂到节点上),
///   卡正开着这一站时同步一份,否则下次打开才看得到。
///
/// App 侧同款:由游玩页持有、卡片详情页读。**不进服务端模型** ——
/// 页面一走就没了,这正是真源的口径(计数「只在本次会话里累计,不落库」)。
class PlayNodeCardExtras extends ChangeNotifier {
  // 真源的 `woodfishCount` 是**一份全局数**(page data 只有一个标量,所有节点共享);
  // App 侧按节点各记一份(#173 口径)—— 节点卡是独立路由,全局数会敲完 A 站在 B 站
  // 头上看到「×20」这种来历不明的数。偏差只在「多站各敲各的」时可见,记录在案。
  final Map<int, int> _woodfish = <int, int>{};
  final Map<int, PlayAiScore> _aiScores = <int, PlayAiScore>{};

  /// 该节点敲过几下(没敲过 = 0)。
  int woodfishCount(int nodeId) => _woodfish[nodeId] ?? 0;

  /// 敲一下。**只加本地计数、不替玩家上报** —— 真源注释原文:
  /// 「前端不替它上报,也就没有『敲 1000 下刷分』这条路」。
  void knockWoodfish(int nodeId) {
    _woodfish[nodeId] = woodfishCount(nodeId) + 1;
    notifyListeners();
  }

  /// 该节点的 AI 参考分;服务端没给过就是 null(**没有占位分**)。
  PlayAiScore? aiScore(int nodeId) => _aiScores[nodeId];

  /// 照片回执带回了分就挂上。`PlayAiScore.fromJson` 已经把 `score <= 0` 判成 null,
  /// 这里不再判第二遍,也不许造一张 0 分的卡。
  void applyPhotoReceipt(int nodeId, PlayAiScore? score) {
    if (score == null) return;
    _aiScores[nodeId] = score;
    notifyListeners();
  }
}

/// 这次游玩里的节点卡附加物。与游玩会话同生命周期 —— **页面一走就没了**,
/// 所以它既不落库、也不该比这次会话活得久。
///
/// ⚠️ 宿主(游玩页)必须一直持有它:`ref.read` 不续命,autoDispose 会在
///    「卡片关掉、下一张还没开」的那一帧把它丢掉 —— 木鱼计数与刚拿到的
///    AI 参考分都会消失。真源这两项是 page data,同一个页面内**不重置**。
final playNodeCardExtrasProvider = Provider.autoDispose
    .family<PlayNodeCardExtras, PlaySessionKey>((Ref ref, PlaySessionKey key) {
      final PlayNodeCardExtras extras = PlayNodeCardExtras();
      ref.onDispose(extras.dispose);
      return extras;
    });

/// `cy-ai-score-card` · AI 参考分(Figma v5.1,node 47:319)。
///
/// 真源:`pages/play/components/ai-score-card/{index.wxml,index.wxss}`。
/// **纯展示、刻意不可点** —— 稿上写明「最终以商家审核为准」,做成可点会误导成
/// 「点了能申诉」。分数与评语都由服务端给,没给就不渲染这张卡(宿主判 [PlayAiScore?])。
///
/// 逐值对齐 wxss:88rpx 分数(44pt,斜体 900 → App 侧按手册收成 w700)、
/// micro 眉标、`play-accent-soft` 竖线、label 评语、micro 尾注。
class PlayAiScoreCard extends StatelessWidget {
  const PlayAiScoreCard({
    super.key,
    required this.score,
    this.label = 'AI 参考分',
  });

  final PlayAiScore score;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _kAiSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      // 真源描边是电子紫 3rpx;稿里这张卡就是紫的(不是可点走蓝,见真源 wxss 注)。
      border: Border.all(color: _kAiEdge, width: 1.5),
    ),
    child: Padding(
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${score.score}',
                style: const TextStyle(
                  color: _kAiEdge,
                  fontSize: _kAiScoreSize,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: CyTokens.space1),
              Text(
                label,
                style: const TextStyle(
                  color: CyTokens.textTertiary,
                  fontSize: CyTokens.typeMicro,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          Container(
            width: 1,
            height: 70,
            margin: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
            color: _kAiRule,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  score.comment,
                  style: const TextStyle(
                    color: CyTokens.textSecondary,
                    fontSize: CyTokens.typeLabel,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  score.note,
                  style: const TextStyle(
                    color: CyTokens.textTertiary,
                    fontSize: CyTokens.typeMicro,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 分数主视觉(真源 `.asc__score` 的 88rpx)—— 比 iOS 梯级的 Large Title(34)大一档,
/// 因为它是这张卡的**唯一**主视觉。
const double _kAiScoreSize = 44;

/// 逐值道具色(真源 `style/tokens.wxss`):电子紫 + 玩法暗底 + 14% 白竖线。
/// 这张卡恒为玩家暗色(道具语言),不跟主题翻转 —— 同先例 `playkit_stopwatch_view.dart`。
const Color _kAiEdge = Color(0xFFB06CFF); // --cy-color-playkit-ai
const Color _kAiSurface = Color(0xFF111111); // --cy-color-play-surface-subtle
const Color _kAiRule = Color(0x24FFFFFF); // --cy-color-play-accent-soft
