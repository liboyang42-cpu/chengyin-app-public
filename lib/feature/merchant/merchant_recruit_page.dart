import '../../l10n/strings.dart';
import 'merchant_directory_strings.dart';
import 'merchant_recruit_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/game_session_api.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/chapter_application.dart';
import '../../data/models/merchant_recruit.dart';
import '../../data/models/topic.dart';
import 'chapter_node_code_sheet.dart';
import 'merchant_error_view.dart';
import 'merchant_game_node_page.dart';
import 'merchant_recruit_state.dart';
import 'merchant_recruit_sheets.dart';

/// 一条路线的商家承接页。对齐小程序 `pages/topic/merchantinfo` 的品牌浏览视图
/// (从合作中心 / 品牌招募广场进来那一条)。
///
/// App 侧此前**整条缺失**:商家能看到"可承接路线"列表,点进去却是玩家版主题详情,
/// 没有任何一处能申请承接、提交点位或填供给。
///
/// ★★ 两条链路,由服务端判、不由前端猜:
///   · 自由探索 → 按**章节**申请承接(过审后填实际供给);
///   · 经典定向 → 按**节点**报名(后台择优调配)。
///   `/api/topic/merchant-recruitment-chapters` 用四句不同的话回答四种处境,
///   照它分流;自己按 productType 猜的话,「品类没配」和「不是商家」
///   会被一起渲成"这条路线没开招商",而那两种用户自己就能解决。
final merchantRecruitProvider = FutureProvider.autoDispose
    .family<RecruitState, int>((ref, int topicId) async {
      final merchant = ref.watch(merchantApiProvider);
      final topicApi = ref.watch(topicApiProvider);
      TopicDetail topic = await topicApi.detail(topicId);
      if (topic.name.trim().isEmpty) {
        // M-12 降级位(真源 merchantinfo.js loadBrowseData):
        // 招商中、尚未对玩家上架的主题,玩家投影判「不存在」(回包空),
        // 与招商列表同口径改走商家投影。已上架主题不会走到这里。
        topic = await topicApi.detailForMerchant(topicId);
      }
      List<RecruitChapter> chapters;
      try {
        final List<Map<String, dynamic>> rows = await topicApi
            .merchantRecruitmentChapters(topicId);
        chapters = rows.map(RecruitChapter.fromJson).toList();
      } catch (e) {
        final String msg = e.toString().replaceFirst('Exception: ', '');
        // 四种处境各自的原话。判错了不是渲染歪一点,是把可执行的前置态说成死路。
        if (msg.contains('仅自由探索')) {
          bool? registered;
          try {
            registered = await merchant.hasRegisteredTopic(topicId);
          } catch (_) {
            // ★ 查不出来就保持 null。装成"没报过"会让商家提交一次必被查重拒掉的报名。
            registered = null;
          }
          return RecruitState(
            mode: RecruitMode.nodeRegistration,
            topicName: topic.name,
            topicChapters: topic.chapters,
            registered: registered,
          );
        }
        if (msg.contains('品类')) {
          return RecruitState(
            mode: RecruitMode.categoryMissing,
            topicName: topic.name,
            blockedMessage: msg,
          );
        }
        if (msg.contains('仅商家')) {
          return RecruitState(
            mode: RecruitMode.notMerchant,
            topicName: topic.name,
            blockedMessage: msg,
          );
        }
        rethrow;
      }

      // 章节承接链路:我的申请(只留这条路线的)+ 我在这条路线下的点位。
      final List<ChapterApplication> mine = await merchant
          .myChapterApplications();
      final List<Map<String, dynamic>> nodeRows = await merchant.myChapterNodes(
        topicId: topicId,
      );
      return RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: topic.name,
        topicChapters: topic.chapters,
        chapters: chapters,
        applications: mine
            .where((ChapterApplication a) => a.topicId == topicId)
            .toList(),
        nodes: nodeRows.map(MyChapterNode.fromJson).toList(),
      );
    });

/// 即将到店的场次。**单独一个 provider**:它失败不该把整页拖成错误态 ——
/// 承接申请与点位是这一页的主干,场次只是附带信息。
final merchantUpcomingRunsProvider = FutureProvider.autoDispose
    .family<List<UpcomingRun>, int>((ref, int topicId) async {
      final List<Map<String, dynamic>> rows = await ref
          .watch(merchantApiProvider)
          .upcomingRuns(topicId: topicId);
      return rows.map(UpcomingRun.fromJson).toList();
    });

