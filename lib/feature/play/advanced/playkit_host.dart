import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_notice.dart';
import '../../../core/widgets/cy_native_sheet.dart';
import '../../../data/api/play_api.dart';
import '../../../data/models/advanced_play.dart';
import 'advanced_play_controller.dart';
import 'fullscreen/playkit_fullscreen_payload.dart';
import 'fullscreen/playkit_prefab_data.dart';
import 'fullscreen/playkit_quiz_data.dart';
import 'playkit_fullscreen.dart';
import 'playkit_projection.dart';

/// 整屏族 / 两件 sheet 的**呈现层**(宿主)。
///
/// 缝([kPlayKitFullscreenBuilders])只回答「这个 kind 用哪个组件」;什么时候打开、
/// 用整屏还是半屏、退出钮挂在哪儿,是宿主这一层的事 —— 三条线做出来的组件都不带
/// 这些 chrome(见 `playkit_countdown_view.dart` 的「退出按钮由宿主提供」)。
///
/// ## 呈现形态按真源分两类
/// 差别不在动作、在**壳**:
/// - [kFullscreenPlayKinds](整屏那批):真源是整屏台面(`cy-play-stage`),
///   「整屏就是判定区」「墙就是手机的四条边」—— 用全屏路由呈现;
/// - `gameTimer` / `stickerBook`:真源是 `cy-sheet`(半屏、自带 handle)——
///   用 B1 [showCyNativeSheet] 呈现(§3.4 更新:B1 已落地,承载任意 Flutter
///   内容的 sheet 走它,13–14 自动回退 `showCupertinoSheet`),
///   组件自带那条 handle 就是唯一一条。
bool playKitWantsFullscreen(PlayKitKind kind) =>
    kFullscreenPlayKinds.contains(kind);

/// 缝里有没有这个 kind 的组件 —— 宿主据此决定开不开呈现层。
///
/// 直接问注册表:为了一个布尔值把组件构建一遍再丢掉,等于把「有没有」和
/// 「长什么样」两件事混在一起调。[buildPlayKitFullscreen] 只留给真正要画的那一处。
bool hasPlayKitComponent(PlayKitKind kind) =>
    kPlayKitFullscreenBuilders.containsKey(kind);

