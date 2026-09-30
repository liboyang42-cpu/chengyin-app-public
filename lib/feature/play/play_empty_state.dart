import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;

import '../../core/network/dio_client.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../data/api/play_api.dart';
import '../../data/models/checkin_models.dart';

/// 游玩首屏的**空态引导**体系 —— 对齐小程序 `pages/play/index` 的 `emptyKind`。
///
/// 真源在 `loadData` 里按固定顺序落 6 种态,每一种只留**真走得通**的出口:
/// 缺场次参数时「重新加载」是死按钮(重试必然命中同一行 return),所以那一支
/// 只给「返回活动详情」。把 402(没有自玩通行证)混进「未报名」也是错的 ——
/// 自玩根本没有报名这个动作(真源 C-26 注释,`index.js:2801-2805`)。

/// `emptyKind` 取值,名字与真源一致。
enum PlayEmptyKind { missing, needPass, auth, error, signup, empty }

/// 后端「没有(或已过期)自玩通行证」的业务码。
/// `ApiPlayProgressController.java:343` → `new AjaxResult(402, "请先购买自玩通行证")`。
const int kPlayNeedPassCode = 402;

@immutable
class PlayEmptyGuide {
  const PlayEmptyGuide({required this.kind, required this.tip});

  final PlayEmptyKind kind;
  final String tip;
}

/// 缺参:`pages/play/index.js:2828`。
const PlayEmptyGuide kPlayMissingSessionGuide = PlayEmptyGuide(
  kind: PlayEmptyKind.missing,
  tip: '场次信息缺失，请从票夹或路线详情进入',
);

/// 首屏拉数失败的分类。判定顺序与文案 1:1 抄 `pages/play/index.js:2830-2843`。
///
/// ★ 402 只认**业务码**(回包 `code==402`)。HTTP 状态异常的 402 会走
///   [DioException] 落 error —— 与真源 `successStatusAbnormal` 强制覆盖
///   body.code 的口径一致(`tests/unit/play-request-recovery.test.js:71-85` 钉这条)。
PlayEmptyGuide classifyPlayNodesFailure(Object error) {
  if (error case PlayException(
    message: final String message,
    code: final int? code,
  )) {
    final String msg = message.trim();
    if (code == kPlayNeedPassCode) {
      return PlayEmptyGuide(
        kind: PlayEmptyKind.needPass,
        tip: msg.isEmpty ? '请先购买自玩通行证后再开始' : msg,
      );
    }
    // 真源按 msg 里的「登录/认证」认登录态(这条链的 401 是回包码,不是 HTTP 状态)。
    if (msg.contains('登录') || msg.contains('认证')) {
      return const PlayEmptyGuide(kind: PlayEmptyKind.auth, tip: '登录已过期，请重新登录');
    }
    return PlayEmptyGuide(
      kind: PlayEmptyKind.error,
      tip: msg.isEmpty ? '加载失败，请稍后重试' : msg,
    );
  }
  if (isUnauthorizedError(error)) {
    return const PlayEmptyGuide(kind: PlayEmptyKind.auth, tip: '登录已过期，请重新登录');
  }
  if (error is DioException) {
    // 断网/超时/状态异常:真源 `.catch` 落「加载失败,请稍后重试」+「重新加载」。
    return const PlayEmptyGuide(kind: PlayEmptyKind.error, tip: '加载失败，请稍后重试');
  }
  // 回包形状不对(拿不到节点列表):`PlayApi._nodesResult` 抛的就是这一句。
  return const PlayEmptyGuide(
    kind: PlayEmptyKind.error,
    tip: kPlayRouteShapeBrokenTip,
  );
}

/// 回包成功但要落空态的两种:`registered === false`(未报名)与节点列表为空。
/// 顺序同真源(`index.js:2846-2852`)—— 未报名优先,别让人以为路线没配。
PlayEmptyGuide? classifyPlayNodesResult(PlayNodesResult result) {
  if (result.registered == false) {
    return const PlayEmptyGuide(kind: PlayEmptyKind.signup, tip: '你还没有报名这个场次');
  }
  if (result.nodes.isEmpty) {
    return const PlayEmptyGuide(
      kind: PlayEmptyKind.empty,
      tip: '本场路线节点还在配置中，请稍后查看',
    );
  }
  return null;
}

