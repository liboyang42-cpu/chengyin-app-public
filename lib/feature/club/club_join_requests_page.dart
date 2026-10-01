import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_manage.dart';
import 'club_controller.dart';

/// 入会申请(主理人视角):待审批列表 + 通过/拒绝。
/// 对齐小程序 `pages/club/join-requests`:
/// - 通过:对方将成为正式成员并可进入群聊;
/// - 拒绝:对方不会获得成员权限,可以再次申请。
/// 处理成功后 invalidate 入会申请与俱乐部详情(详情页角标 pendingJoinRequestCount 同步减)。
class ClubJoinRequestsPage extends ConsumerStatefulWidget {
  const ClubJoinRequestsPage({super.key, required this.clubId});
  final int clubId;

  @override
  ConsumerState<ClubJoinRequestsPage> createState() =>
      _ClubJoinRequestsPageState();
}

class _ClubJoinRequestsPageState extends ConsumerState<ClubJoinRequestsPage> {
  int? _actingMemberId;

  Future<void> _review(JoinRequest request, bool approve) async {
    if (_actingMemberId != null) return;
    final memberId = request.memberId;
    final bool confirmed = await cyConfirm(
      context,
      title: approve ? stringsOf(context).clubJoinApproveTitle : stringsOf(context).clubJoinRejectTitle,
      content: approve ? stringsOf(context).clubJoinApproveBody : stringsOf(context).clubJoinRejectBody,
      confirmText: approve ? stringsOf(context).clubJoinApprove : stringsOf(context).clubJoinReject,
      danger: !approve,
    );
    if (!confirmed || !mounted) return;

    setState(() => _actingMemberId = memberId);
    try {
      await ref
          .read(clubApiProvider)
          .reviewJoinRequest(
            clubId: widget.clubId,
            memberId: memberId,
            approve: approve,
          );
      if (!mounted) return;
      ref.invalidate(clubJoinRequestsProvider(widget.clubId));
      ref.invalidate(clubDetailProvider(widget.clubId));
      CyNativeNotice.show(context, approve ? stringsOf(context).clubJoinApproved : stringsOf(context).clubJoinRejected);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _actingMemberId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(clubJoinRequestsProvider(widget.clubId));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubJoinRequestsTitle),
              Expanded(
                child: requests.when(
                  loading: () => const CySkeleton(),
                  error: (Object err, StackTrace st) => StatusView(
                    message: stringsOf(context).clubJoinUnavailable,
                    sub: stringsOf(context).clubPanelRetryNetwork,
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: () =>
                        ref.invalidate(clubJoinRequestsProvider(widget.clubId)),
                  ),
                  data: (List<JoinRequest> list) {
                    if (list.isEmpty) {
                      return StatusView(
                        message: stringsOf(context).clubJoinEmpty,
                        sub: stringsOf(context).clubJoinEmptyBody,
                        icon: CupertinoIcons.person_badge_plus,
                        large: true,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(CyTokens.space4),
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: CyTokens.space2),
                      itemBuilder: (context, i) => _RequestRow(
                        request: list[i],
                        busy: _actingMemberId == list[i].memberId,
                        onApprove: () => _review(list[i], true),
                        onReject: () => _review(list[i], false),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final JoinRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: Row(
          children: <Widget>[
            CyAvatar(
              url: request.avatar,
              fallback: (request.nickname?.isNotEmpty ?? false)
                  ? request.nickname!
                  : stringsOf(context).clubJoinAvatarFallback,
              size: 44,
            ),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    (request.nickname?.isNotEmpty ?? false)
                        ? request.nickname!
                        : stringsOf(context).clubJoinUser(request.memberId),
                    style: textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    (request.joinTime?.isEmpty ?? true)
                        ? stringsOf(context).clubJoinTimeUnknown
                        : request.requestTimeText,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            SizedBox(
              width: 64,
              height: 44,
              child: CupertinoButton(
                onPressed: busy ? null : onReject,
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space1,
                ),
                minimumSize: const Size(44, 44),
                child: Text(
                  stringsOf(context).clubJoinReject,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            SizedBox(
              width: 64,
              height: 44,
              child: CupertinoButton(
                onPressed: busy ? null : onApprove,
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space1,
                ),
                minimumSize: const Size(44, 44),
                color: CyTokens.actionPrimaryBg,
                foregroundColor: busy
                    ? CyTokens.textPlaceholder
                    : CyTokens.actionPrimaryFg,
                child: busy
                    ? const CupertinoActivityIndicator()
                    : Text(stringsOf(context).clubJoinApprove),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
