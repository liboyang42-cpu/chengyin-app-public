import '../../core/theme/cy_palette.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'cancel_activity_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/network/dio_client.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../data/api/account_api.dart';
import '../../data/api/activity_api.dart'
    show ActivityApi, RegistrationCheckoutException;
import '../../data/api/participant_api.dart';
import '../orders/checkout_logic.dart';
import '../orders/merchant_consent_row.dart';
import '../orders/payment_result_sheet.dart';
import '../orders/payment_verifier.dart';
import '../payment/wechat_payment.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity.dart';
import '../../data/models/activity_status.dart' show parseActivityDate;
import '../../data/models/activity_waitlist.dart';
import '../auth/login_gate.dart';
import '../auth/auth_controller.dart';
import 'activity_controller.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_action_sheet.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import 'participant_picker.dart';
import 'activity_waitlist_section.dart';

/// 后端是否以「未登录」拒绝了这次请求。只认 401,不把网络故障也当成要登录 ——
/// 那会让断网的用户被反复推去登录页,登完还是失败。
bool _isUnauthorized(Object err) =>
    err is DioException && err.response?.statusCode == 401;

class _TicketChoiceButton extends StatelessWidget {
  const _TicketChoiceButton({
    super.key,
    required this.tickets,
    required this.value,
    required this.onChanged,
  });
  final List<ActivityTicket> tickets;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    ActivityTicket? selected;
    for (final ActivityTicket ticket in tickets) {
      if (ticket.id == value) selected = ticket;
    }
    final String selectedLabel = selected == null
        ? '请选择票种'
        : '${selected.name}  ${selected.priceText}';
    return Semantics(
      button: true,
      label: '选择票种',
      value: selectedLabel,
      child: CupertinoButton(
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        color: p.bgSurfaceSubtle,
        foregroundColor: p.textPrimary,
        onPressed: () async {
          final int? picked = await showCupertinoModalPopup<int>(
            context: context,
            semanticsDismissible: true,
            builder: (BuildContext sheetContext) => CupertinoActionSheet(
              title: const Text('选择票种'),
              actions: tickets
                  .map((ActivityTicket ticket) {
                    return CupertinoActionSheetAction(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(ticket.id),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${ticket.name}  ${ticket.priceText}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ticket.id == value)
                            const Icon(CupertinoIcons.check_mark, size: 18),
                        ],
                      ),
                    );
                  })
                  .toList(growable: false),
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('取消'),
              ),
            ),
          );
          if (picked != null) onChanged(picked);
        },
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                selectedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            const Icon(CupertinoIcons.chevron_down, size: 16),
          ],
        ),
      ),
    );
  }
}

