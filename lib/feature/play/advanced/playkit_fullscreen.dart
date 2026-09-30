import 'package:flutter/cupertino.dart';

import 'fullscreen/playkit_bingo_view.dart';
import 'fullscreen/playkit_silent_order_view.dart';
import 'fullscreen/playkit_predict_view.dart';
import 'fullscreen/playkit_quiz_views.dart';
import 'fullscreen/playkit_random_view.dart';
import 'fullscreen/playkit_prefab_views.dart';
import 'fullscreen/playkit_scan_view.dart';
import 'fullscreen/playkit_countdown_view.dart';
import 'fullscreen/playkit_daily_sign_view.dart';
import 'fullscreen/playkit_game_timer_view.dart';
import 'fullscreen/playkit_stickerbook_view.dart';
import 'fullscreen/playkit_timewindow_view.dart';
import 'fullscreen/playkit_stopwatch_view.dart';
import 'fullscreen/playkit_steps_view.dart';
import 'fullscreen/playkit_walk_view.dart';
import 'fullscreen/ball_shake_view.dart';
import 'fullscreen/coin_flip_view.dart';
import 'fullscreen/dice_roll_view.dart';
import 'fullscreen/quiet_hold_view.dart';
import 'fullscreen/reaction_view.dart';
import 'playkit_projection.dart';

/// 整屏族玩法(v5.2)的宿主缝。
///
/// 为什么与半屏那批 [AdvancedPlayKitView] 分开:小程序
/// `pages/play/components/playkit/index.js` 原文写着 ——
/// 「整屏那批…它们不是半屏 sheet ——『整屏就是判定区』『墙就是手机的四条边』
/// 『整屏被油盖住』压在半屏里全部不成立」。
/// 所以抛硬币 / 掷骰 / 反应 / 摇一摇 / 保持安静 / 倒计时 / 秒表这几个
/// **必须在整屏上呈现**,塞进半屏 sheet 会把判定区压没。
///
/// 其他批次的玩法(问答族 `qa` / `branch` / 竞猜等)也走这条缝 ——
/// 它们的原型同样是整屏。
///
/// ## 一个批次只做两件事
/// 1. 在 `lib/feature/play/advanced/fullscreen/` 下加自己的组件文件;
/// 2. 在 [kPlayKitFullscreenBuilders] **末尾追加**自己那几行。
///
/// ⚠️ 只追加、不重排。删任何既有行都要在 PR 说明里写清理由。
///
/// ## 结果一律由服务端定
/// 抛硬币 / 掷骰 / 倒计时到点这些的**结果服务端算**,客户端只是把它演出来 ——
/// 客户端的随机数玩家改得动,而这个玩法的结果直接对应任务。组件不加随机数,
/// 也不自己判断通过,只把 [PlayKitAction] 抛给宿主。
typedef PlayKitFullscreenBuilder =
    Widget Function(BuildContext context, PlayKitFullscreenContext data);

/// 整屏族从宿主拿到的全部东西。**只从这里取数据**,不要自己去读 provider。
@immutable
class PlayKitFullscreenContext {
  const PlayKitFullscreenContext({
    required this.card,
    required this.enabled,
    this.acting = false,
    this.onAction,
    this.onRefresh,
    this.onUploadPhoto,
  });

  /// 服务端投影。整屏族**不推算**通关、不补造成绩 —— 照 [PlayKitCard] 显示。
  final PlayKitCard card;

  /// 宿主正忙(上一次动作还没回来)时为 false,组件应禁用可点的东西。
  final bool enabled;

  final bool acting;

  /// 组件把玩家的选择抛回给页面;页面负责翻成 serverAction / serverPayload。
  final ValueChanged<PlayKitAction>? onAction;

  /// 让宿主**重新问一次服务端**(会话状态整份重取)。
  ///
  /// 只给「本地时钟走到了、但开门与否不由本地说了算」的那一处用:
  /// `timeWindow` 的倒计时归零(真源 `cy-playkit-timewindow` 到点发 `open` 事件,
  /// 组件注释写明意图是「由页面重新问服务端拿状态」——本地时钟不是权威,
  /// 改手机时间就能提前开门;小程序页面的 dispatch 其实没接这一条,见
  /// `playkit_timewindow_view.dart` 头注)。
  /// 没接这条的宿主给 null,组件照常只显示到点文案。
  final VoidCallback? onRefresh;

