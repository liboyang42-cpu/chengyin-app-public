import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/map/map_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_notice.dart';
import '../../../core/widgets/cy_net_image.dart';
import '../../../data/models/checkin_models.dart';
import '../play_gap_logic.dart';
import '../play_session_controller.dart';
import 'card_box_geometry.dart';
import 'chapter_story_page.dart';
import 'free_explore_layout.dart';
import 'shop_npc_page.dart';
import 'story_lines.dart';
import '../widgets/play_node_card_extras.dart';
import '../widgets/playkit_woodfish.dart';
import 'widgets/card_box_3d.dart';
import 'widgets/game_section.dart';
import 'widgets/perk_section.dart';
import 'widgets/shop_section.dart';

/// 卡片详情页:3D 卡盒(从屏① Hero 飞入)+ 章节头 + 店铺卡/导航行 + 到店三步 + 主 CTA。
///
/// ★ 本页**按 nodeId 从 provider 现读**节点,不接快照 ——
///   扫码/拍照成功后 provider 一刷新,到店三步就地亮起、CTA 文案与禁用态同步变,
///   用户不用退出详情页再进来(与小程序一致)。接快照的话第 2 步永远走不到。
class CardDetailPage extends ConsumerStatefulWidget {
  const CardDetailPage({
    super.key,
    required this.sessionKey,
    required this.nodeId,
    required this.onPrimary,
  });

  /// 与游玩页同一个 key —— 详情页读的必须是同一份会话状态。
  final PlaySessionKey sessionKey;
  final int nodeId;