/// 活动详情:封面(4:3 大图)/标题/元信息/票种 + 底部报名条(弹出报名表单)。
/// 对齐小程序 `components/cy/scene-play-activity-detail`。
class ActivityDetailPage extends ConsumerWidget {
  const ActivityDetailPage({super.key, required this.activityId});
  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(activityDetailProvider(activityId));
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('活动详情'),
              Expanded(
                child: detail.when(
                  loading: () => const CySkeleton(type: CySkeletonType.detail),
                  error: (Object err, StackTrace st) => _isUnauthorized(err)
                      // ★ 游客点进详情必然走到这里:后端 `/api/activity/info` 对无 token 的
                      //   请求返回 401(实测生产:{"code":401,"msg":"登录状态已失效…"}),
                      //   而路由是让游客直接浏览的 —— 设计假设与后端现实对不上。
                      //   小程序不会撞上,因为那边人人都被微信静默登录、不存在"游客"。
                      //   通用错误态在这里是**误导**:游客从没登录过,却被告知"登录状态已失效",
                      //   而且「重试」按多少次都还是 401,是条死路。改成可恢复的登录引导。
                      ? StatusView(
                          message: '登录后查看活动详情',
                          sub: '这一步需要登录,登录完会自动回到这一页。',
                          icon: CupertinoIcons.lock,
                          retryLabel: '去登录',
                          onRetry: () async {
                            if (!await requireLogin(context, ref)) return;
                            ref.invalidate(activityDetailProvider(activityId));
                          },
                        )
                      : StatusView(
                          // 文案是 2026-08-18 定稿的,见
                          // test/feature/activity/detail_unauthorized_test.dart:
                          // 「没能打开这个活动」—— 不含内部构件名,也不冒充登录问题。
                          message: '没能打开这个活动',
                          sub: '网络开了点小差',
                          icon: CupertinoIcons.exclamationmark_triangle,
                          retryLabel: '重新读取',
                          onRetry: () => ref.invalidate(
                            activityDetailProvider(activityId),
                          ),
                        ),
                  data: (ActivityDetail a) => a.isGate
                      ? _ActivityGate(
                          clubId: a.gateClubId,
                          message: a.gateMessage,
                        )
                      : _DetailBody(activity: a),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 俱乐部门禁态。真源 scene-play-activity-detail:非成员拿到的不是详情而是
/// `gate=true`,这不是加载失败(重试无意义),唯一出口是去加入俱乐部;
/// 拿不到 clubId 时不能给无目的按钮,退回活动列表(:503-509 goGateClub)。
class _ActivityGate extends StatelessWidget {
  const _ActivityGate({required this.clubId, required this.message});

  final int clubId;
  final String message;

  @override
  Widget build(BuildContext context) {
    return StatusView(
      large: true,
      message: message,
      sub: '加入俱乐部后即可查看活动详情与票种',
      icon: Icons.groups_outlined,
      retryLabel: clubId > 0 ? '去加入俱乐部' : '返回活动列表',
      onRetry: clubId > 0
          ? () => context.push('/club/$clubId')
          : () {
              final NavigatorState navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.pop();
                return;
              }
              GoRouter.maybeOf(context)?.go('/activities');
            },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.activity});
  final ActivityDetail activity;

  Future<void> _showReviewSheet(BuildContext context, WidgetRef ref) async {
    if (!await requireLogin(context, ref) || !context.mounted) return;
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.32,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              _ReviewSheet(activityId: activity.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: <Widget>[
        ListView(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.space4,
            CyTokens.space4,
            CyTokens.space4,
            96,
          ),
          children: <Widget>[
            // ★ U5:标题叠在 hero 上,不再单独占一行。
            //   对齐小程序 `components/cy/scene-play-activity-detail`:
            //   `.activity-hero` 里是 image + `.activity-hero__shade` 渐变遮罩 +
            //   `.activity-hero__copy`(flex-end,padding space-4),标题与日期都压在遮罩之上。
            //   遮罩取自 `--cy-comp-sheet-activity-scrim`:
            //   linear-gradient(180deg, transparent 25% → rgba(0,0,0,.78) 100%);
            //   前景取自 `--cy-comp-sheet-player-text` = 纯白。
            _Hero(activity: activity),
            if ((activity.cancelTime ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              _CancelledNotice(activity: activity),
            ],
            const SizedBox(height: CyTokens.space3),
            _MetaCard(activity: activity),
            if (activity.description != null &&
                activity.description!.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space4),
              const CySectionTitle('关于这场活动'),
              const SizedBox(height: CyTokens.space2),
              Text(
                activity.description!,
                style: CyType.body.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ],
            if (activity.collaborators.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space4),
              _HostSection(host: activity.collaborators.first),
            ],
            if (activity.registrants.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space4),
              _RegistrantsSection(
                count: activity.registrationCount,
                people: activity.registrants,
              ),
            ],
            if (activity.nodes.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space4),
              _NodesSection(nodes: activity.nodes),
            ],
            const SizedBox(height: CyTokens.space4),
            const CySectionTitle('票种'),
            const SizedBox(height: CyTokens.space2),
            if (activity.tickets.isEmpty) ...<Widget>[
              const _ActivityEmpty(title: '暂无可选票种', sub: '主理人还没有发布可报名票种。'),
            ],
            ...activity.tickets.map(
              (ActivityTicket t) => _TicketRow(ticket: t),
            ),
            const SizedBox(height: CyTokens.space4),
            _RatingSummary(
              rating: activity.rating,
              commentCount: activity.commentCount,
              onWrite: () => _showReviewSheet(context, ref),
            ),
            const SizedBox(height: CyTokens.space3),
            if (activity.comments.isEmpty)
              const _ActivityEmpty(title: '还没有评价', sub: '参加后，来分享你的真实体验。')
            else
              ...activity.comments.map(
                (ActivityComment item) => _ActivityCommentCard(comment: item),
              ),
            const SizedBox(height: CyTokens.space3),
            Text(
              '首次真实评价的积分以平台当前规则为准',
              // `.activity-points__text`:type-caption + text-secondary
              style: CyType.caption2.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomBar(activity: activity),
        ),
      ],
    );
  }
}

/// 评价场次。
///
/// ★ 带输入框的表单**不能**放进 action sheet —— iOS 的 action sheet 只承载选项,
///   文本框落在里面既不符合 HIG,键盘升起时也没有可滚动的表单空间。
///   结构与「取消活动」同一档:半屏 sheet + 导航栏「取消」+ 底部主按钮。
class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.activityId});

  final int activityId;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  final TextEditingController _content = TextEditingController();
  int _rating = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _content.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _rating > 0 && _content.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(activityApiProvider)
          .addReview(
            activityId: widget.activityId,
            rating: _rating,
            contents: _content.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(activityDetailProvider(widget.activityId));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          minimumSize: const Size(44, 44),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        middle: const Text('写评价'),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Text(
              '参加后，来分享你的真实体验。',
              style: CyType.footnote.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: CyTokens.space3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                5,
                (int index) => CupertinoButton(
                  key: Key('activity-review-star-${index + 1}'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _rating = index + 1),
                  child: Icon(
                    index < _rating
                        ? CupertinoIcons.star_fill
                        : CupertinoIcons.star,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            CupertinoTextField(
              key: const Key('activity-review-content'),
              controller: _content,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              placeholder: '输入你的真实体验',
              padding: const EdgeInsets.all(CyTokens.space3),
            ),
            const SizedBox(height: CyTokens.space3),
            CyNativeButton(
              key: const Key('activity-review-submit'),
              label: _busy ? '发布中…' : '发布评价',
              onPressed: _canSubmit ? _submit : null,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelledNotice extends StatelessWidget {
  const _CancelledNotice({required this.activity});
  final ActivityDetail activity;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        border: Border.all(color: CyTokens.statusDanger),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '该活动已被主办方取消',
            style: CyType.callout.copyWith(
              color: CyTokens.statusDanger,
              fontWeight: FontWeight.w700,
            ),
          ),
          if ((activity.cancelReason ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            // `.activity-cancelled__reason`:type-body + text-primary
            Text(
              '原因：${activity.cancelReason}',
              style: CyType.body.copyWith(color: palette.textPrimary),
            ),
          ],
          const SizedBox(height: CyTokens.space1),
          Text(
            '已报名费用将原路全额退回，预计 1–3 个工作日到账。',
            // `.activity-cancelled__sub`:type-caption + text-secondary
            style: CyType.caption2.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HostSection extends StatelessWidget {
  const _HostSection({required this.host});
  final ActivityPerson host;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const CySectionTitle('主理人'),
      const SizedBox(height: CyTokens.space2),
      CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: host.memberId == null
            ? null
            : () => context.push('/user/${host.memberId}'),
        child: Row(
          children: <Widget>[
            CyAvatar(url: host.avatar, fallback: host.name, size: 36),
            const SizedBox(width: CyTokens.space2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  (host.name ?? '').trim().isEmpty ? '主理人' : host.name!,
                  style: CyType.headline,
                ),
                Text(
                  '发起人 · 主理人',
                  // `.activity-host__role`:type-caption + text-tertiary
                  style: CyType.caption2.copyWith(
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class _RegistrantsSection extends StatelessWidget {
  const _RegistrantsSection({required this.count, required this.people});
  final int count;
  final List<ActivityRegistrant> people;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      CySectionTitle(count >= 0 ? '$count 人已报名' : '报名成员'),
      const SizedBox(height: CyTokens.space2),
      Wrap(
        spacing: CyTokens.space2,
        runSpacing: CyTokens.space2,
        children: people
            .map(
              (ActivityRegistrant person) => CupertinoButton(
                key: ValueKey<String>(
                  'activity-registrant-${person.memberId ?? person.nickname}',
                ),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.all(4),
                onPressed: person.memberId == null
                    ? null
                    : () => context.push('/user/${person.memberId}'),
                child: CyAvatar(
                  url: person.avatar,
                  fallback: person.nickname,
                  size: 32,
                ),
              ),
            )
            .toList(growable: false),
      ),
    ],
  );
}

class _NodesSection extends StatelessWidget {
  const _NodesSection({required this.nodes});
  final List<ActivityNodeSummary> nodes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const CySectionTitle('节点玩法'),
      const SizedBox(height: CyTokens.space2),
      ...nodes.map((ActivityNodeSummary node) => _ActivityNodeRow(node: node)),
    ],
  );
}

class _ActivityNodeRow extends StatelessWidget {
  const _ActivityNodeRow({required this.node});
  final ActivityNodeSummary node;

  @override
  Widget build(BuildContext context) {
    final String players = (node.players ?? '').trim().isEmpty
        ? '人数待确认'
        : '${node.players}人';
    final String duration = node.duration == null
        ? '时长待确认'
        : '${node.duration!.toStringAsFixed(node.duration! % 1 == 0 ? 0 : 1)} 分钟';
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: CupertinoButton(
        padding: const EdgeInsets.all(CyTokens.space2),
        color: CyPalette.of(context).bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        onPressed: node.id == null
            ? null
            : () => context.push('/template/${node.id}?scope=my'),
        child: Row(
          children: <Widget>[
            CyAvatar(url: node.imgUrl, fallback: node.title, size: 44),
            const SizedBox(width: CyTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    (node.title ?? '').trim().isEmpty ? '节点名称待确认' : node.title!,
                    style: CyType.headline,
                  ),
                  Text(
                    '$players · $duration',
                    // `.activity-node__meta`:type-caption + text-tertiary
                    style: CyType.caption2.copyWith(
                      color: CyPalette.of(context).textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty({required this.title, required this.sub});
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
    child: Center(
      child: Column(
        children: <Widget>[
          // 真源两处调用都是 `<cy-empty size="sm">`:标题 caption/500/tertiary,
          // 说明 caption/secondary —— sm 档是刻意做轻的,别拿整段空态的体量压它。
          Text(
            title,
            style: CyType.caption2.copyWith(
              fontWeight: FontWeight.w500,
              color: CyPalette.of(context).textTertiary,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: CyType.caption2.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActivityCommentCard extends StatelessWidget {
  const _ActivityCommentCard({required this.comment});
  final ActivityComment comment;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: CyTokens.space2),
    padding: const EdgeInsets.all(CyTokens.space3),
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSurfaceSubtle,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                (comment.memberNickname ?? '').trim().isEmpty
                    ? '城瘾玩家'
                    : comment.memberNickname!,
                style: CyType.headline,
              ),
            ),
            Text(
              comment.createTime ?? '',
              // `.activity-comment__time`:type-caption + text-tertiary
              style: CyType.caption2.copyWith(
                color: CyPalette.of(context).textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: CyTokens.space1),
        Row(
          children: List<Widget>.generate(
            comment.rating.clamp(0, 5),
            (_) => const Icon(CupertinoIcons.star_fill, size: 12),
          ),
        ),
        if ((comment.contents ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          // `.activity-comment__text`:type-body + text-secondary
          Text(
            comment.contents!,
            style: CyType.body.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      ],
    ),
  );
}

/// 元信息卡:主题 / 集合点 / 已报名 / 玩法节点。
/// 对齐小程序 `.activity-meta`(bg-surface-subtle、radius-lg、key-value 行)。
class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.activity});
  final ActivityDetail activity;

  @override
  Widget build(BuildContext context) {
    final rows = <_MetaRow>[
      _MetaRow(
        keyText: '主题',
        value: activity.categoryNames.isEmpty
            ? '主题待确认'
            : activity.categoryNames.join(' · '),
      ),
      _MetaRow(
        keyText: '集合点',
        value: (activity.addressName ?? activity.address ?? '').trim().isEmpty
            ? '位置待确认'
            : activity.hasCoordinates
            ? '查看地图'
            : (activity.addressName ?? activity.address)!,
      ),
      _MetaRow(keyText: '已报名', value: '${activity.registrationCount} 人'),
      _MetaRow(keyText: '玩法节点', value: '${activity.nodes.length} 个'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        children: List<Widget>.generate(rows.length, (int i) {
          return Column(
            children: <Widget>[
              rows[i],
              if (i < rows.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: CyPalette.of(context).borderSubtle,
                  indent: CyTokens.space3,
                  endIndent: CyTokens.space3,
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
    required this.rating,
    required this.commentCount,
    required this.onWrite,
  });

  final double rating;
  final int commentCount;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      // 分数 + 评价数包一层 Expanded:200% Dynamic Type 下大字会把整行撑爆
      // (实测溢出 8.8px),这里让评价数换行吃掉增量,「写评价」仍贴右。
      Expanded(
        child: Row(
          children: <Widget>[
            Text(
              rating <= 0
                  ? '—'
                  : rating == rating.roundToDouble()
                  ? '${rating.toInt()}'
                  : rating.toStringAsFixed(1),
              style: CyType.largeTitle,
            ),
            const SizedBox(width: CyTokens.space1),
            Flexible(
              child: Text(
                commentCount == 0 ? '还没有评价' : '$commentCount 条评价',
                // `.activity-review-score__meta`:type-caption + text-tertiary
                style: CyType.caption2.copyWith(
                  color: CyPalette.of(context).textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
      CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        color: CyPalette.of(context).bgSurfaceSubtle,
        onPressed: onWrite,
        child: const Text('写评价'),
      ),
    ],
  );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.keyText, required this.value});
  final String keyText;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            keyText,
            style: CyType.body.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          Flexible(
            child: Text(
              value,
              // 集合点常是「XX地铁站 · XX路 1601 号」这种长值,单行必截断,
              // 而地址截断了等于没给 —— 放宽到两行。
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: CyType.body.copyWith(
                color: CyPalette.of(context).textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 票种卡:bg-surface-subtle + radius-lg + 描边,name/price 同为 card-title 加粗。
/// 对齐小程序 `.ticket`。选中在报名弹窗里做(票种下拉),这里保持展示。
class _TicketRow extends StatefulWidget {
  const _TicketRow({required this.ticket});
  final ActivityTicket ticket;

  @override
  State<_TicketRow> createState() => _TicketRowState();
}

class _TicketRowState extends State<_TicketRow> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final ActivityTicket ticket = widget.ticket;
    final String inventory = ticket.remainingInventory == null
        ? '余票待确认'
        : ticket.remainingInventory! > 0
        ? '剩余 ${ticket.remainingInventory} 张'
        : '已售罄';
    final String date = ticket.startTime == null
        ? '时间待定'
        : '${_compactActivityDate(ticket.startTime)}${ticket.endTime == null ? '' : ' - ${_compactActivityDate(ticket.endTime)}'}';
    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space2),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  ticket.name.isEmpty ? '票种名称待确认' : ticket.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.callout.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                ticket.priceText,
                style: CyType.callout.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            '$date · $inventory',
            style: CyType.caption2.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          CupertinoButton(
            key: ValueKey<String>('activity-ticket-more-${ticket.id}'),
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
            minimumSize: const Size(44, 44),
            onPressed: () => setState(() => expanded = !expanded),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    expanded ? '收起阵容' : '查看阵容与截止时间',
                    // 11 = 小程序 `.ticket__more-label` 的 type-caption(不是
                    // `.ticket__name` 的 card-title);颜色取 `.ticket__more` 的 text-primary。
                    style: CyType.caption2.copyWith(
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_right,
                  size: 16,
                ),
              ],
            ),
          ),
          if (expanded) ...<Widget>[
            if ((ticket.description ?? '').trim().isNotEmpty)
              Text(
                ticket.description!,
                style: CyType.caption2.copyWith(
                  color: CyPalette.of(context).textPrimary,
                ),
              ),
            if (ticket.endTime != null)
              Text(
                '报名截止 ${_compactActivityDate(ticket.endTime)}',
                style: CyType.caption2.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            const SizedBox(height: CyTokens.space1),
            if (ticket.registrants.isEmpty)
              Text(
                '这个票种还没有人报名',
                // 真源 `<cy-empty size="sm" title=…>`:caption/500/tertiary
                style: CyType.caption2.copyWith(
                  fontWeight: FontWeight.w500,
                  color: CyPalette.of(context).textTertiary,
                ),
              )
            else
              Wrap(
                spacing: CyTokens.space2,
                children: ticket.registrants
                    .map(
                      (ActivityRegistrant person) => CyAvatar(
                        url: person.avatar,
                        fallback: person.nickname,
                        size: 28,
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
        ],
      ),
    );
  }
}

String _compactActivityDate(String? value) {
  final DateTime? parsed = parseActivityDate(value);
  if (parsed == null) return value?.trim() ?? '';
  final String hour = parsed.hour.toString().padLeft(2, '0');
  final String minute = parsed.minute.toString().padLeft(2, '0');
  return '${parsed.month}月${parsed.day}日 $hour:$minute';
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.activity});
  final ActivityDetail activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? me = ref.watch(authControllerProvider).user?.id;
    final bool isOwner = canCancelActivity(
      hostMemberId: activity.hostMemberId,
      myMemberId: me,
    );
    final AsyncValue<List<MyRegistration>> joined = ref.watch(
      myJoinedActivitiesProvider,
    );
    final MyRegistration? registration = joined.maybeWhen(
      data: (List<MyRegistration> list) {
        for (final MyRegistration item in list) {
          if (item.ownerType == 2 && item.ownerId == activity.id) return item;
        }
        return null;
      },
      orElse: () => null,
    );

    final Widget primary;
    if (isOwner) {
      primary = CancelActivityEntry(
        activityId: activity.id,
        hostMemberId: activity.hostMemberId,
        inline: true,
      );
    } else if (registration != null) {
      primary = CyNativeButton(
        width: double.infinity,
        label: _registeredActionLabel(registration),
        onPressed: () => context.push('/participations'),
      );
    } else {
      primary = CyNativeButton(
        width: double.infinity,
        label: '立即报名',
        onPressed: () async {
          if (!await requireLogin(context, ref)) return;
          if (!context.mounted) return;
          await showCupertinoSheet<void>(
            context: context,
            showDragHandle: true,
            topGap: 0.08,
            scrollableBuilder:
                (BuildContext context, ScrollController scrollController) =>
                    _SignupSheet(
                      activity: activity,
                      scrollController: scrollController,
                    ),
          );
        },
      );
    }

    return CyFooterBar(
      secondary: CyNativeButton(
        width: double.infinity,
        role: CyNativeButtonRole.secondary,
        icon: const CyNativeButtonIcon(
          sfSymbol: 'square.and.arrow.up',
          fallback: CupertinoIcons.share,
        ),
        label: '分享',
        onPressed: () => SharePlus.instance.share(
          ShareParams(title: activity.name, text: activity.name),
        ),
      ),
      primary: primary,
    );
  }
}

String _registeredActionLabel(MyRegistration registration) {
  final DateTime now = DateTime.now();
  final DateTime? start = parseActivityDate(registration.startDate);
  final DateTime? end = parseActivityDate(registration.endDate);
  if (start != null && now.isBefore(start)) return '查看报名';
  if (end != null) {
    final DateTime endOfDay = DateTime(
      end.year,
      end.month,
      end.day,
      23,
      59,
      59,
      999,
    );
    if (now.isAfter(endOfDay)) return '查看足迹';
  }
  return '继续探索';
}

/// 报名表单(底部弹窗):姓名/手机必填,可选票种,创建报名。
/// 对齐小程序 `pages/activity/baoming` 的 .cy-field / .cy-label 形态。
class _SignupSheet extends ConsumerStatefulWidget {
  const _SignupSheet({required this.activity, required this.scrollController});
  final ActivityDetail activity;
  final ScrollController scrollController;

  @override
  ConsumerState<_SignupSheet> createState() => _SignupSheetState();
}

class _SignupSheetState extends ConsumerState<_SignupSheet> {
  int? _ticketId;
  Participant? _participant;
  bool _busy = false;

  /// 当前报价。★ 不只是显示明细 —— 它带的 `quoteSign` 是**建单硬前置**,
  ///   没有它后端直接 400。所以报价没到位时提交按钮必须是禁用的。
  RegistrationQuote? _quote;

  /// 报价正在刷新(切票种 / 拨积分开关都会重算)。
  bool _quoting = false;

  /// 报价失败的原因,失败时顶掉费用明细显示。
  String? _quoteError;

  /// 是否使用积分抵扣。后端按这个值重算报价,签名也随之变 ——
  /// 所以它一变就必须重新取价,不能拿旧签名去建单(会 409)。
  bool _usePoints = false;

  /// 已建单但未确认支付的报名。留着它,用户取消支付后可在原地重试 ——
  /// ⚠️ 待支付的票**不会出现在票夹**(后端 /registration/list 对 owner_type<3
  /// 强制 registrationStatus=2),关掉这个弹窗就再也找不到入口,只能重新报名建新单。
  RegistrationCreateResult? _pending;

  /// 建单用的幂等标识。同一次报名重试必须复用,否则会建出多张票。
  String? _requestId;

  /// 是否已勾选「向主办方提供报名信息」的单独同意。
  /// ★ 后端 create / pay / pay/app 三个入口都查这条同意记录,没有一律拒 ——
  ///   所以这不是可选的合规装饰,是报名与支付的硬前置。
  bool _consented = false;
  ActivityWaitlistStatus? _waitlistStatus;
  String? _submitError;

  /// 支付通道探测结果。null = 没问出来 —— 当可用处理(软探测不是硬闸,
  /// 探测失败把正常支付路径堵死比让它去试一次更糟)。
  bool? _paymentReady;
  bool _checkingReady = false;

  /// 姓名 / 手机号表单。★ 建单提交的是**这两个输入框此刻的值**:
  ///   从已保存的参与人选进来只是省手填,用户改过就以改的为准。
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  /// 参与人列表的订阅。列表晚到时要补一次「默认选中默认参与人」,
  /// 否则卡片显示选中了、表单却还是空的 —— 用户以为填过了。
  ProviderSubscription<AsyncValue<List<Participant>>>? _participantsSub;

  ActivityTicket? get _selectedTicket {
    for (final ActivityTicket ticket in widget.activity.tickets) {
      if (ticket.id == _ticketId) return ticket;
    }
    return null;
  }

  bool get _requiresWaitlistOffer => _selectedTicket?.isSoldOut ?? false;

  bool get _hasWaitlistOffer => _waitlistStatus?.hasActiveOffer ?? false;

  /// 待支付金额>0 且探测明确说不可用 —— 才拦(`canPay` 同款判据)。
  bool get _payBlocked =>
      (_quote?.payAmount ?? 0) > 0 && _paymentReady == false;

  String get _actionLabel {
    if (_requiresWaitlistOffer && !_hasWaitlistOffer) {
      return _waitlistStatus?.paymentText ?? '正在确认候补状态…';
    }
    if (_checkingReady) return '检查支付服务...';
    if (_payBlocked) return '重新检查支付服务';
    return '付款';
  }

  /// 通道没通时按 CTA 直接拦下:给 tips + 重新探测一次(baoming.js 同款,
  /// 按钮文案已提示,按下再兜一道)。返回 true = 已拦截。
  bool _interceptNotReady() {
    if (!_payBlocked) return false;
    if (!_checkingReady) {
      _toast('正在重新检查支付服务，请稍后重试');
      _checkPaymentReadiness();
    }
    return true;
  }

  Future<void> _checkPaymentReadiness() async {
    if (_checkingReady) return;
    setState(() => _checkingReady = true);
    try {
      final r = await ref.read(activityApiProvider).paymentReadiness();
      if (!mounted) return;
      setState(() => _paymentReady = r.ready);
    } catch (_) {
      // 探测本身失败 —— 不改判,保留上一次结论(没有就当可用)。
    } finally {
      if (mounted) setState(() => _checkingReady = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.activity.tickets.isNotEmpty) {
      _ticketId = widget.activity.tickets.first.id;
    }
    _refreshQuote();
    _checkPaymentReadiness();
    // 参与人列表可能已经就绪(刚在别的页面加载过),也可能稍后才到 ——
    // 两条路都要把默认参与人填进表单,少了后一条就会出现
    // 「卡片上选着人、姓名手机号却空着」的错位。
    final List<Participant>? ready = ref
        .read(participantsProvider)
        .asData
        ?.value;
    if (ready != null && ready.isNotEmpty) {
      _applyParticipant(_preferredParticipant(ready)!);
    }
    _participantsSub = ref.listenManual(participantsProvider, (
      AsyncValue<List<Participant>>? previous,
      AsyncValue<List<Participant>> next,
    ) {
      final List<Participant> list =
          next.asData?.value ?? const <Participant>[];
      if (_participant != null || list.isEmpty) return;
      setState(() => _applyParticipant(_preferredParticipant(list)!));
    });
  }

  @override
  void dispose() {
    _participantsSub?.close();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// 选中参与人 = 卡片显示它 + 姓名手机号按**原值**填进表单。
  /// ★ 掩码只用于列表展示:填进表单会把 138****1234 当号码提交上去。
  ///   选择器那条路见它自己的注释,这两处必须都填原值。
  void _applyParticipant(Participant participant) {
    _participant = participant;
    _nameCtrl.text = participant.fullName;
    _phoneCtrl.text = participant.mobilePhone;
  }

  /// 取报价。切票种 / 拨积分开关后都要重取 —— 旧签名对不上后端会 409。
  Future<void> _refreshQuote() async {
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final quote = await ref
          .read(activityApiProvider)
          .quote(
            ownerId: widget.activity.id,
            ticketId: _ticketId,
            usePoints: _usePoints,
          );
      if (!mounted) return;
      setState(() => _quote = quote);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        // 异常原文只进日志;上屏的是人话,拼进「没能取到价格:…」那句里。
        debugPrint('[activity-detail] 取报价失败: $e');
        _quoteError = friendlyOrBackendMessage(e, fallback: '稍后重试');
      });
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, msg, isError: isError);
  }

  Future<void> _submit() async {
    // 闸在字段本身:报名要提交的就是这两个值,拿参与人快照当替身会在
    // 「选了参与人又手改了手机号」时提交出用户没确认过的号码。
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String realName = _nameCtrl.text.trim();
    final String phone = _phoneCtrl.text.trim();
    if (_interceptNotReady()) return;
    if (_requiresWaitlistOffer && !_hasWaitlistOffer) {
      _toast('当前票种已满，需等候候补名额', isError: true);
      return;
    }
    final quote = _quote;
    if (quote == null || quote.quoteSign.isEmpty) {
      // 到不了这儿(按钮已禁用),但真走到就明说原因,别让后端那句
      // 「缺少报价签名,请重新进入报名页」直接甩给用户。
      _toast('报价还没取到,请稍候重试', isError: true);
      return;
    }
    if (!wechatPaymentFlowGate.tryAcquire()) {
      _toast('已有一笔支付正在处理中，请完成后再试', isError: true);
      return;
    }
    setState(() {
      _busy = true;
      _submitError = null;
    });
    try {
      await _attemptCheckout(realName, phone, quote);
    } finally {
      wechatPaymentFlowGate.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 建单→支付一轮。旧幂等键对应的单已过期/已进终态时(410 / 终态 409),
  /// **换键重建一次**——只一次:再撞同样的错就说明不是键的问题,
  /// 把后端那句「订单已过期,请重新报名」原样给用户(与真源逐字同源)。
  /// 调用方需持有 wechatPaymentFlowGate(重建走的是同一次用户意图,
  /// 不重新抢闸 —— 递归会在自己持有的闸上死锁)。
  Future<void> _attemptCheckout(
    String realName,
    String phone,
    RegistrationQuote quote,
  ) async {
    bool rebuilt = false;
    while (true) {
      try {
        _requestId ??= ActivityApi.newRequestId();
        // 同意必须先于建单落库:后端按「当前版本的 AGREE 记录」判定,
        // 版本由服务端现算,客户端不传也不猜。
        await ref.read(accountApiProvider).agreeSignupDataSharing(_requestId!);
        final result = await ref
            .read(activityApiProvider)
            .createRegistration(
              ownerId: widget.activity.id,
              realName: realName,
              phone: phone,
              ticketId: _ticketId,
              requestId: _requestId,
              usePoints: _usePoints,
              quoteSign: quote.quoteSign,
              waitlistOfferId: _hasWaitlistOffer
                  ? _waitlistStatus!.offerId
                  : null,
              waitlistOfferToken: _hasWaitlistOffer
                  ? _waitlistStatus!.offerToken
                  : null,
            );
        if (!mounted) return;
        setState(() => _pending = result);
        if (!result.needsPayment) {
          // 零元单:后端已置支付完成,直接走成功面板(真源 freeSignup 文案)。
          await _presentResultSheet(
            registrationId: result.registrationId,
            presetSuccess: true,
            freeSignup: true,
          );
          return;
        }
        await _pay(result.payParams!, registrationId: result.registrationId);
        return;
      } on RegistrationCheckoutException catch (e) {
        if (!mounted) return;
        final route = routeCheckoutFailure(code: e.code, message: e.message);
        if (route == CheckoutFailureRoute.rebuild && !rebuilt) {
          rebuilt = true;
          _requestId = null;
          continue;
        }
        if (route == CheckoutFailureRoute.priceChanged) {
          // 同码 409 的另一半:重报价,不是重建。
          setState(() => _submitError = priceChangedUserMessage);
          _refreshQuote();
          return;
        }
        setState(() {
          _submitError = route == CheckoutFailureRoute.rebuild
              ? orderExpiredUserMessage
              : e.message;
        });
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _submitError = e.toString().replaceFirst('Exception: ', '');
        });
        return;
      }
    }
  }

  /// 用已有报名单重新取参数并调起支付(用户上次取消/失败后重试)。
  Future<void> _retryPay() async {
    final pending = _pending;
    if (pending == null) return;
    if (_interceptNotReady()) return;
    if (!wechatPaymentFlowGate.tryAcquire()) {
      _toast('已有一笔支付正在处理中，请完成后再试', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final params = await ref
          .read(activityApiProvider)
          .payApp(pending.registrationId);
      await _pay(params, registrationId: pending.registrationId);
    } on RegistrationCheckoutException catch (e) {
      final route = routeCheckoutFailure(code: e.code, message: e.message);
      if (route == CheckoutFailureRoute.rebuild) {
        // 待支付单已过期/进终态:这张单没救了,丢键重走建单(一次)。
        setState(() {
          _pending = null;
          _requestId = null;
        });
        final quote = _quote;
        if (quote != null && quote.quoteSign.isNotEmpty) {
          await _attemptCheckout(
            _nameCtrl.text.trim(),
            _phoneCtrl.text.trim(),
            quote,
          );
        }
      } else if (route == CheckoutFailureRoute.priceChanged) {
        setState(() => _submitError = priceChangedUserMessage);
        _refreshQuote();
      } else {
        _toast(e.message, isError: true);
      }
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      wechatPaymentFlowGate.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 调起微信支付,把结果交给**服务端回读**——客户端回应不是订单真源:
  /// success 也要轮询终态才算数;failed/unknown 更不能断定「没付」,
  /// 用户可能已扣款而回调未到。cancelled 是唯一可以直接认的:
  /// 微信 SDK 说没起成就没起,顺手撤单(撤不掉由 /pay 的过期兜底)。
  Future<void> _pay(
    Map<String, String> params, {
    required int registrationId,
  }) async {
    final outcome = await const WechatPayment().pay(params);
    if (!mounted) return;
    switch (outcome) {
      case WechatPayOutcome.cancelled:
        _toast('您已取消支付');
        await _cancelPendingOrder();
      case WechatPayOutcome.failed:
        await _presentResultSheet(
          registrationId: registrationId,
          presetFailMessage: '支付未完成',
        );
      case WechatPayOutcome.success:
      case WechatPayOutcome.unknown:
        await _reconcile(registrationId);
    }
  }

  /// 支付后终态轮询(与小程序 payment-verifier 同参同判据),
  /// 结果一律进结果面板。
  Future<void> _reconcile(int registrationId) async {
    final verifier = RegistrationPaymentVerifier(
      requestStatus: (int id) async {
        final d = await ref.read(activityApiProvider).ticketInfo(id);
        return <String, dynamic>{
          'paymentStatus': d.paymentStatus,
          'registrationStatus': d.registrationStatus,
        };
      },
    );
    await _presentResultSheet(
      registrationId: registrationId,
      reconcile: () => verifier.verify(registrationId),
    );
  }

  Future<void> _presentResultSheet({
    required int registrationId,
    Future<PaymentVerifyOutcome> Function()? reconcile,
    String? presetFailMessage,
    bool presetSuccess = false,
    bool freeSignup = false,
  }) async {
    final PaymentSheetOutcome? r = await showPaymentResultSheet(
      context,
      reconcile: reconcile,
      presetFailMessage: presetFailMessage,
      presetSuccess: presetSuccess,
      freeSignup: freeSignup,
      consent: (ValueChanged<bool> onBusy) => CyMerchantConsentRow(
        orderId: registrationId,
        ownerMemberId: widget.activity.hostMemberId,
        onBusyChanged: onBusy,
      ),
    );
    if (!mounted) return;
    switch (r?.result) {
      case PaymentSheetResult.success:
        _finish(freeSignup ? '报名成功' : '支付成功');
      case PaymentSheetResult.failed:
      case null:
        // null = fail 相被滑掉(canPop 只放行 fail),与按「知道了」同义。
        setState(() {
          _submitError = (r != null && r.why.isNotEmpty) ? r.why : '这笔没有付成功';
        });
        ref.invalidate(activityDetailProvider(widget.activity.id));
        ref.invalidate(myJoinedActivitiesProvider);
      case PaymentSheetResult.unknown:
        await cyConfirm(
          context,
          title: '支付结果待确认',
          content: '暂不要重复支付，请稍后到订单中查看最终状态。',
          confirmText: '知道了',
          showCancel: false,
        );
        if (!mounted) return;
        ref.invalidate(activityDetailProvider(widget.activity.id));
        ref.invalidate(myJoinedActivitiesProvider);
    }
  }

  /// 取消支付后撤单,释放幂等键 —— 真源纪律:`_reqId=null` **只在撤单
  /// 成功之后**。撤失败就留着旧键旧单,下次「去支付」原单重试,
  /// 真过期了由 /pay 的 410 兜底重建。
  Future<void> _cancelPendingOrder() async {
    final pending = _pending;
    if (pending == null) return;
    try {
      await ref
          .read(activityApiProvider)
          .cancelRegistration(
            registrationId: pending.registrationId,
            paid: false,
          );
      _requestId = null;
      if (mounted) setState(() => _pending = null);
    } catch (_) {
      // 撤单失败:不动旧键(见上)。
    }
  }

  void _finish(String msg) {
    if (!mounted) return;
    ref.invalidate(activityDetailProvider(widget.activity.id));
    ref.invalidate(myJoinedActivitiesProvider);
    if (widget.activity.teamMode == 2) {
      _finishWithTeam(msg);
      return;
    }
    Navigator.of(context).pop();
    _toast(msg);
  }

  Future<void> _finishWithTeam(String msg) async {
    final int max = (widget.activity.teamMaxMembers ?? 4).clamp(2, 4);
    final int? size = await showCyNativeActionSheet<int>(
      context: context,
      title: '创建同行队伍',
      message: '选择队伍人数，创建后可邀请同行玩家。',
      cancelLabel: '稍后处理',
      actions: <CyNativeAction<int>>[
        for (int value = 2; value <= max; value++)
          CyNativeAction<int>(value: value, label: '$value 人队伍'),
      ],
    );
    if (!mounted) return;
    if (size == null) {
      Navigator.of(context).pop();
      _toast(msg);
      return;
    }
    setState(() => _busy = true);
    try {
      final int teamId = await ref
          .read(pageParityApiProvider)
          .createActivityTeam(activityId: widget.activity.id, maxMembers: size);
      if (!mounted) return;
      final GoRouter router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/team/$teamId');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ActivityTicket> tickets = widget.activity.tickets;
    final AsyncValue<List<Participant>> participantsAsync = ref.watch(
      participantsProvider,
    );
    final List<Participant> participants =
        participantsAsync.asData?.value ?? const <Participant>[];
    final Participant? participant =
        _participant ?? _preferredParticipant(participants);
    // ★ 骨架屏只挡「报价还没算出来」这一段。参与人列表**不挡**:
    //   它慢或挂住时,整张结算页跟着变骨架 = 用户连票种和费用都看不到,
    //   而小程序那边只有参与人那一小块是加载态。
    final bool initialLoading = _quote == null && _quoteError == null;
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CyPalette.of(context).bgPage.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: CyPalette.of(context).borderSubtle),
        ),
        middle: const Text('结算'),
        leading: CupertinoButton(
          key: const Key('signup-checkout-close'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.chevron_down, size: 22),
        ),
      ),
      resizeToAvoidBottomInset: true,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: initialLoading
              ? const _SignupCheckoutSkeleton(
                  key: Key('signup-checkout-skeleton'),
                )
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: SingleChildScrollView(
                        controller: widget.scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(
                          CyTokens.pageX,
                          CyTokens.space4,
                          CyTokens.pageX,
                          CyTokens.space5,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const SizedBox(height: CyTokens.space4),
                            CySectionTitle(
                              '参与人信息',
                              trailing: const Icon(
                                CupertinoIcons.chevron_forward,
                                size: 18,
                              ),
                            ),
                            const SizedBox(height: CyTokens.space2),
                            if (participantsAsync.hasError)
                              _SignupInlineError(
                                onRetry: () =>
                                    ref.invalidate(participantsProvider),
                              )
                            else
                              _ParticipantSummary(
                                participant: participant,
                                enabled: !_busy && _pending == null,
                                onPressed: () async {
                                  final Participant? picked =
                                      await pickParticipant(context);
                                  if (picked == null || !mounted) return;
                                  setState(() {
                                    _participant = picked;
                                    _nameCtrl.text = picked.fullName;
                                    _phoneCtrl.text = picked.mobilePhone;
                                  });
                                  // 上面三行与 _applyParticipant 重复是**故意**的:
                                  // participant_fill_source_test 要求「选中后填原值」
                                  // 就写在选择器这里。合并回 helper 会让那条门禁失锚。
                                },
                              ),
                            const SizedBox(height: CyTokens.space7),
                            const CySectionTitle('报名信息'),
                            const SizedBox(height: CyTokens.space3),
                            // 从参与人选是省手填,**不是**唯一入口:
                            // 没存过参与人的人也要能直接报名,所以这里留
                            // 可编辑的姓名/手机号,键盘与自动填充都按 iOS 语义给。
                            AutofillGroup(
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    CyField(
                                      label: '姓名',
                                      child: _CupertinoValidatedField(
                                        controller: _nameCtrl,
                                        keyboardType: TextInputType.name,
                                        textInputAction: TextInputAction.next,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        autofillHints: const <String>[
                                          AutofillHints.name,
                                        ],
                                        placeholder: '请输入真实姓名',
                                        validator: (_) =>
                                            _nameCtrl.text.trim().isEmpty
                                            ? '请输入姓名'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: CyTokens.space3),
                                    CyField(
                                      label: '手机号',
                                      child: _CupertinoValidatedField(
                                        controller: _phoneCtrl,
                                        keyboardType: TextInputType.phone,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const <String>[
                                          AutofillHints.telephoneNumber,
                                        ],
                                        placeholder: '请输入联系手机号',
                                        validator: (_) {
                                          final String value = _phoneCtrl.text
                                              .trim();
                                          if (value.isEmpty) {
                                            return '请输入手机号';
                                          }
                                          if (!RegExp(
                                            r'^1\d{10}$',
                                          ).hasMatch(value)) {
                                            return '手机号格式不正确';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: CyTokens.space7),
                            const CySectionTitle('活动信息'),
                            const SizedBox(height: CyTokens.space3),
                            _CheckoutActivitySummary(activity: widget.activity),
                            if (tickets.length > 1) ...<Widget>[
                              const SizedBox(height: CyTokens.space3),
                              _TicketChoiceButton(
                                key: const Key('signup-ticket-picker'),
                                tickets: tickets,
                                value: _ticketId,
                                onChanged: (int value) {
                                  setState(() {
                                    _ticketId = value;
                                    _waitlistStatus = null;
                                  });
                                  _refreshQuote();
                                },
                              ),
                            ],
                            if (_ticketId != null)
                              ActivityWaitlistSection(
                                key: ValueKey<String>(
                                  'activity-waitlist-${widget.activity.id}-$_ticketId',
                                ),
                                activityId: widget.activity.id,
                                ticketId: _ticketId!,
                                soldOut: _selectedTicket?.isSoldOut ?? false,
                                onChanged: (ActivityWaitlistStatus? value) {
                                  if (!mounted) return;
                                  setState(() => _waitlistStatus = value);
                                },
                                onInventoryMayHaveChanged: () {
                                  ref.invalidate(
                                    activityDetailProvider(widget.activity.id),
                                  );
                                },
                                onOpenRegistration: (int registrationId) {
                                  final GoRouter router = GoRouter.of(context);
                                  Navigator.of(context).pop();
                                  router.push('/ticket/$registrationId');
                                },
                              ),
                            FeeBreakdown(
                              ticket: _selectedTicket,
                              quote: _quote,
                              loading: _quoting,
                              error: _quoteError,
                              usePoints: _usePoints,
                              onRetry: _refreshQuote,
                              onTogglePoints: (_busy || _pending != null)
                                  ? null
                                  : (bool value) {
                                      setState(() => _usePoints = value);
                                      _refreshQuote();
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                    _CheckoutBottomBar(
                      submitError: _submitError,
                      consented: _consented,
                      busy: _busy,
                      pending: _pending != null,
                      quoteReady:
                          _quote?.payAmount != null &&
                          _quote!.quoteSign.isNotEmpty,
                      waitlistReady:
                          !_requiresWaitlistOffer || _hasWaitlistOffer,
                      actionLabel: _actionLabel,
                      onConsentChanged: (bool value) {
                        setState(() => _consented = value);
                      },
                      onSubmit: _submit,
                      onRetryPay: _retryPay,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Participant? _preferredParticipant(List<Participant> participants) {
    for (final Participant participant in participants) {
      if (participant.isDefault) return participant;
    }
    return participants.isEmpty ? null : participants.first;
  }
}

/// 单个文本输入:Cupertino 控件 + FormField 校验 + 出错时的红框与说明。
///
/// ★ 键盘类型、Action、自动填充提示都由调用方给:报名要填的是真名和手机号,
///   用错键盘(iOS 上是 name/phone 两套完全不同的键位)会直接影响填得对不对。
class _CupertinoValidatedField extends StatelessWidget {
  const _CupertinoValidatedField({
    required this.controller,
    required this.placeholder,
    required this.keyboardType,
    required this.textInputAction,
    required this.autofillHints,
    required this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String> autofillHints;
  final FormFieldValidator<String> validator;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return FormField<String>(
      initialValue: controller.text,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (FormFieldState<String> field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CupertinoTextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            autofillHints: autofillHints,
            autocorrect: keyboardType != TextInputType.phone,
            enableSuggestions: keyboardType != TextInputType.phone,
            padding: const EdgeInsets.all(CyTokens.space3),
            placeholder: placeholder,
            decoration: BoxDecoration(
              color: palette.bgSurfaceSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(
                color: field.hasError
                    ? CyTokens.statusDanger
                    : palette.borderSubtle,
              ),
            ),
            onChanged: field.didChange,
          ),
          if (field.errorText case final String error) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              error,
              style: CyType.footnote.copyWith(color: CyTokens.statusDanger),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParticipantSummary extends StatelessWidget {
  const _ParticipantSummary({
    required this.participant,
    required this.enabled,
    required this.onPressed,
  });

  final Participant? participant;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Participant? value = participant;
    return CupertinoButton(
      key: const Key('signup-participant-row'),
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      onPressed: enabled ? onPressed : null,
      child: value == null
          ? Text(
              '还没有参与人信息，点击新增',
              style: CyType.body.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            )
          : Row(
              children: <Widget>[
                Text(
                  value.fullName,
                  style: CyType.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: CyPalette.of(context).textPrimary,
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Text(
                  value.mobilePhone,
                  style: CyType.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SignupInlineError extends StatelessWidget {
  const _SignupInlineError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          '参与人信息没能加载',
          style: CyType.body.copyWith(
            color: CyPalette.of(context).textSecondary,
          ),
        ),
      ),
      CupertinoButton(onPressed: onRetry, child: const Text('重试')),
    ],
  );
}

class _CheckoutActivitySummary extends StatelessWidget {
  const _CheckoutActivitySummary({required this.activity});

  final ActivityDetail activity;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      ClipRRect(
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        child: SizedBox(
          width: 80,
          height: 60,
          child: (activity.imgUrl ?? '').isEmpty
              ? ColoredBox(
                  color: CyPalette.of(context).bgSurfaceSubtle,
                  child: Center(
                    child: Text(
                      '海报待同步',
                      style: CyType.footnote.copyWith(
                        color: CyPalette.of(context).textTertiary,
                      ),
                    ),
                  ),
                )
              : Image.network(
                  activity.imgUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: CyPalette.of(context).bgSurfaceSubtle,
                    child: const Center(child: Text('海报待同步')),
                  ),
                ),
        ),
      ),
      const SizedBox(width: CyTokens.space3),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              activity.name.isEmpty ? '活动信息待同步' : activity.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CyType.callout.copyWith(fontWeight: FontWeight.w700),
            ),
            if ((activity.startDate ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space1),
              Text(
                activity.startDate!,
                style: CyType.footnote.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ],
            const SizedBox(height: CyTokens.space1),
            Row(
              children: <Widget>[
                Icon(
                  CupertinoIcons.location_solid,
                  size: 14,
                  color: CyPalette.of(context).textTertiary,
                ),
                const SizedBox(width: CyTokens.space1),
                Expanded(
                  child: Text(
                    (activity.address ?? '').isEmpty
                        ? '待确认集合地点'
                        : activity.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CyType.footnote.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class _CheckoutBottomBar extends StatelessWidget {
  const _CheckoutBottomBar({
    required this.submitError,
    required this.consented,
    required this.busy,
    required this.pending,
    required this.quoteReady,
    required this.waitlistReady,
    required this.actionLabel,
    required this.onConsentChanged,
    required this.onSubmit,
    required this.onRetryPay,
  });

  final String? submitError;
  final bool consented;
  final bool busy;
  final bool pending;
  final bool quoteReady;
  final bool waitlistReady;
  final String actionLabel;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onSubmit;
  final VoidCallback onRetryPay;

  @override
  Widget build(BuildContext context) {
    // 姓名/手机号有没有填、填得对不对,由表单自己的 validator 判(_submit 里
    // 一次性 validate),不在这里再抄一遍正则 —— 两处判据迟早会分叉。
    final bool enabled = !busy && quoteReady && waitlistReady && consented;
    return Container(
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgPage,
        border: Border(
          top: BorderSide(color: CyPalette.of(context).borderSubtle),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space2,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (submitError case final String message) ...<Widget>[
              _SignupSubmitError(message: message, onRetry: onSubmit),
              const SizedBox(height: CyTokens.space2),
            ],
            Semantics(
              key: const Key('signup-data-consent'),
              container: true,
              checked: consented,
              enabled: !busy && !pending,
              label: '同意将姓名、手机号提供给主办方，用于报名核验',
              onTap: busy || pending
                  ? null
                  : () => onConsentChanged(!consented),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: busy || pending
                    ? null
                    : () => onConsentChanged(!consented),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: ExcludeSemantics(
                    child: Row(
                      children: <Widget>[
                        CupertinoCheckbox(
                          value: consented,
                          onChanged: busy || pending
                              ? null
                              : (bool? value) =>
                                    onConsentChanged(value ?? false),
                        ),
                        const SizedBox(width: CyTokens.space2),
                        Expanded(
                          child: Text(
                            '同意将姓名、手机号提供给主办方，用于报名核验',
                            style: CyType.footnote.copyWith(
                              color: CyPalette.of(context).textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space1),
            if (pending) ...<Widget>[
              Text(
                '订单已创建，完成支付后出票',
                style: CyType.footnote.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
            ],
            AnimatedOpacity(
              // 支付/禁用态的本地状态淡切 —— 走档位,别写死 180ms(T6 棘轮)。
              duration: CyMotion.standard,
              opacity: pending || enabled ? 1 : 0.28,
              child: CyNativeButton(
                key: const Key('signup-pay'),
                onPressed: pending
                    ? (busy ? null : onRetryPay)
                    : (enabled ? onSubmit : null),
                label: pending ? '去支付' : actionLabel,
                loading: busy,
                width: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignupSubmitError extends StatelessWidget {
  const _SignupSubmitError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      key: const Key('signup-submit-error'),
      constraints: const BoxConstraints(minHeight: CyTokens.btnH),
      padding: const EdgeInsets.only(left: CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.statusInfo.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.info_circle,
            color: CyTokens.statusInfo,
            size: 20,
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '这次报名还没完成',
                  style: CyType.body.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.footnote.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(88, 52),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
            onPressed: onRetry,
            child: Text(
              '重新提交',
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignupCheckoutSkeleton extends StatelessWidget {
  const _SignupCheckoutSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(CyTokens.pageX),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        _SignupSkeletonBlock(height: 134),
        SizedBox(height: CyTokens.space3),
        _SignupSkeletonBar(widthFactor: 0.60),
        SizedBox(height: CyTokens.space2),
        _SignupSkeletonBar(widthFactor: 0.35),
        SizedBox(height: CyTokens.space5),
        _SignupSkeletonBlock(height: 134),
        SizedBox(height: CyTokens.space3),
        _SignupSkeletonBar(widthFactor: 0.60),
        SizedBox(height: CyTokens.space2),
        _SignupSkeletonBar(widthFactor: 0.35),
      ],
    ),
  );
}

class _SignupSkeletonBlock extends StatelessWidget {
  const _SignupSkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSurfaceSubtle,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
    ),
  );
}

class _SignupSkeletonBar extends StatelessWidget {
  const _SignupSkeletonBar({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: Alignment.centerLeft,
    child: Container(
      height: 12,
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
    ),
  );
}

/// 活动 hero:封面 + 渐变遮罩 + 压在其上的标题与日期。
///
/// ★ 遮罩不是装饰,是**可读性的前提**:封面是用户上传的任意图片,
///   亮图上直接压白字会读不出来。小程序为此专门有 `.activity-hero__shade`,
///   值 `linear-gradient(180deg, rgba(0,0,0,0) 25%, rgba(0,0,0,.78) 100%)` ——
///   上四分之一全透明(不糊掉画面主体),底部压到 .78(保证文字够黑底)。
class _Hero extends StatelessWidget {
  const _Hero({required this.activity});

  final ActivityDetail activity;

  /// 小程序 `.activity-hero { min-height: 360rpx }` = 180pt。
  static const double _minHeight = 180;

  String get _statusText => switch (activity.status) {
    1 => '即将开始',
    2 => '报名中',
    3 => '进行中',
    4 => '结算中',
    5 || 6 => '已结束',
    9 => '已下线',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final String? start = activity.startDate;
    final String normalizedStart = start?.trim() ?? '';
    final String when = normalizedStart.length > 16
        ? normalizedStart.substring(0, 16)
        : normalizedStart;
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: _Cover(url: activity.imgUrl)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xC7000000)],
                  stops: <double>[0.25, 1.0],
                ),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: _minHeight),
            padding: const EdgeInsets.all(CyTokens.space4),
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_statusText.isNotEmpty) ...<Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[CyTag(label: _statusText)],
                  ),
                  const SizedBox(height: CyTokens.space2),
                ],
                Text(
                  activity.name.isEmpty ? '城市探索活动' : activity.name,
                  style: const TextStyle(
                    // .activity-hero__title:page-title 字号 + 700 + leading-tight
                    fontSize: CyTokens.typePageTitle,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
                if (when.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    when,
                    // .activity-hero__date:caption + opacity .86
                    style: const TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: Color(0xDBFFFFFF),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    // 对齐小程序 `.activity-hero__fallback`(wxss:7):surface-subtle 底 +
    // 图片图标 + 「封面待确认」。★ 此前这里画的是**一张假地图**(自绘街网 +
    // 橙色路线 + 5 个锚点),小程序没有这东西;它还是硬编码深蓝底
    // (`Color(0xFF111A2D)`),商家浅色视角下就是白页上的一块黑砖。
    final CyPalette palette = CyPalette.of(context);
    return CyNetImage(
      url,
      height: 180,
      width: double.infinity,
      fallback: SizedBox(
        height: 180,
        child: ColoredBox(
          color: palette.bgSurfaceSubtle,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  CupertinoIcons.photo,
                  // 真源 `<cy-icon name="image" size="48" />`,48rpx = 24pt
                  size: 24,
                  color: palette.textSecondary,
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  '封面待确认',
                  // `.activity-hero__fallback`:type-caption
                  style: CyType.caption2.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 费用明细 —— 对齐小程序 `pages/activity/baoming` 的分行明细。
///
/// ★ 它同时承担一个**非显示职责**:报价里的 `quoteSign` 是建单硬前置,
///   所以这块的加载/失败态直接决定提交按钮能不能点。失败必须给重试,
///   否则用户会卡在一个「什么都没说、按钮又是灰的」的死界面里。
/// 费用明细。★ 公开(而不是 `_FeeBreakdown`)只为一件事:
/// 让「金额没算出来时不许显示 ¥0.00」这条能被真渲染测到 ——
/// 通过整页 pump 要造一整套活动/报价替身,那条测试大概率不会有人写。
class FeeBreakdown extends StatelessWidget {
  const FeeBreakdown({
    super.key,
    this.ticket,
    required this.quote,
    required this.loading,
    required this.error,
    required this.usePoints,
    required this.onRetry,
    required this.onTogglePoints,
  });

  final ActivityTicket? ticket;
  final RegistrationQuote? quote;
  final bool loading;
  final String? error;
  final bool usePoints;
  final VoidCallback onRetry;
  final ValueChanged<bool>? onTogglePoints;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '没能取到价格:$error',
                style: CyType.footnote.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
            CupertinoButton(
              onPressed: onRetry,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final q = quote;
    if (q == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
        child: Text(
          '正在计算费用…',
          style: CyType.footnote.copyWith(
            color: CyPalette.of(context).textSecondary,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: CyTokens.space7),
        const CySectionTitle('费用明细'),
        const SizedBox(height: CyTokens.space3),
        if (ticket case final ActivityTicket value) ...<Widget>[
          _FeeRow(label: value.name, value: _formatMoney(value.price)),
          _FeeRow(label: '订单金额', value: _formatMoney(value.price)),
        ],
        if ((q.memberDiscountYuan ?? 0) > 0)
          _FeeRow(
            label: '俱乐部会员权益',
            value: '-¥${q.memberDiscountYuan!.toStringAsFixed(2)}',
          ),
        if ((q.couponDeductYuan ?? 0) > 0)
          _FeeRow(
            label: '优惠券',
            value: '-¥${q.couponDeductYuan!.toStringAsFixed(2)}',
          ),
        // 积分抵扣开关。★ 拨动会重新报价 —— 签名跟着变,不能沿用旧的。
        if (q.pointsUsable)
          MergeSemantics(
            child: Semantics(
              key: const Key('signup-points-toggle'),
              label: '积分抵扣',
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text('积分抵扣', style: CyType.body)),
                    if (usePoints && q.hasDeduction)
                      Padding(
                        padding: const EdgeInsets.only(right: CyTokens.space2),
                        child: Text(
                          '-¥${q.pointsDeductYuan!.toStringAsFixed(2)}(用 ${q.pointsUsed} 积分)',
                          style: CyType.footnote.copyWith(
                            color: CyPalette.of(context).textSecondary,
                          ),
                        ),
                      ),
                    CupertinoSwitch(
                      value: usePoints,
                      onChanged: loading ? null : onTogglePoints,
                    ),
                  ],
                ),
              ),
            ),
          ),
        // ★ 开了开关却一分没抵到,必须说清楚为什么,否则用户以为是 bug。
        if (q.pointsUsable && usePoints && !q.hasDeduction && !loading)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space2),
            child: Text(
              '当前积分不足以抵扣本单',
              style: CyType.footnote.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ),
        const SizedBox(height: CyTokens.space3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '总计',
              style: CyType.footnote.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              // ★ payAmount 为空 ≠ 免单。写 `?? 0` 会在付款按钮旁边
              //   摆一个「实付 ¥0.00」—— 那是本项目反复出现的
              //   「把没拿到说成没有」,而这次说的是钱。
              loading
                  ? '计算中…'
                  : (q.payAmount == null
                        ? '金额没算出来'
                        : _formatMoney(q.payAmount)),
              style: CyType.largeTitle.copyWith(
                fontWeight: FontWeight.w700,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatMoney(double? value) {
  if (value == null) return '—';
  // ★ 两位小数照实显示。省掉 `.00` 会把 ¥149.00 写成 ¥149,同一张结算页里
  //   票种行(走 ActivityTicket.priceText)却还是 ¥49.00 —— 同页两种写法。
  return '¥${value.toStringAsFixed(2)}';
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: CyType.body)),
          Text(
            value,
            style: CyType.body.copyWith(
              color: CyPalette.of(context).textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