/// 打开某个 kind 的玩法呈现层(整屏族走全屏,其余走底部 sheet)。
///
/// ## present=inline(铺故事流)在本层暂不拦
/// 真源 `pages/play/index.js:4801-4809`:kit 带 `present:'inline'` 时把
/// `playKit.show` 关成 false —— 不弹这一层,内容铺进章节故事流(`_inlineKit()`,
/// 故事流那侧由 `openChapterFull` 的 `kind:'kit'` 段渲染)。
/// App 的故事流内嵌是并行的 a4-playkit-storyflow 线,尚未落地;在那之前
/// inline 玩法照常走这条壳 —— 不报错也不静默丢(真源此刻**仍然渲染**,
/// 只是渲染在故事流里;这里拦成不显示才是真正的静默丢)。storyflow 落地后
/// 由消费 `PlayKitCard.present` 的那一侧接管分派。
Future<void> showPlayKitOverlay({
  required BuildContext context,
  required AdvancedPlayController controller,
  required PlayKitKind kind,
}) {
  if (playKitWantsFullscreen(kind)) {
    // 走根导航:`fullscreenDialog` 的转场 + 盖住整屏台面,半屏那条路不被叠住。
    return Navigator.of(context, rootNavigator: true).push<void>(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext routeContext) => PlayKitFullscreenSurface(
          controller: controller,
          kind: kind,
          onExit: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }
  return showCyNativeSheet<void>(
    context,
    // 真源是内容高的半屏;B1 已落地(iOS 15+ 原生 sheet,13–14 回退
    // `showCupertinoSheet` 同形态半屏),内容超出由内部滚动兜住。
    detents: CyNativeSheetDetents.medium,
    // 组件自带 handle(真源 cy-sheet 的口径),系统这条再开就是两条叠着。
    // ⚠️ 关不了组件那条:它是注册表里构造的,而注册表只许追加、不许改既有行。
    // 所以从系统这一侧让路 —— 视觉上只剩一条,和真源一致。
    grabber: false,
    builder: (BuildContext sheetContext) =>
        PlayKitSheetSurface(controller: controller, kind: kind),
  );
}

/// 从控制器**当前**状态里取这个 kind 最新的那张投影卡。
///
/// 为什么要现取而不是把卡片传进来:呈现层是路由/弹层,生命周期比宿主那一格长 ——
/// 判定回来之后 `card.kit` 里才有对错与反馈,拿旧卡片会让玩家永远看不到判定结果。
///
/// ⚠️ 不能直接 `projectPlayKit(state.playKit)` 找:那条投影按真源 `pickPlayKit`
/// 只返回**一张**卡(优先级最高且未完成的段)。答对那一刻本段刚好「完成」,
/// 投影立刻切去别的段 —— 整屏就会当场变成一张空卡,而那一刻正是该显示判定的时刻。
/// 所以先把 playKit 收窄成这一段自己,再让投影只回答这一段。
///
/// 段名 = [PlayKitKind] 的枚举名(投影按这些键读 `playKit`,`card.kit` 里挂的也是它);
/// **不是** [buildPlayKitKindTypeName] —— 那套是分发器的 type 名,
/// 在 `hiddenObject` / `pricePair` 上和段名不一样。
///
/// 本地 kind(`gameTimer` / `stickerBook` / `walk`)服务端不下发段,给一张最小卡,
/// 组件按降级态渲染(数据来源是后续批次的事,见 PR 的未决问题)。
PlayKitCard resolvePlayKitCard(
  AdvancedPlayController controller,
  PlayKitKind kind,
) {
  final AdvancedPlayState? state = controller.state;
  if (state != null) {
    final PlayKitPresentation present = playKitPresentationOf(state.present);
    final Object? segment = state.playKit[kind.name];
    if (segment != null) {
      for (final PlayKitCard card in projectPlayKit(<String, Object?>{
        kind.name: segment,
      }, present: present)) {
        if (card.kind == kind) return card;
      }
    }
    for (final PlayKitCard card in projectPlayKit(
      state.playKit,
      present: present,
    )) {
      if (card.kind == kind) return card;
    }
    // 本地 kind(gameTimer / stickerBook / walk)服务端不下发段:
    // 呈现方式仍随视图走,别让故事流线拿到假的默认值。
    return PlayKitCard(kind: kind, title: '', detail: '', present: present);
  }
  return PlayKitCard(kind: kind, title: '', detail: '');
}

/// 在册的服务端动作名(按 kind 收窄)—— 真源 `utils/playkit-view.js` 的
/// `ACTION_OF` 逐行落过来:每个 kit 一行(那边是 `type:action → 服务端名`,
/// 这里把 type 那半边落成 kind),值的半边照抄;同一个 kit 的多个组件动作
/// 落到同一行,比如五个挑战类都是 `START_CHALLENGE`。
///
/// 为什么不「把组件抛的名字统一大写」:真源两栏都不是大写化能推出来的
/// (`coinflip:flip → FLIP_COIN`),而 `qa:shoot` 这类**只在页面里被拦截、
/// 根本不在表里**的名字,大写化只会拼出服务端不认识的 `QA:SHOOT`。
/// 这类错**不报错**:请求发出去、服务端查不到动作,只是玩家做完那一下
/// 什么也没发生(真源 `playkit-view.js` 的注释原文)。
///
/// 收窄到 kind 这一维,和真源「两栏一起查」同口径:同一个 kind 抛别的 kind
/// 的合法动作名也不放行 —— `pages/play/index.js` 拦 `qa:shoot` 时特意写明
/// 「必须限定来源,否则伪造一下就能绕过类型门禁」。
///
/// 表里没有的 kind 一律不发(宿主呈现层本来也只服务注册表里那批)。
/// 本地 kind 给空行,不是漏了:它们没有服务端动作(数据来源见 PR 未决问题)。
const Map<PlayKitKind, Set<String>> kPlayKitServerActionsOf =
    <PlayKitKind, Set<String>>{
      // ── 走宿主呈现层那批(v5.2)──────────────────────────────
      PlayKitKind.qa: <String>{'SUBMIT_QA'},
      PlayKitKind.branch: <String>{'CHOOSE'},
      PlayKitKind.estimate: <String>{'SUBMIT_ESTIMATE'},
      PlayKitKind.pricePair: <String>{'SUBMIT_PRICE_PAIR'},
      PlayKitKind.hiddenObject: <String>{'SUBMIT_HIDDEN_OBJECT'},
      PlayKitKind.countdown: <String>{'START_CHALLENGE', 'SUBMIT_COUNTDOWN'},
      PlayKitKind.stopwatch: <String>{'START_CHALLENGE', 'SUBMIT_STOPWATCH'},
      // ── 半屏那批(v5.1):动作由 `advanced_play_sheet.dart` 那条路转发 ──
      PlayKitKind.blindTaste: <String>{'SUBMIT_BLIND_TASTE'},
      PlayKitKind.diyName: <String>{'SUBMIT_DIY_NAME'},
      PlayKitKind.steps: <String>{'SUBMIT_STEPS'},
      PlayKitKind.dailySign: <String>{'CLAIM_DAILY_SIGN'},
      PlayKitKind.slowTask: <String>{'START_SLOW_TASK', 'CLAIM_SLOW_TASK'},
      // silentOrder 给空行:**真源 `ACTION_OF` 里没有 `silentorder:*` 那一条**
      // (判定发生在店员扫见证码那一刻,组件只抛 `giveup`/`close`)。
      // 空行 = 「在册、但没有服务端动作」,与 walk / gameTimer 那几件同列 —— 不是漏了。
      PlayKitKind.silentOrder: <String>{},
      // ── 组件还没做,表先照真源留着(真源那张表一行不少)────────────
      PlayKitKind.coinFlip: <String>{'FLIP_COIN'},
      PlayKitKind.diceRoll: <String>{'ROLL_DICE'},
      PlayKitKind.predict: <String>{'SUBMIT_PREDICT'},
      PlayKitKind.reaction: <String>{'START_CHALLENGE', 'SUBMIT_REACTION'},
      PlayKitKind.ballShake: <String>{'START_CHALLENGE', 'SUBMIT_BALL_SHAKE'},
      PlayKitKind.quietHold: <String>{'START_CHALLENGE', 'SUBMIT_QUIET_HOLD'},
      PlayKitKind.random: <String>{'DRAW'},
      PlayKitKind.scan: <String>{'SUBMIT_SCAN'},
      // ── 《预制人生》四段(2026-09-19 · a4-playkit-journey4)─────────────
      PlayKitKind.profile: <String>{'SUBMIT_PROFILE'},
      // photoCheck:动作在表里,但**只有两步链会发它**(组件手里只有一个出了
      // 这台手机不存在的临时路径)—— 真源 `ACTION_OF` 里没有 `photocheck:*`
      // 那一条(那边表是「组件事件 → 动作名」,这条链在页面 `_submitKitPhoto`
      // 里拦);App 的表按「kind → 服务端动作名」收窄,名字在册、由链末发。
      PlayKitKind.photoCheck: <String>{'SUBMIT_PHOTO_CHECK'},
      PlayKitKind.note: <String>{'SUBMIT_NOTE'},
      // 限时打字必须先开表:服务端拿 START_CHALLENGE 那一刻的服务器时间复核用时。
      PlayKitKind.typeIn: <String>{'START_CHALLENGE', 'SUBMIT_TYPE_IN'},
      // ── 没有服务端动作、但有组件的那些 ──────────────────────────
      // timeWindow:真源 `ACTION_OF` 里没有 `timewindow:*` —— 「订阅开播提醒」
      // 走的是微信订阅消息(`wx.requestSubscribeMessage` + 服务端下发的模板 id),
      // 到点则由页面**重新取状态**,两条都不是服务端动作。所以这里给空行:
      // 给空不是漏了,是它本来就没有可发的名字。
      PlayKitKind.timeWindow: <String>{},
      // ── 本地 kind:服务端不下发,也没有服务端动作 ────────────────
      PlayKitKind.walk: <String>{},
      PlayKitKind.gameTimer: <String>{},
      PlayKitKind.stickerBook: <String>{},
      PlayKitKind.bingo: <String>{},
    };

/// 在册动作名的并集。给「源码里出现的名字都在册」那条门禁和自检用 ——
/// 真源那边是一张平表,这里由 kind 分组派生,少一处抄写就少一处漂移。
final Set<String> kPlayKitServerActions = <String>{
  for (final Set<String> names in kPlayKitServerActionsOf.values) ...names,
};

/// 组件抛上来的动作 → 服务端。**这一条是呈现层唯一的出口。**
///
/// 两道门禁都在这儿,顺序也是真源的顺序:
/// 1. **拍照问答拦在最前**(真源 `pages/play/index.js` 的 `_submitPlayKitAction`):
///    它要先把照片传上去拿到地址、再连地址提交,**是两步**;塞进一步直发的话
///    服务端拿到的是一个「出了这台手机就不存在」的临时路径。所以必须拦在
///    [AdvancedPlayController.submit] 的 `toUpperCase()` **之前** —— 裸转发会把
///    它拼成 `QA:SHOOT`。且**只有 qa 组件是合法来源**(否则伪造一个 shoot
///    就绕过了这道门禁)。
/// 2. **不在册的动作一律不发**(真源 `serverAction`:`ACTION_OF` 里没有就 return)。
///    其中分两种:
///    * kind 在册但动作表是**空行**(silentOrder / walk / gameTimer / stickerBook /
///      bingo)—— 真源对这些动作本来就是**静默**的(玩家那一下的反馈在组件里,
///      如认输的停表 + medium 触感),宿主一句都不许多给;
///    * 真不在册的名字(含非 qa 组件伪造的 `qa:shoot`)—— 不抛异常,
///      给一次原生提示,让「点了没反应」至少是可见的。
///
/// 通过门禁才震一下手指并交给控制器:**动作名一个字不改**,载荷过一次
/// [playKitServerPayload] 的单位换算(真源 `_submitPlayKitAction` 里那句
/// 「payload 要过一次翻译」同口径 —— 组件按玩家看到的单位报,服务端按判定要的
/// 单位收;不过这一层的后果是服务端按 0 判,**不报错,只是永远不通过**)。
void submitPlayKitAction({
  required BuildContext context,
  required AdvancedPlayController controller,
  required PlayKitKind kind,
  required PlayKitAction action,
}) {
  // ① 拍照族两步链,且**只有对应组件是合法来源**(真源按 kit.type 拦同一条)。
  if (action.action == kQaShootAction && kind == PlayKitKind.qa) {
    unawaited(
      _submitKitPhoto(
        context,
        controller,
        action.payload,
        action: kQaSubmitAction,
      ),
    );
    return;
  }
  if (action.action == kPhotoCheckShootAction &&
      kind == PlayKitKind.photoCheck) {
    // 判定全在服务端(契约 §2.2):只报图片地址,客户端本地算分那套已删。
    unawaited(
      _submitKitPhoto(
        context,
        controller,
        action.payload,
        action: kPhotoCheckSubmitAction,
      ),
    );
    return;
  }
  // ② 在册、且属于这个 kind 的才发。
  if (kPlayKitServerActionsOf[kind]?.contains(action.action) ?? false) {
    // 与半屏那条路同形:组件自己那一下是「选中」语义,宿主再补一次「提交」语义。
    unawaited(HapticFeedback.mediumImpact());
    unawaited(
      controller.submit(
        action.action,
        playKitServerPayload(kind, action.action, action.payload),
      ),
    );
    return;
  }
  // ③ 在册、但真源本来就不发的动作(空行的 kind:silentOrder / walk / gameTimer / …)。
  //    真源 `pages/play/index.js` 的 `_submitPlayKitAction` 查 `silentorder:giveup`
  //    查不到 → `if (!name) return` —— 不发、不提示、不打日志。这类动作的反馈
  //    (停表 + medium 触感)在组件自己那一下里,宿主一句都不许多给。
  if (kPlayKitServerActionsOf[kind]?.isEmpty ?? false) return;
  // ④ 其余(含非 qa 组件伪造来的 qa:shoot)一律不发、不报错。
  CyNativeNotice.show(context, '这一步没有发出去');
}

/// 服务端单文件限额,与小程序共享上传入口(`utils/transport/upload-client.js`
/// 的 `MAX_UPLOAD_FILE_SIZE`,同源 `spring.servlet.multipart.max-file-size=10MB`)一致。
const int _kQaPhotoMaxBytes = 10 * 1024 * 1024;

String _oversizeMessage(int maxBytes) =>
    '文件过大，请压缩或更换文件后上传（单个文件最大${(maxBytes / (1024 * 1024)).round()}MB）';

/// 拍照族两步链的宿主侧:先上传拿地址,再连地址提交(qa 拍照题 / photoCheck 共用),
/// 或只把地址交回去(建档头像 —— 它在「提交登记」那一步才随 answers 一起走)。
///
/// 真源 `pages/play/index.js` 的 `_submitKitPhoto` 逐条落过来。两步都可能失败,
/// 而且要**分开说**:上传失败是「照片没传上去」,提交失败是「传上去了但没记上」——
/// 合成一句「提交失败」,玩家不知道要不要重拍。
///
/// [action] 给 null = 头像那条:不发动作,上传成功回地址(调用方自己写回本地);
/// 给了名字 = 上传成功后连地址一起提交,返回 null。失败一律返回 null(实话已由
/// [CyNativeNotice] 说过)。
Future<String?> _submitKitPhoto(
  BuildContext context,
  AdvancedPlayController controller,
  Map<String, Object?> detail, {
  String? action,
}) async {
  final String path = '${detail['tempFilePath'] ?? ''}'.trim();
  if (path.isEmpty) return null; // 真源同一条:没路径静默(组件自己已提示「没拿到照片」)
  final Future<String> Function(String filePath)? uploader =
      controller.uploadPhoto;
  if (uploader == null) {
    CyNativeNotice.show(context, '玩法未就绪，请退出后重进');
    return null;
  }
  if (controller.qaPhotoUploading) return null; // 双击锁:在途时后到的 shoot 忽略
  final AdvancedPlayState? before = controller.state;
  if (before == null || !before.isRunning) {
    CyNativeNotice.show(context, '玩法状态不完整，请重进节点');
    return null;
  }
  // 已知超限不发网络(组件带真实 size;拿不到按未知放行,由服务端拦,不伪造)。
  final Object? rawSize = detail['size'];
  final int? size = rawSize is num && rawSize.isFinite ? rawSize.toInt() : null;
  if (size != null && size > _kQaPhotoMaxBytes) {
    CyNativeNotice.show(
      context,
      _oversizeMessage(_kQaPhotoMaxBytes),
      isError: true,
    );
    return null;
  }
  controller.qaPhotoUploading = true;
  // 真源是 cyLoading「正在上传」;App 侧无模态 HUD 先例,走同语义的轻量通知
  // (与 roam_poi_detail 上传前「照片上传中…」同款观感)。
  CyNativeNotice.show(context, '正在上传');
  final String url;
  try {
    url = await uploader(path);
  } on PlayException catch (error) {
    controller.qaPhotoUploading = false;
    if (!context.mounted) return null;
    CyNativeNotice.show(
      context,
      error.message.isEmpty ? '照片没传上去' : error.message,
      isError: true,
    );
    return null;
  } catch (_) {
    controller.qaPhotoUploading = false;
    if (!context.mounted) return null;
    CyNativeNotice.show(context, '照片没传上去', isError: true);
    return null;
  }
  controller.qaPhotoUploading = false;
  // 上传中途玩家退出:不回执给已销毁的呈现层,更不替旧提交点一下(真源的
  // createPageBoundOperation + isAborted 双守卫,App 侧由 mounted 承担)。
  if (!context.mounted) return null;
  if (url.trim().isEmpty) {
    // 回执看着成功但没给出地址 —— 仍算「照片没传上去」(真源 `if (!url)` 同一条)。
    CyNativeNotice.show(context, '照片没传上去', isError: true);
    return null;
  }
  final AdvancedPlayState? after = controller.state;
  if (after == null ||
      after.sessionId != before.sessionId ||
      after.version != before.version) {
    // 照片是异步上传的,回来时必须仍是同一 session、同一版本 ——
    // 否则会把上一题的照片提交到下一题/下一个会话。
    CyNativeNotice.show(context, '题目已变化，上一张照片未提交', isError: true);
    return null;
  }
  if (controller.phase == AdvancedPlayPhase.acting ||
      controller.phase == AdvancedPlayPhase.unknown) {
    // 控制器正在 acting/unknown 时 submit 会被静默挡掉:不装成功,给一句可恢复的实话。
    CyNativeNotice.show(context, '确认中，照片未提交，请稍后再试');
    return null;
  }
  if (action == null) return url; // 头像那条:只回地址,不动作
  await controller.submit(action, <String, Object?>{'imageUrl': url});
  return null;
}

/// 缝要的那四处 —— 与半屏那条路(`AdvancedPlayKitView`)完全同形,只多一个
/// **[BuildContext]**:门禁要给原生提示,提示得挂在调用点所在的 overlay 上。
PlayKitFullscreenContext playKitFullscreenContextFor(
  BuildContext context,
  AdvancedPlayController controller,
  PlayKitCard card,
) => PlayKitFullscreenContext(
  card: card,
  enabled: controller.canWrite,
  acting: controller.phase == AdvancedPlayPhase.acting,
  onAction: (PlayKitAction action) => submitPlayKitAction(
    context: context,
    controller: controller,
    kind: card.kind,
    action: action,
  ),
  // 整份重取(不是局部补丁):会话视图、版本号、段数据都可能变 ——
  // 幂等键与 CAS 都挂在 controller 上,绕过它自己发请求会与版本漂移。
  onRefresh: () => unawaited(controller.start()),
  // 建档头像那条:与拍照族同一条上传链(锁 / 尺寸预检 / 版本守卫都在里面),
  // 区别只有「不发动作」—— 地址写回组件,提交时随 SUBMIT_PROFILE 一起走。
  onUploadPhoto: (Map<String, Object?> detail) =>
      _submitKitPhoto(context, controller, detail),
);

/// 整屏族的外壳:铺满屏 + 一枚系统式退出钮(真源里那枚「退出」由宿主提供)。
class PlayKitFullscreenSurface extends StatelessWidget {
  const PlayKitFullscreenSurface({
    super.key,
    required this.controller,
    required this.kind,
    required this.onExit,
  });

  final AdvancedPlayController controller;
  final PlayKitKind kind;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CyTokens.bgPage,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _PlayKitSurfaceBody(controller: controller, kind: kind),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(CyTokens.space2),
              child: Align(
                alignment: Alignment.topLeft,
                child: _PlayKitExitButton(onExit: onExit),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `gameTimer` / `stickerBook` 的外壳:半屏 sheet 的内容 —— 组件自带 surface
/// 与 handle,所以这一层只负责「撑满卡片 + 贴底 + 把滚动交出去」。
class PlayKitSheetSurface extends StatelessWidget {
  const PlayKitSheetSurface({
    super.key,
    required this.controller,
    required this.kind,
    this.scrollController,
  });

  final AdvancedPlayController controller;
  final PlayKitKind kind;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    // 原生 sheet 承载时透明,透出系统材质(S3);回退路径维持真源底。
    backgroundColor: isCyNativeSheet(context)
        ? CupertinoColors.transparent
        : CyTokens.bgPage,
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          SingleChildScrollView(
            controller: scrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _PlayKitSurfaceBody(controller: controller, kind: kind),
                ],
              ),
            ),
          ),
    ),
  );
}