class MerchantRecruitPage extends ConsumerWidget {
  const MerchantRecruitPage({super.key, required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RecruitState> async = ref.watch(
      merchantRecruitProvider(topicId),
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          async.value?.topicName.trim().isNotEmpty == true
              ? async.value!.topicName.trim()
              : stringsOf(context).merchantRecruitPageTitle,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const CySkeleton(),
            error: (Object e, StackTrace _) => merchantErrorView(
              context,
              e,
              onRetry: () => ref.invalidate(merchantRecruitProvider(topicId)),
            ),
            data: (RecruitState s) => _Body(topicId: topicId, state: s),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.topicId, required this.state});

  final int topicId;
  final RecruitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(merchantRecruitProvider(topicId));
        ref.invalidate(merchantUpcomingRunsProvider(topicId));
      },
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.pageX),
        children: <Widget>[
          switch (state.mode) {
            RecruitMode.categoryMissing => _Blocked(
              key: const Key('recruit-blocked-category'),
              title: stringsOf(context).merchantRecruitPageCategory,
              sub: state.blockedMessage ?? stringsOf(context).merchantRecruitPageCategoryHint,
              actionLabel: stringsOf(context).merchantRecruitPageCategoryAction,
              onAction: () => context.push('/merchant/coop-profile'),
            ),
            RecruitMode.notMerchant => _Blocked(
              key: const Key('recruit-blocked-not-merchant'),
              title: stringsOf(context).merchantRecruitPageNotMerchant,
              sub: state.blockedMessage ?? stringsOf(context).merchantRecruitPageNotMerchantHint,
              actionLabel: stringsOf(context).merchantRecruitPageApplyMerchant,
              onAction: () => context.push('/merchant/apply'),
            ),
            RecruitMode.chapterRecruit => _ChapterRecruit(
              topicId: topicId,
              state: state,
            ),
            RecruitMode.nodeRegistration => _NodeRegistration(
              topicId: topicId,
              state: state,
            ),
          },
          // 「本站」入口只在**承接方**这一档摆:报名/申请过这条路线,才有「我这一站」
          // 可进。浏览者是来看招商的,给他一个点下去只会说「还没开出场次」的入口,
          // 是把「还没有」误报成「就是没有」。
          if (state.registered == true || state.applications.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space5),
            _StationEntry(topicId: topicId),
          ],
          const SizedBox(height: CyTokens.space5),
          _UpcomingRuns(topicId: topicId),
        ],
      ),
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({
    super.key,
    required this.title,
    required this.sub,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String sub;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return StatusView(
      icon: Icons.storefront_outlined,
      message: title,
      sub: sub,
      large: true,
      onRetry: onAction,
      retryLabel: actionLabel,
    );
  }
}

// ─────────────────────────────────────────── 自由探索:章节承接

class _ChapterRecruit extends ConsumerWidget {
  const _ChapterRecruit({required this.topicId, required this.state});

  final int topicId;
  final RecruitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CySectionTitle(stringsOf(context).merchantRecruitPageChapters),
        Text(
          stringsOf(context).merchantRecruitPageChaptersHint,
          style: t.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: CyTokens.space3),
        if (state.chapters.isEmpty)
          StatusView(
            key: Key('recruit-chapters-empty'),
            icon: CupertinoIcons.tray,
            message: stringsOf(context).merchantRecruitPageChaptersEmpty,
            sub: stringsOf(context).merchantRecruitPageChaptersEmptyHint,
          )
        else
          ...state.chapters.map(
            (RecruitChapter c) => _ChapterCard(
              topicId: topicId,
              chapter: c,
              applied: state.applications.any(
                (ChapterApplication a) => a.chapterId == c.id,
              ),
            ),
          ),
        if (state.applications.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          CySectionTitle(stringsOf(context).merchantRecruitPageApplications),
          const SizedBox(height: CyTokens.space2),
          ...state.applications.map(
            (ChapterApplication a) => _ApplicationCard(
              topicId: topicId,
              application: a,
              action: state.actionOf(a),
              chapter: state.chapterOf(a.chapterId),
            ),
          ),
        ],
        if (state.nodes.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          CySectionTitle(stringsOf(context).merchantRecruitPageNodes),
          const SizedBox(height: CyTokens.space2),
          ...state.nodes.map((MyChapterNode n) => _NodeCard(node: n)),
        ],
      ],
    );
  }
}