/// 空态卡:一句「为什么这一屏没有内容」+ 该态唯一的出路。
///
/// 对应真源 `.play-empty-card`(`pages/play/index.wxss:496-498`):整屏居中的
/// 内容卡,主文案 + 至多一主一次两个按钮。**没有**「重新加载」的态就是
/// 重试救不回来的态,别摆一个按下去只会回到同一屏的假按钮。
class PlayEmptyGuideView extends StatelessWidget {
  const PlayEmptyGuideView({
    super.key,
    required this.guide,
    this.onReload,
    this.onBackDetail,
    this.onGetPass,
    this.onRelogin,
  });

  final PlayEmptyGuide guide;

  /// 「重新加载」—— 只有 [PlayEmptyKind.error] 给。
  final VoidCallback? onReload;

  /// 「返回活动详情」/「返回」:有栈 pop,没栈回票夹(真源 `goBackDetail`)。
  final VoidCallback? onBackDetail;

  /// 「获取通行证」:去主题详情买通行证(真源 `goGetPass`)。
  final VoidCallback? onGetPass;

  /// 「重新登录」:就地登录,成功后重拉首屏(真源 `doRelogin`)。
  final VoidCallback? onRelogin;

  List<
    ({String label, Key key, VoidCallback? onPressed, CyNativeButtonRole role})
  >
  get _actions {
    final back = (
      label: '返回活动详情',
      key: const Key('play-empty-back'),
      onPressed: onBackDetail,
      role: CyNativeButtonRole.secondary,
    );
    return switch (guide.kind) {
      PlayEmptyKind.signup =>
        <
          ({
            String label,
            Key key,
            VoidCallback? onPressed,
            CyNativeButtonRole role,
          })
        >[
          (
            label: '去报名',
            key: const Key('play-empty-signup'),
            onPressed: onBackDetail,
            role: CyNativeButtonRole.primary,
          ),
        ],
      PlayEmptyKind.auth =>
        <
          ({
            String label,
            Key key,
            VoidCallback? onPressed,
            CyNativeButtonRole role,
          })
        >[
          (
            label: '重新登录',
            key: const Key('play-empty-relogin'),
            onPressed: onRelogin,
            role: CyNativeButtonRole.primary,
          ),
        ],
      PlayEmptyKind.error =>
        <
          ({
            String label,
            Key key,
            VoidCallback? onPressed,
            CyNativeButtonRole role,
          })
        >[
          (
            label: '重新加载',
            key: const Key('play-empty-reload'),
            onPressed: onReload,
            role: CyNativeButtonRole.primary,
          ),
          back,
        ],
      PlayEmptyKind.missing =>
        <
          ({
            String label,
            Key key,
            VoidCallback? onPressed,
            CyNativeButtonRole role,
          })
        >[
          (
            label: '返回活动详情',
            key: const Key('play-empty-back'),
            onPressed: onBackDetail,
            role: CyNativeButtonRole.primary,
          ),
        ],
      PlayEmptyKind.needPass =>
        <
          ({
            String label,
            Key key,
            VoidCallback? onPressed,
            CyNativeButtonRole role,
          })
        >[
          (
            label: '获取通行证',
            key: const Key('play-empty-pass'),
            onPressed: onGetPass,
            role: CyNativeButtonRole.primary,
          ),
        ],
      PlayEmptyKind.empty =>
        <
          ({
            String label,
            Key key,
            VoidCallback? onPressed,
            CyNativeButtonRole role,
          })
        >[
          (
            label: '返回',
            key: const Key('play-empty-back'),
            onPressed: onBackDetail,
            role: CyNativeButtonRole.secondary,
          ),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final List<Widget> actions = <Widget>[];
    for (final action in _actions) {
      // 出路本身不可用时不画按钮 —— 按不动的出路比没有出路更坏。
      if (action.onPressed == null) continue;
      if (actions.isNotEmpty) {
        actions.add(const SizedBox(height: CyTokens.space3));
      }
      actions.add(
        CyNativeButton(
          key: action.key,
          label: action.label,
          role: action.role,
          width: double.infinity,
          onPressed: action.onPressed,
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              container: true,
              liveRegion: true,
              label: guide.tip,
              child: ExcludeSemantics(
                child: Text(
                  guide.tip,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: CyTokens.typeBody,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space5),
              ...actions,
            ],
          ],
        ),
      ),
    );
  }
}