/// 呈现层里那件组件 —— 跟着控制器重建,数据只从缝里取。
class _PlayKitSurfaceBody extends StatelessWidget {
  const _PlayKitSurfaceBody({required this.controller, required this.kind});

  final AdvancedPlayController controller;
  final PlayKitKind kind;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final Widget? component = buildPlayKitFullscreen(
          context,
          playKitFullscreenContextFor(
            context,
            controller,
            resolvePlayKitCard(controller, kind),
          ),
        );
        // 注册表里没有的 kind 不该走到这儿(宿主是先问过缝才开的呈现层),
        // 真走到了也只是空屏 —— 这是缝的契约:不崩、不报错。
        return component ?? const SizedBox.shrink();
      },
    );
  }
}

/// 退出钮:系统式的叉,不写「返回/关闭」文字(N3)。
///
/// 底衬用 `CyTokens.overlay`:整屏台面有的是白底(倒计时那屏),有的是黑底,
/// 只有半透明黑底衬 + 白叉在两种底上都读得出来。叉恒为 `CupertinoColors.white`
/// 是同域既有写法(`play_session_page.dart` / `stopwatch_game_page.dart`):
/// 它压的是**恒暗**的底衬,不是会随外观翻转的页面色。
class _PlayKitExitButton extends StatelessWidget {
  const _PlayKitExitButton({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '退出玩法',
    // ★ 动作必须挂在这一层:子树的语义被 ExcludeSemantics 摘掉了,
    //   只给 `button: true` 不给 `onTap`,VoiceOver 会念「按钮」但双击没反应
    //   (同一课在 `cy_widgets.dart` 里记着)。
    onTap: onExit,
    child: ExcludeSemantics(
      child: CupertinoButton(
        minimumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        onPressed: onExit,
        child: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: CyTokens.overlay,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            CupertinoIcons.xmark,
            size: 18,
            color: CupertinoColors.white,
          ),
        ),
      ),
    ),
  );
}