class _ChapterCard extends ConsumerStatefulWidget {
  const _ChapterCard({
    required this.topicId,
    required this.chapter,
    required this.applied,
  });

  final int topicId;
  final RecruitChapter chapter;

  /// 已经申请过这一章了。★ 已申请的**不再摆「申请承接」** ——
  ///   服务端会回「已申请」,那是一个必然失败的按钮。
  final bool applied;

  @override
  ConsumerState<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends ConsumerState<_ChapterCard> {
  bool _busy = false;

  Future<void> _apply() async {
    final ChapterNodeDraft? draft = await showChapterApplyForm(
      context,
      ref,
      chapterName: merchantRecruitChapterName(context, widget.chapter),
    );
    if (draft == null || !mounted) return;

    setState(() => _busy = true);
    String message;
    bool isError = false;
    try {
      // 两步一气呵成,和小程序同序:先申请承接,再把点位内容提交上去。
      // 服务端的点位提交闸要求"已在这一章的承接链路里",所以顺序不能反。
      try {
        await ref
            .read(merchantApiProvider)
            .applyChapter(widget.chapter.id, message: draft.message);
      } on MerchantApiException catch (e) {
        // ★ 「已申请 / 申请已通过」不是失败:继续把点位提交上去。
        //   当成失败会让改点位这条路被自己的第一次申请永久堵死。
        if (!e.message.contains('已申请') && !e.message.contains('申请已通过')) {
          rethrow;
        }
      }
      await ref
          .read(merchantApiProvider)
          .submitChapterNode(
            chapterId: widget.chapter.id,
            templateId: draft.templateId,
            name: draft.name,
            address: draft.address,
          );
      // ★★ 招商是**竞争位** —— 只说「等待审核」会让商家以为位置已经锁定,
      //   而实际可能有别家一起报同一个章节。小程序的成功页专门有一句
      //   「报名成功不等于中标」(merchantapply/index.wxml:88)。
      //   ⚠️ 这不是措辞讲究:商家按「已拿下」去安排排期/备货,
      //     落选时的损失是真的。
      message = '已提交,等待主办方审核 —— 报名成功不等于中标';
    } on MerchantApiException catch (e) {
      // 服务端的拒绝话术自带修复指引(玩法超出条款 / 模板不是自己的 /
      // 主题已开始),照原文显示。
      message = e.message;
      isError = true;
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
      isError = true;
    } finally {
      ref.invalidate(merchantRecruitProvider(widget.topicId));
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    CyNativeNotice.show(context, message, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final RecruitChapter c = widget.chapter;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      key: Key('recruit-chapter-${c.id}'),
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(merchantRecruitChapterName(context, c), style: t.titleSmall),
          const SizedBox(height: CyTokens.space1),
          // 公示项:品类 / 章节类型 / 条款档。招商时就该看得到的三样。
          Text(
            '${merchantRecruitCategory(context, c)} · ${merchantRecruitRequired(context, c)} · ${c.termsLabel}',
            style: t.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (c.boundaryLabel.isNotEmpty)
            Text(
              c.boundaryLabel,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          if (c.perkMinValueLabel.isNotEmpty)
            Text(
              c.perkMinValueLabel,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          Text(
            merchantRecruitLimit(context, c),
            style: t.bodySmall?.copyWith(color: p.textTertiary),
          ),
          const SizedBox(height: CyTokens.space3),
          if (widget.applied)
            Text(
              stringsOf(context).merchantRecruitPageAlreadyApplied,
              style: t.bodySmall?.copyWith(color: p.textTertiary),
            )
          else
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                onPressed: _busy ? null : _apply,
                label: stringsOf(context).merchantRecruitUiApplyTitle,
                width: double.infinity,
                loading: _busy,
              ),
            ),
        ],
      ),
    );
  }
}

class _ApplicationCard extends ConsumerStatefulWidget {
  const _ApplicationCard({
    required this.topicId,
    required this.application,
    required this.action,
    required this.chapter,
  });

  final int topicId;
  final ChapterApplication application;
  final ChapterApplicationAction action;
  final RecruitChapter? chapter;