  /// 「只上传、不提交」的一条:建档头像是它唯一的用户 —— 组件抛来临时路径与
  /// 大小,宿主走与拍照族同一条链(双击锁 / 超限预检 / 版本守卫 / 失败实话),
  /// 成功回图片地址(头像在「提交登记」那一步才随 answers 一起走),
  /// 失败回 null(提示已由宿主给过,组件只把按钮放回原样)。
  /// 没接这条的宿主给 null,组件把头像位挡成不可点。
  final Future<String?> Function(Map<String, Object?> detail)? onUploadPhoto;
}

/// 整屏族的注册表。**只追加,不重排。**
///
/// 空表是合法状态:注册表里没有的 kind 走 [buildPlayKitFullscreen] 的回落,
/// 宿主应把它当「这个玩法 App 还没有」处理 —— 与小程序
/// 「名字不在这张表里就当它不存在」同口径,**不崩、不报错**。
final Map<PlayKitKind, PlayKitFullscreenBuilder>
kPlayKitFullscreenBuilders = <PlayKitKind, PlayKitFullscreenBuilder>{
  // ── 问答 / 判定族五屏(2026-09-17)────────────────────────────
  // 结果一律由服务端定:这五屏都不判对错、不算走向,只把玩家输入
  // 按服务端认的字段名抛回去(见 fullscreen/playkit_quiz_data.dart)。
  PlayKitKind.qa: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitQaView(data: data),
  PlayKitKind.branch: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitBranchView(data: data),
  PlayKitKind.estimate: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitEstimateView(data: data),
  PlayKitKind.pricePair:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitPricePairView(data: data),
  PlayKitKind.hiddenObject:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitHiddenView(data: data),
  // ── 计时/传感器族(2026-09-17 · feat/playkit-timers)──────────────────
  // 这三件的真源是 `cy-play-stage`(**整屏台面**),所以它们既在这里、
  // 也在 kFullscreenPlayKinds 里。
  PlayKitKind.countdown:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitCountdownView(data: data),
  PlayKitKind.stopwatch:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitStopwatchView(data: data),
  // walk 是**本地 kind**(不在服务端段名表里):步数只能从外面进来,
  // 默认那条路是「没有步数来源」的降级态,宿主接上来源后传 `steps:` 即可。
  PlayKitKind.walk: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitWalkView(data: data),
  // ⚠️ 这两件在小程序里是 **cy-sheet(半屏)**,不是整屏 ——
  // 所以它们刻意**没有**进 kFullscreenPlayKinds(那个集合的语义是
  // 「必须占满屏」)。登记在这里是因为这是仓内唯一一处
  // 「玩法 kind → 组件」的入口;宿主按 §3.4 S2/S3 用 sheet 呈现,
  // 系统自带 grabber 时把组件里的 `showGrabber` 关掉。
  PlayKitKind.gameTimer:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitGameTimerView(data: data),
  PlayKitKind.stickerBook:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitStickerBookView(data: data),
  // ── v5.2 整屏决定类五件套(只追加,不重排)──────────────────────
  // 抛硬币 / 掷骰子:结果由服务端定,组件只把动作抛出来;
  // 变色就点 / 弹球 / 安静挑战:开局先 START_CHALLENGE,成绩按服务器时间复核。
  PlayKitKind.coinFlip: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitCoinFlipView(data: data),
  PlayKitKind.diceRoll: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitDiceRollView(data: data),
  PlayKitKind.reaction: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitReactionView(data: data),
  PlayKitKind.ballShake:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitBallShakeView(data: data),
  PlayKitKind.quietHold:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitQuietHoldView(data: data),
  // ── 节点玩法模板族最后四件(2026-09-17 · feat/playkit-misc)──────────
  // 动作名 / 载荷逐条对齐 `utils/playkit-view.js` 的 ACTION_OF + serverPayload:
  //   predict:submit → SUBMIT_PREDICT{optionKey} / random:draw → DRAW{} /
  //   scan:scanned → SUBMIT_SCAN{code}。前两屏的投影分支在 `projectPlayKit`。
  PlayKitKind.predict: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitPredictView(data: data),
  PlayKitKind.random: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitRandomView(data: data),
  PlayKitKind.scan: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitScanView(data: data),
  // bingo 是**本地 kind**(真源 KIT_TYPES 里、ACTION_OF 里没有):与
  // walk / stickerBook / gameTimer 同列 —— 不做服务端动作,由本地流程点名。
  // 宿主把九个格子与已亮位序传进来即可(默认值 = 空棋盘,不崩)。
  PlayKitKind.bingo: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitBingoView(data: data),
  // ── v5.1 半屏壳剩下的三件(2026-09-18 · feat/a4-playkit-b2)──────────
  // 动作名 / 载荷逐条对齐 `utils/playkit-view.js` 的 ACTION_OF + serverPayload:
  //   dailysign:accept → CLAIM_DAILY_SIGN{text, photoUrl}。
  // 三件的**呈现形态各不相同**(真源的壳不是一个):
  //   · dailySign —— 自己的整屏(带页头与日期),进 [kFullscreenPlayKinds];
  //   · silentOrder / steps —— `cy-sheet`,走底部 sheet,刻意不进那个集合。
  PlayKitKind.dailySign:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitDailySignView(data: data),
  PlayKitKind.silentOrder:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitSilentOrderView(data: data),
  PlayKitKind.steps: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitStepsView(data: data),
  // ── 时段限定(2026-09-19 · a4-playkit-dedupe-a,收 #159/#204 的重叠)───
  // 真源是 `cy-sheet`(半屏),**刻意不进** [kFullscreenPlayKinds]:
  // 它是「还没到开播时间」那张门禁卡,倒计时 + 到点回服务端复核,
  // 没有「整屏就是判定区」那回事。
  PlayKitKind.timeWindow:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitTimeWindowView(data: data),
  // ── 《预制人生》四段(2026-09-19 · a4-playkit-journey4)────────────
  // 真源四屏全在整屏台面 `cy-play-stage`(skin="qadark")上,与问答族同壳。
  PlayKitKind.profile: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitProfileView(data: data),
  PlayKitKind.photoCheck:
      (BuildContext context, PlayKitFullscreenContext data) =>
          PlayKitPhotoCheckView(data: data),
  PlayKitKind.note: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitNoteView(data: data),
  PlayKitKind.typeIn: (BuildContext context, PlayKitFullscreenContext data) =>
      PlayKitTypeInView(data: data),
};