  /// 主 CTA:把**当前**节点交给调用方的 `_onNodeTap`。
  final ValueChanged<PlayNode> onPrimary;

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage> {
  // 正文滚动量,只喂给卡盒收缩 + 顶栏接管——不影响别处,故不用 setState 整页重建。
  final ValueNotifier<double> _scrollTop = ValueNotifier<double>(0);

  /// 卡盒是滚动区**之上**的浮层,命中测试到它就断了,正文的 Scrollable 拿不到指针。
  /// 卡盒占了上半屏,不接这条竖向就是半屏滚不动的死区。所以把竖向拖动转交给正文的
  /// 滚动位置(样机是手写 `_cardAxis` 分轴,同一件事;走 [ScrollPosition.drag]
  /// 而不是自己 jumpTo,是为了连惯性甩动一起拿到)。
  final ScrollController _body = ScrollController();
  ScrollHoldController? _bodyHold;
  Drag? _bodyDrag;

  @override
  void dispose() {
    _bodyHold?.cancel();
    _bodyDrag?.cancel();
    _body.dispose();
    _scrollTop.dispose();
    super.dispose();
  }

  /// ★ 手指落下就得先把正文**按停**。`Scrollable` 的「按住即刹车」不是 drag 干的,
  ///   是 `_handleDragDown → position.hold()` 干的 —— 只转交 drag 不转交 hold,
  ///   在卡盒上甩一把之后按回卡盒**刹不住**(实测 pixels 111.5 → 313.7,
  ///   按正文同样位置则 131.5 → 131.5)。卡盒占大半个上半屏,正是最爱甩的那块。
  ///   持有的 hold 由 `position` 在 drag 接管时自己 dispose,回调把引用清空 ——
  ///   所以 hold 和 drag 不会同时握在手里。
  void _onCardVerticalDown(DragDownDetails d) {
    if (!_body.hasClients) return;
    _bodyHold = _body.position.hold(() => _bodyHold = null);
  }

  void _onCardVerticalStart(DragStartDetails d) {
    if (!_body.hasClients) return;
    _bodyDrag = _body.position.drag(d, () => _bodyDrag = null);
  }

  void _onCardVerticalUpdate(DragUpdateDetails d) => _bodyDrag?.update(d);

  void _onCardVerticalEnd(DragEndDetails d) {
    _bodyDrag?.end(d);
    _bodyDrag = null;
  }

  /// 点卡盒 → 全屏故事流(样机 `openChapStory`,index.js:1013)。**不是**进游戏,
  /// 游戏在底部那颗 CTA 上。
  ///
  /// ⚠️ 这一章没写剧情就**不开页**,只给一句提示(样机 index.js:1016)——
  ///   开一页空白比不开更像坏了。判据统一走 [buildStoryLines] 返回空列表,
  ///   不在这里再判一遍 description:分段规则只该有一处。
  void _openStory(PlayNode node, PlayChapter? chapter) {
    if (chapter == null ||
        buildStoryLines(chapter, nodeImgUrl: node.imgUrl).isEmpty) {
      // ★ 中性态,不是错误态(样机 index.js:1016 用的就是中性 `cyToast`)。
      //   「作者没写内容」是一条告知,不是出错 —— 报错样式 + heavyImpact 会让人
      //   以为是自己点坏了。
      CyNativeNotice.show(context, '这一章还没写剧情');
      return;
    }
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        // 同样只传 nodeId:故事流自己从 provider 现读,不接快照。
        // onPrimary 直接透传 —— 故事流底部那颗主按钮开的就是本页同一个玩法。
        builder: (_) => ChapterStoryPage(
          sessionKey: widget.sessionKey,
          nodeId: widget.nodeId,
          onPrimary: widget.onPrimary,
        ),
      ),
    );
  }

  /// 点店铺卡 → 店铺分身对话(样机 `openShopNpc`,index.js:1192)。
  ///
  /// ⚠️ **没有分身就不进页**,只给一句提示(样机 index.js:1193)——
  ///   开一页站着个没名字的人形比不开更像坏了。判据是 `node.npc`:
  ///   `PlayNpcBrief.fromJson` 已经把「有对象但没名字」判成 null 了
  ///   (checkin_models.dart:446),这里不用再判一遍名字空不空。
  void _openShopNpc(PlayNode node) {
    if (node.npc == null) {
      // ★ 中性态:「这家没配分身」是一条告知,不是出错(与上面故事流那句同款)。
      CyNativeNotice.show(context, '这家还没有店铺分身');
      return;
    }
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        // 同样只传 nodeId:分身页自己从 provider 现读,不接快照。
        builder: (_) =>
            ShopNpcPage(sessionKey: widget.sessionKey, nodeId: widget.nodeId),
      ),
    );
  }

  void _onCardVerticalCancel() {
    _bodyHold?.cancel();
    _bodyDrag?.cancel();
    _bodyDrag = null;
  }

  @override
  Widget build(BuildContext context) {
    final PlayNodesResult? data = ref
        .watch(playSessionProvider(widget.sessionKey))
        .value;
    final PlayNode? node = data?.nodeById(widget.nodeId);
    if (data == null || node == null) {
      // 会话还没数据 / 刷新后这张卡不在列表里:给一句话,不崩、不假装还能互动。
      return const Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '这张卡片暂时读不到，返回卡包再试',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ),
        ),
      );
    }
    final PlayChapter? chapter = data.chapterOf(node);
    // 木鱼计数与 AI 参考分都是这次会话里的 page data(真源 `pages/play/index.js`),
    // 不在服务端模型里 —— 所以要单独取一份,不能从 [node] 上读。
    final PlayNodeCardExtras extras = ref.watch(
      playNodeCardExtrasProvider(widget.sessionKey),
    );
    final String primaryLabel = node.done ? '已核销' : '开始互动 获得奖励！';

    // CTA 固定在屏幕底部（对齐小程序 .fx-hero__cta），不进滚动列表——
    // 否则 3D 卡盒（高 = 宽×1.38）在小视口下会把 CTA 连同后面的内容一起
    // 挤出 ListView 的懒加载缓存区，导致它们根本没被构建。
    // 滚动内容改用 Column（非 Sliver 懒加载），章节头/小瘾说/到店三步
    // 这些排在卡盒后面的内容同理保证一定会被构建。
    const double ctaBarHeight = 16 + CyTokens.btnH + 20;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewport) {
            // 卡盒的布局尺寸只在这一处算:浮层的 Positioned 和滚动区顶部的占位
            // 共用它。两处各写一份常量,改一处漏一处就会露出/挤掉一条缝。
            final double cardW = viewport.maxWidth - 40; // 左右各 20 页边距
            final double cardH = cardW * kFreeExploreTileRatio;
            return Stack(
              // Stack 默认 StackFit.loose,尺寸取非定位子节点(滚动区)——
              // 而 SingleChildScrollView 会收缩到内容高度,内容不满屏时 Stack 撑不满
              // 视口,导致 Positioned(bottom: 0) 的“底”是内容的底而非屏幕的底。
              // expand 让 Stack 撑满视口,滚动区仍在其中自己滚,不影响滚动行为。
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification n) {
                    _scrollTop.value = n.metrics.pixels;
                    return false; // 不吞事件,交给外层继续冒泡
                  },
                  child: SingleChildScrollView(
                    controller: _body,
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      20 + ctaBarHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ★ 卡盒**不在滚动流里**(它是下面那个浮层),这里只是等高占位,
                        //   正文从卡片背后滚上去。反过来把滚动区压到卡片下方的话,
                        //   卡片缩走会在它原来的位置留一块空背景 —— 样机
                        //   index.wxml:383 点名的正是这个坑。
                        SizedBox(height: cardH),
                        const SizedBox(height: 20),
                        if (chapter != null) ...[
                          _ChapterHeader(chapter: chapter),
                          const SizedBox(height: 20),
                        ],
                        if (node.hookText != null &&
                            node.hookText!.isNotEmpty) ...[
                          _HookRow(hookText: node.hookText!),
                          const SizedBox(height: 20),
                        ],
                        ShopSection(
                          node: node,
                          // ★ 没分身也照挂手势 —— 判据在 [_openShopNpc] 里,不在这里
                          //   (与下面导航行同一条:整块不可点的话,玩家拿不到那句解释)。
                          onTapShop: () => _openShopNpc(node),
                          // ★ 无坐标也照挂 —— 判据在 [_navigate] 里,不在这里。
                          //   样机 `.fx-shop__nav` 只按地址渲染(index.wxml:420)。
                          onTapNav: () => _navigate(context, node),
                        ),
                        if (GameSection.visibleFor(node)) ...[
                          const SizedBox(height: 20),
                          GameSection(node: node),
                        ],
                        const SizedBox(height: 20),
                        _OnsiteSteps(node: node),
                        if (node.perk != null) ...[
                          const SizedBox(height: 20),
                          PerkSection(perk: node.perk!),
                        ],
                        // ── 节点卡尾段:AI 参考分 与 氛围件 ─────────────────────
                        // 真源 `pages/play/index.wxml:959,962` —— 顺序也是先分数卡、
                        // 再木鱼。两者都不判定通关、都不另开一层弹窗、没数据就整块不渲染
                        // (不造占位分,也不摆一块敲不动的木鱼)。
                        _NodeCardExtras(node: node, extras: extras),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrollTop,
                    builder:
                        (BuildContext context, double scrollTop, Widget? _) {
                          final collapse = cardCollapse(scrollTop);
                          return _CollapsedTopBar(
                            visible: collapse.barTakesOver,
                            node: node,
                            chapter: chapter,
                          );
                        },
                  ),
                ),
                // 卡盒浮层。★ 必须排在滚动区**之后**(画在它上面):正文现在从顶栏
                // 下面就开始铺,盖住卡片就点不到也拖不动了(样机 index.wxss:1466)。
                // 也排在顶栏之后,与样机 z-index 4 > 3 一致 —— 缩到最后那一小截
                // 正好压在顶栏缩略图那一侧。
                Positioned(
                  left: 20,
                  top: 20,
                  width: cardW,
                  height: cardH,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrollTop,
                    builder:
                        (BuildContext context, double scrollTop, Widget? card) {
                          final collapse = cardCollapse(scrollTop);
                          return IgnorePointer(
                            // 样机 .is-faded 是 opacity:0 + pointer-events:none ——
                            // 只淡出不禁手势的话,屏幕上半张全是一块看不见的热区。
                            ignoring: collapse.faded,
                            child: Opacity(
                              opacity: collapse.faded ? 0 : 1,
                              child: Transform.scale(
                                scale: collapse.scale,
                                // ★ 左上角为原点,与样机 transform-origin:0 0 同源:
                                //   收缩方向朝卡片自己的左上角,也就是顶栏缩略图那一侧。
                                //   换成居中原点卡片会往中间飘,离缩略图越缩越远。
                                alignment: Alignment.topLeft,
                                child: card,
                              ),
                            ),
                          );
                        },
                    child: Semantics(
                      button: true,
                      // 样机 index.wxml:363 的 aria-label 原话(标点也照抄:
                      // 分隔两个动作的是一个分号,不是逗号)。
                      label: '读这一章的剧情;左右拖可以转动卡片',
                      child: GestureDetector(
                        // 点 = 进故事流;横向拖是卡盒自己的跟手转(CardBox3d 里那个
                        // GestureDetector)。两者共存靠手势竞技场:拖过 slop 之后
                        // tap 自己退出,不会一拖就误进页。
                        onTap: () => _openStory(node, chapter),
                        // 竖向转交正文,横向留给卡盒自己的跟手转 —— 两边各认一个轴,
                        // 手势竞技场自己分得开。
                        onVerticalDragDown: _onCardVerticalDown,
                        onVerticalDragStart: _onCardVerticalStart,
                        onVerticalDragUpdate: _onCardVerticalUpdate,
                        onVerticalDragEnd: _onCardVerticalEnd,
                        onVerticalDragCancel: _onCardVerticalCancel,
                        child: Hero(
                          tag: 'fx-card-${node.nodeId}',
                          child: CardBox3d(
                            width: cardW,
                            height: cardH,
                            dimmed: node.done,
                            front: _CardCover(node: node),
                            back: _CardBack(chapter: chapter),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.bgDeep.withValues(alpha: 0),
                          AppColors.bgDeep,
                        ],
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Semantics(
                        button: true,
                        label: '${node.name}，$primaryLabel',
                        child: CupertinoButton(
                          minimumSize: const Size.fromHeight(CyTokens.btnH),
                          padding: const EdgeInsets.symmetric(
                            horizontal: CyTokens.btnPadX,
                          ),
                          color: CyTokens.actionPrimaryBg,
                          // 禁用态照原型的 .btn--disabled:占位色字 + 中性底。
                          // 不能沿用 actionPrimaryFg——它是 #0A0A0A,压在 bgSubtle
                          // (白 4% 叠 #0A0A0A ≈ #151517)上只有 1.08:1,字直接看不见。
                          disabledColor: CyTokens.bgSubtle,
                          foregroundColor: node.done
                              ? CyTokens.textPlaceholder
                              : CyTokens.actionPrimaryFg,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusLg,
                          ),
                          onPressed: node.done
                              ? null
                              : () => widget.onPrimary(node),
                          child: Text(primaryLabel),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 卡盒缩到 [cardCollapse] 判定的接管点之后,顶栏换成的紧凑条:
/// 缩略图 + 店名 + 章节眉标。章节读不到就不渲染眉标那一行——不许拿店名冒充。
class _CollapsedTopBar extends StatelessWidget {
  const _CollapsedTopBar({
    required this.visible,
    required this.node,
    required this.chapter,
  });

  final bool visible;
  final PlayNode node;
  final PlayChapter? chapter;

  @override
  Widget build(BuildContext context) {
    // 未接管时压根不挂这棵子树——挂着靠 opacity 藏,店名文本会在树里重复一份,
    // 撞上别处按 find.text(node.name) 断言「只出现一次」的测试(店铺卡那份)。
    if (!visible) return const SizedBox.shrink();
    final String? eyebrow = chapter?.meta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          CyNetImage(
            node.imgUrl?.split(',').first,
            width: 32,
            height: 32,
            borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null && eyebrow.isNotEmpty)
                  Text(
                    eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡盒正面:封面图,不叠字(小程序口径:卡面不写字)。
class _CardCover extends StatelessWidget {
  const _CardCover({required this.node});

  final PlayNode node;

  @override
  Widget build(BuildContext context) {
    // ★ 走 CyNetImage 收口:它对 null / 空串 / `",http://x"` 这种首段为空的串
    //   都有兜底,自己手写 errorBuilder 正是 net_image_fallback_test 判为
    //   「必然漏掉一批」的老路子。
    return CyNetImage(node.imgUrl?.split(',').first);
  }
}

/// 卡盒背面:只写章节名 + 章节介绍。
class _CardBack extends StatelessWidget {
  const _CardBack({required this.chapter});

  final PlayChapter? chapter;

  @override
  Widget build(BuildContext context) {
    final String? title = chapter?.title;
    final String? desc = chapter?.description;
    return Container(
      color: AppColors.bgDeep,
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            // 卡背是紧约束（SizedBox(w, w×1.38)），长介绍不 Flexible+maxLines
            // 会把 Column 撑爆（RenderFlex overflow，release 下被 ClipRRect 静默裁掉）。
            Flexible(
              child: Text(
                desc,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.chapter});

  final PlayChapter chapter;

  @override
  Widget build(BuildContext context) {
    final meta = chapter.meta;
    final title = chapter.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meta != null && meta.isNotEmpty)
          Text(
            meta,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        if (title != null && title.isNotEmpty)
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}

/// 「小瘾说」一行:独立标签 + 正文,不拼冒号。属于章节(紧跟章节头),
/// 不放进 [ShopSection] —— 那是段②(店铺卡 + 导航行),各管各的。
/// 样机这里是暖金,玩家端单色契约不许品牌色,只靠字重与字号分层。
class _HookRow extends StatelessWidget {
  const _HookRow({required this.hookText});

  final String hookText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '小瘾说',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hookText,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }
}

/// 导航到店铺。★ 结果分三档各说各的 —— 见 map_launcher.dart(与 roam_poi_detail_page 同一套兜底链)。
Future<void> _navigate(BuildContext context, PlayNode node) async {
  // ★ 没坐标不是「按钮坏了」,是这家店的数据没录 —— 照样机 `openHeroNav`
  //   (index.js:1516-1518)给一句提示,而不是整行不渲染让用户以为没这回事。
  //   ⚠️ 措辞走共享的 mapLaunchMessage:样机原话是「这家还没标坐标」,但同一情况
  //   全 App 已有 5 处在用「这个地点还没有坐标,暂时导航不了」。「完全还原样机」
  //   管的是版面与交互,不是要 App 为一个页面放弃文案一致性 —— 两句语义等价,
  //   用户无感,分叉却是真实的维护负担。
  if (!hasCoordinates(node.latitude, node.longitude)) {
    CyNativeNotice.show(
      context,
      mapLaunchMessage(MapLaunchResult.noCoordinates),
      isError: true,
    );
    return;
  }
  final MapLaunchResult r = await launchNavigation(
    lat: node.latitude,
    lng: node.longitude,
    name: node.name,
    address: node.address,
    isIOS: Platform.isIOS,
  );
  if (!context.mounted) return;
  final String msg = mapLaunchMessage(r);
  if (msg.isEmpty) return; // 打开了就别打扰
  CyNativeNotice.show(context, msg, isError: true);
}

/// 节点卡尾段:AI 参考分(服务端给了才有)+ 赛博木鱼(节点点名了才有)。
///
/// ★ 真源里这两块都在**节点卡内联**(`.sheet` 的尾部,`pages/play/index.wxml:959-963`),
///   不抢弹窗、不判定通关。宿主是这里 —— App 侧的节点卡 = 卡片详情页。
/// ★ 整块跟着 [PlayNodeCardExtras] 重建:卡正开着这一站时,照片回执带回来的
///   AI 参考分要**当场**浮出来(真源 `_applyAiScore` 里那句「卡正开着这一站时
///   同步一份,否则要等下次打开才看得到」)。
class _NodeCardExtras extends StatelessWidget {
  const _NodeCardExtras({required this.node, required this.extras});

  final PlayNode node;
  final PlayNodeCardExtras extras;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: extras,
    builder: (BuildContext context, Widget? child) {
      final PlayAiScore? score = extras.aiScore(node.nodeId);
      final bool woodfish = PlayKitWoodfish.visibleFor(node);
      if (score == null && !woodfish) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (score != null) ...<Widget>[
            const SizedBox(height: 20),
            PlayAiScoreCard(score: score),
          ],
          if (woodfish) ...<Widget>[
            const SizedBox(height: 20),
            PlayKitWoodfish(
              count: extras.woodfishCount(node.nodeId),
              onKnock: () => extras.knockWoodfish(node.nodeId),
            ),
          ],
        ],
      );
    },
  );
}

class _OnsiteSteps extends StatelessWidget {
  const _OnsiteSteps({required this.node});

  final PlayNode node;

  @override
  Widget build(BuildContext context) {
    final steps = onsiteSteps(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 段眉标(样机 .fx-hero__ey,index.wxml:451)。邻居三段都有,
        // 只剩这一段光着会出现视觉断层。
        const Text(
          '到店三步',
          style: TextStyle(
            color: CyTokens.textTertiary,
            fontSize: CyTokens.typeCaption,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            children: [
              Container(
                // 到店三步序号圆点。不用 Material `CircleAvatar`(iOS 27 语言里
                // 换成实色圆形容器,与 official 域 #290 同口径修法)。
                key: steps[i].done
                    ? ValueKey<String>('onsite-step-done-$i')
                    : null,
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: steps[i].done ? AppColors.success : AppColors.divider,
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  steps[i].title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