  @override
  ConsumerState<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends ConsumerState<_ApplicationCard> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() body) async {
    setState(() => _busy = true);
    String text;
    bool isError = false;
    try {
      text = await body();
    } on MerchantApiException catch (e) {
      text = e.message;
      isError = true;
    } catch (e) {
      text = e.toString().replaceFirst('Exception: ', '');
      isError = true;
    } finally {
      ref.invalidate(merchantRecruitProvider(widget.topicId));
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    CyNativeNotice.show(context, text, isError: isError);
  }

  Future<void> _withdraw() async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).merchantRecruitPageWithdrawTitle(merchantDirectoryChapterTitle(context, widget.application)),
      content: stringsOf(context).merchantRecruitPageWithdrawHint,
      confirmText: stringsOf(context).merchantRecruitPageWithdrawConfirm,
      cancelText: stringsOf(context).merchantRecruitPageWithdrawCancel,
    );
    if (!ok || !mounted) return;
    final successMessage = stringsOf(context).merchantRecruitPageWithdrawn;
    await _run(() async {
      await ref
          .read(merchantApiProvider)
          .withdrawChapterApplication(widget.application.id);
      return successMessage;
    });
  }

  Future<void> _offer() async {
    final String? mode = widget.action.termsMode;
    if (mode == null) return;
    final Map<String, dynamic>? payload = await showChapterOfferForm(
      context,
      ref,
      chapterId: widget.application.chapterId ?? 0,
      chapterName: widget.application.chapterName ?? stringsOf(context).merchantRecruitPageCurrentChapter,
      termsMode: mode,
    );
    if (payload == null || !mounted) return;
    final successMessage = stringsOf(context).merchantRecruitPageSupplyActive;
    await _run(() async {
      await ref.read(coopApiProvider).enrollChapterOffer(payload);
      return successMessage;
    });
  }

  /// 圈层供给「无变化,重新确认」—— 服务端拿现有快照刷新确认时间,
  /// 所以**不弹表单**,只发一次请求。
  Future<void> _reconfirmSupply() async {
    final int? offerId = widget.action.offerId;
    if (offerId == null) return;
    final successMessage = stringsOf(context).merchantRecruitPageReconfirmed;
    await _run(() async {
      await ref.read(coopApiProvider).reconfirmCircleSupply(offerId);
      return successMessage;
    });
  }

  Future<void> _pauseSupply() async {
    final int? offerId = widget.action.offerId;
    if (offerId == null) return;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).merchantRecruitPagePauseTitle,
      content: stringsOf(context).merchantRecruitPagePauseHint,
      confirmText: stringsOf(context).merchantRecruitPagePauseConfirm,
    );
    if (!ok || !mounted) return;
    final successMessage = stringsOf(context).merchantRecruitPagePaused;
    await _run(() async {
      await ref.read(coopApiProvider).pauseCircleSupply(offerId);
      return successMessage;
    });
  }

  /// 「实际供给已生效……」这句话。服务端给了确认时间就缀上日期 ——
  /// ★ 没有日期**不等于**没确认过(小程序同样只在有值时显示),
  ///   所以只缀不补零,不能编一个「最近确认」出来。
  String _supplyActiveLine(ChapterApplication a) {
    const String base = '实际供给已生效;要修改请撤回后重新提交';
    final String at = (a.circleSupplyCheckedAt ?? '').trim();
    final String day = at.length >= 10 ? at.substring(0, 10) : at;
    return day.isEmpty ? base : '$base · 最近确认 $day';
  }

  @override
  Widget build(BuildContext context) {
    final ChapterApplication a = widget.application;
    final ChapterApplicationAction act = widget.action;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      key: Key('recruit-application-${a.id}'),
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            a.chapterName?.trim().isNotEmpty == true
                ? a.chapterName!.trim()
                : stringsOf(context).merchantRecruitPageUnnamedChapter,
            style: t.titleSmall,
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            merchantDirectoryChapterStatus(context, a),
            style: t.bodySmall?.copyWith(
              color: a.isRejected ? p.statusWarning : p.textSecondary,
            ),
          ),
          // 条款档读不出来时说实话 —— 别默认成权益档,那会让下面的表单收错数据。
          Text(
            widget.chapter?.termsLabel ?? stringsOf(context).merchantRecruitPageTermsUnavailable,
            style: t.bodySmall?.copyWith(color: p.textTertiary),
          ),
          if (act.offerReadOnly)
            Text(
              _supplyActiveLine(a),
              style: t.bodySmall?.copyWith(color: p.textTertiary),
            ),
          if (a.isApproved && !act.offerReadOnly && !act.canSubmitOffer)
            Text(
              stringsOf(context).merchantRecruitPageTermsUnavailableHint,
              style: t.bodySmall?.copyWith(color: CyPalette.of(context).statusWarning),
            ),
          if (act.canWithdraw || act.canSubmitOffer) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                if (act.canWithdraw)
                  Expanded(
                    child: CyNativeButton(
                      key: Key('recruit-withdraw-${a.id}'),
                      onPressed: _busy ? null : _withdraw,
                      label: stringsOf(context).merchantRecruitPageWithdraw,
                      role: CyNativeButtonRole.secondary,
                    ),
                  ),
                if (act.canWithdraw && act.canSubmitOffer)
                  const SizedBox(width: CyTokens.space2),
                if (act.canSubmitOffer)
                  Expanded(
                    child: CyNativeButton(
                      key: Key('recruit-offer-${a.id}'),
                      onPressed: _busy ? null : _offer,
                      label: stringsOf(context).merchantRecruitUiOfferTitle,
                    ),
                  ),
              ],
            ),
          ],
          // 圈层供给的复核动作。★ 与上面那排**分开**:上面是「申请」的动作,
          //   这两个是「已生效供给」的动作,状态上互斥,不能挤在一排里。
          if (act.canReconfirmCircleSupply) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: CyNativeButton(
                    key: Key('recruit-reconfirm-supply-${a.id}'),
                    onPressed: _busy ? null : _reconfirmSupply,
                    // 文案跟小程序 `merchantinfo.wxml:384` 一字不差(全角逗号)。
                    label: stringsOf(context).merchantRecruitPageReconfirm,
                    role: CyNativeButtonRole.secondary,
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: CyNativeButton(
                    key: Key('recruit-pause-supply-${a.id}'),
                    onPressed: _busy ? null : _pauseSupply,
                    label: stringsOf(context).merchantRecruitPagePause,
                    role: CyNativeButtonRole.secondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node});

  final MyChapterNode node;

  /// 是否摆出「出示码」这两个入口。判据同小程序
  /// (`pages/topic/merchantinfo/merchantinfo.js:2032`:`showCheckinQr` 只在
  ///  confirmed / running 两个状态下为真)—— 没过审的点位摆一张扫了也没用的码,
  /// 只会让商家以为现场已经能接待了。
  bool get _canShowQr => node.isApproved;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      key: Key('recruit-node-${node.id}'),
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(merchantRecruitNodeName(context, node), style: t.titleSmall)),
              Text(
                merchantRecruitNodeAudit(context, node),
                style: t.labelSmall?.copyWith(
                  color: node.isRejected
                      ? CyPalette.of(context).statusDanger
                      : node.isApproved
                      ? CyPalette.of(context).statusSuccess
                      : p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            (node.address ?? '').trim().isEmpty ? stringsOf(context).merchantRecruitPageAddressMissing : node.address!.trim(),
            style: t.bodySmall?.copyWith(color: p.textSecondary),
          ),
          // ★ 驳回原因是这张卡最有用的一行:没有它商家只知道"没过",不知道改什么。
          if (node.isRejected)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(
                (node.nodeAuditReason ?? '').trim().isEmpty
                    ? stringsOf(context).merchantRecruitPageMissingReason
                    : stringsOf(context).merchantCatalogReason(node.nodeAuditReason!.trim()),
                style: t.bodySmall,
              ),
            ),
          // 点位自己的三件事:现场码 / 店内海报码 / 点位角色。
          // 端点各是各的(live-checkin-code / poster-code / npc/*),
          // 别拿一张码当两张用。
          const SizedBox(height: CyTokens.space3),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: <Widget>[
              if (_canShowQr)
                CyNativeButton(
                  key: Key('recruit-node-live-code-${node.id}'),
                  label: stringsOf(context).merchantRecruitPageCheckinCode,
                  role: CyNativeButtonRole.secondary,
                  onPressed: () => showChapterNodeCodeSheet(
                    context,
                    nodeId: node.id,
                    kind: ChapterNodeCodeKind.liveCheckin,
                  ),
                ),
              if (_canShowQr)
                CyNativeButton(
                  key: Key('recruit-node-poster-code-${node.id}'),
                  label: stringsOf(context).merchantRecruitPagePosterCode,
                  role: CyNativeButtonRole.secondary,
                  onPressed: () => showChapterNodeCodeSheet(
                    context,
                    nodeId: node.id,
                    kind: ChapterNodeCodeKind.poster,
                  ),
                ),
              CyNativeButton(
                key: Key('recruit-node-npc-${node.id}'),
                label: stringsOf(context).merchantRecruitPageNpc,
                role: CyNativeButtonRole.secondary,
                onPressed: () => context.push(
                  '/merchant/node-npc/${node.id}',
                  extra: node.name,
                ),
              ),
            ],
          ),
          if (!_canShowQr)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(
                node.nodeAuditStatus == null
                    ? stringsOf(context).merchantRecruitPageCodeUnknown
                    : stringsOf(context).merchantRecruitPageCodePending,
                style: t.bodySmall?.copyWith(color: p.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────── 经典定向:节点报名

class _NodeRegistration extends ConsumerStatefulWidget {
  const _NodeRegistration({required this.topicId, required this.state});

  final int topicId;
  final RecruitState state;

  @override
  ConsumerState<_NodeRegistration> createState() => _NodeRegistrationState();
}

class _NodeRegistrationState extends ConsumerState<_NodeRegistration> {
  bool _busy = false;

  Future<void> _register() async {
    final Map<String, dynamic>? param = await showNodeRegistrationForm(
      context,
      ref,
      topicId: widget.topicId,
      nodes: widget.state.selectableNodes,
    );
    if (param == null || !mounted) return;
    setState(() => _busy = true);
    String text;
    bool isError = false;
    try {
      text = await ref.read(merchantApiProvider).createTopicRegistration(param);
    } on MerchantApiException catch (e) {
      // 报名未开始 / 已结束 / 已报过这个节点 / 不能报自己发的路线 ——
      // 每一句都在告诉商家该怎么办,照原文显示。
      text = e.message;
      isError = true;
    } catch (e) {
      text = e.toString().replaceFirst('Exception: ', '');
      isError = true;
    } finally {
      ref.invalidate(merchantRecruitProvider(widget.topicId));
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    CyNativeNotice.show(context, text, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final RecruitState s = widget.state;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final bool registered = s.registered == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CySectionTitle(stringsOf(context).merchantRecruitUiRegisterTitle),
        Text(
          stringsOf(context).merchantRecruitPageRegisterHint,
          style: t.bodySmall?.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: CyTokens.space3),
        if (registered)
          StatusView(
            key: const Key('recruit-already-registered'),
            icon: Icons.assignment_turned_in_outlined,
            message: stringsOf(context).merchantRecruitPageRegistered,
            sub: stringsOf(context).merchantRecruitPageRegisteredHint,
            onRetry: () => context.push('/merchant/registrations'),
            retryLabel: stringsOf(context).merchantRecruitPageMyApplications,
          )
        else ...<Widget>[
          // ★ 查不出来就说查不出来。装成"没报过"的话,商家填完整张表才被查重拒掉。
          if (s.registered == null)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: Text(
                key: const Key('recruit-registered-unknown'),
                stringsOf(context).merchantRecruitPageRegistrationUnknown,
                style: t.bodySmall?.copyWith(color: CyPalette.of(context).statusWarning),
              ),
            ),
          if (s.selectableNodes.isEmpty)
            StatusView(
              key: Key('recruit-nodes-empty'),
              icon: CupertinoIcons.location,
              message: stringsOf(context).merchantRecruitPageNodesEmpty,
              sub: stringsOf(context).merchantRecruitPageNodesEmptyHint,
            )
          else
            CyNativeButton(
              key: const Key('recruit-register-button'),
              onPressed: _busy ? null : _register,
              label: stringsOf(context).merchantRecruitPageRegister,
              width: double.infinity,
              loading: _busy,
            ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────── 即将到店的场次

class _UpcomingRuns extends ConsumerWidget {
  const _UpcomingRuns({required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<UpcomingRun>> async = ref.watch(
      merchantUpcomingRunsProvider(topicId),
    );
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CySectionTitle(stringsOf(context).merchantRecruitPageRuns),
        const SizedBox(height: CyTokens.space2),
        async.when(
          // ★ 骨架屏内部是 ListView,直接塞进外层 ListView 会 unbounded ——
          //   给它一个确定高度,别让加载态把整页炸掉。
          loading: () =>
              const SizedBox(height: 180, child: CySkeleton(count: 2)),
          // ★ 读失败**不能渲成空态**:「没加载出来」和「没有场次」在图上长得一样,
          //   而商家会照着"没人来"去排班。
          error: (Object e, StackTrace _) => StatusView(
            key: const Key('recruit-runs-error'),
            icon: CupertinoIcons.exclamationmark_triangle,
            message: stringsOf(context).merchantRecruitPageRunsError,
            sub: e.toString().replaceFirst('Exception: ', ''),
            onRetry: () =>
                ref.invalidate(merchantUpcomingRunsProvider(topicId)),
          ),
          data: (List<UpcomingRun> rows) {
            if (rows.isEmpty) {
              return StatusView(
                key: Key('recruit-runs-empty'),
                icon: Icons.event_available_outlined,
                message: stringsOf(context).merchantRecruitPageRunsEmpty,
                sub: stringsOf(context).merchantRecruitPageRunsEmptyHint,
              );
            }
            return Column(
              children: rows
                  .map(
                    (UpcomingRun r) => Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space2),
                      child: CyCell(
                        title: '${merchantRecruitStart(context, r)} · ${merchantRecruitSource(context, r)}',
                        subtitle: <String>[
                          merchantRecruitMeta(context, r),
                          if (r.stepLabel.isNotEmpty) merchantRecruitStep(context, r),
                          if (r.arrivalLabel.isNotEmpty) merchantRecruitArrival(context, r),
                        ].join(' · '),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          stringsOf(context).merchantRecruitPageRunsHint,
          style: t.bodySmall?.copyWith(color: p.textTertiary),
        ),
      ],
    );
  }
}

/// 承接页的「本站」入口(真源 `pages/topic/merchantinfo/merchantinfo.js:2629`
/// `goStation()`):拿本商家的**全部**站点入口,按 topicId 过滤出「场次已开」
/// (`activityId > 0`)的那条,再跳 `game-node`;多个场次先让商家选一个。
///
/// ⚠️ 不能拿上面「即将到店的场次」顶替 —— 那份回来的是 ticketId(OmsTicket)的
/// 行程,`game-node` 要的是 CmsActivity.id,两者不是一个东西(真源原注释)。
/// 空结果也不等于错:要说清是「还没开场次」,而不是进了空页。
class _StationEntry extends ConsumerStatefulWidget {
  const _StationEntry({required this.topicId});

  final int topicId;

  @override
  ConsumerState<_StationEntry> createState() => _StationEntryState();
}

class _StationEntryState extends ConsumerState<_StationEntry> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final List<MerchantGameEntry> entries = await ref
          .read(gameSessionApiProvider)
          .loadMerchantEntries();
      final List<MerchantGameEntry> mine = entries
          .where(
            (MerchantGameEntry e) =>
                e.topicId == widget.topicId && e.activityId > 0,
          )
          .toList(growable: false);
      if (!mounted) return;
      if (mine.isEmpty) {
        CyNativeNotice.show(context, stringsOf(context).merchantRecruitPageNoSessions);
        return;
      }
      if (mine.length == 1) {
        context.push('/merchant/game-node/${mine.single.activityId}');
        return;
      }
      final MerchantGameEntry? picked = await showCupertinoModalPopup(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: Text(stringsOf(context).merchantRecruitPageChooseSession),
          actions: mine
              .map(
                (MerchantGameEntry e) => CupertinoActionSheetAction(
                  key: Key('recruit-station-option-${e.activityId}'),
                  onPressed: () => Navigator.of(sheetContext).pop(e),
                  child: Text(
                    e.activityName.isEmpty ? stringsOf(context).merchantRecruitPageUnnamedSession : e.activityName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(stringsOf(context).merchantRecruitUiCancel),
          ),
        ),
      );
      if (picked != null && mounted) {
        context.push('/merchant/game-node/${picked.activityId}');
      }
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CyCell(
      key: const Key('recruit-station-entry'),
      leading: const Icon(CupertinoIcons.game_controller),
      title: stringsOf(context).merchantRecruitPageStation,
      subtitle: stringsOf(context).merchantRecruitPageStationHint,
      onTap: _busy ? null : _open,
    );
  }
}