/// 取某个 kind 的整屏组件;没登记返回 null。
Widget? buildPlayKitFullscreen(
  BuildContext context,
  PlayKitFullscreenContext data,
) {
  final PlayKitFullscreenBuilder? builder =
      kPlayKitFullscreenBuilders[data.card.kind];
  return builder?.call(context, data);
}

/// 整屏族 = 必须占满屏的那批。宿主用它决定走整屏还是回落到半屏 [AdvancedPlayKitView]。
const Set<PlayKitKind> kFullscreenPlayKinds = <PlayKitKind>{
  PlayKitKind.coinFlip,
  PlayKitKind.diceRoll,
  PlayKitKind.reaction,
  PlayKitKind.ballShake,
  PlayKitKind.quietHold,
  PlayKitKind.countdown,
  PlayKitKind.stopwatch,
  PlayKitKind.qa,
  PlayKitKind.branch,
  PlayKitKind.estimate,
  PlayKitKind.pricePair,
  PlayKitKind.hiddenObject,
  PlayKitKind.predict,
  PlayKitKind.random,
  PlayKitKind.scan,
  PlayKitKind.walk,
  PlayKitKind.bingo,
  // 今日城市签真源是自带页头的整屏(`playkit-dailysign/index.wxml` 的 `.ds__nav`),
  // 不是 cy-sheet —— 与那两件半屏壳正好相反。
  PlayKitKind.dailySign,
  // 《预制人生》四段真源全在整屏台面 `cy-play-stage`(skin="qadark")上 ——
  // 建档的表、拍照的取景、留言的纸面、打字的目标行,都要整屏才摆得开。
  PlayKitKind.profile,
  PlayKitKind.photoCheck,
  PlayKitKind.note,
  PlayKitKind.typeIn,
};
