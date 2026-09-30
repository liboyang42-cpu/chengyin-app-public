import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/models/club.dart';
import 'club_controller.dart';

/// 能不能把这一行移除。
///
/// ★★★ 两条闸缺一不可(后端 ApiClubController):
///   · **只有创建者**能移除,role==1 的管理员不能(577-579)
///   · **创建者本人不能被移除**(会回「不能移除俱乐部创建者」)
/// 把入口给管理员看 = 摆一个点下去必被拒的按钮。
bool canRemoveClubMember({
  required bool viewerIsCreator,
  required ClubMember member,
}) => viewerIsCreator && !member.isOwner;

/// 能不能给这一行设/取消管理员。
///
/// ⚠️ 创建者不需要给自己设(后端回「创建者无需设置角色」)。
bool canSetClubMemberRole({
  required bool viewerIsCreator,
  required ClubMember member,
}) => viewerIsCreator && !member.isOwner;

/// 成员行的直接管理入口(权限 / 临时封禁 / 移除)。不能管时整块不存在。
class ClubMemberActions extends ConsumerStatefulWidget {
  const ClubMemberActions({
    super.key,
    required this.clubId,
    required this.member,
    required this.viewerIsCreator,
    this.canGovernMembers = false,
    this.confirmPresenter,
  });

  final int clubId;
  final ClubMember member;
  final bool viewerIsCreator;

  /// 行右缘「临时封禁」:主理人或持 `club:member:manage` 的人可进
  /// (真源 cset 面板 wxml:776 + goMemberGovernance js:2076)。
  final bool canGovernMembers;
  final CyNativeConfirmPresenter? confirmPresenter;

  @override
  ConsumerState<ClubMemberActions> createState() => _ClubMemberActionsState();
}

class _ClubMemberActionsState extends ConsumerState<ClubMemberActions> {
  bool _busy = false;

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, msg, isError: isError);
  }

  Future<void> _run(
    Future<String> Function() action, {
    bool refreshDetail = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String msg = await action();
      ref.invalidate(clubMembersProvider(widget.clubId));
      if (refreshDetail) ref.invalidate(clubDetailProvider(widget.clubId));
      // ★ 原样显示后端那句话。它可能是「管理员最多 2 个,请先取消其他管理员」——
      //   那句带着**可执行信息**,吞成「设置失败」等于把出路也一起吞了。
      _toast(msg);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRole(ClubMember member) async {
    final bool ok = await cyConfirm(
      context,
      title: member.isAdmin ? '取消管理员' : '设为管理员',
      content: member.isAdmin
          ? '取消后，对方将不能再删除他人违规内容或现场出示团码。确认取消？'
          : '管理员可协助删除违规内容、现场出示团码。确认设置？',
      nativePresenter: widget.confirmPresenter,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref
          .read(clubApiProvider)
          .setMemberRole(
            clubId: widget.clubId,
            memberId: member.memberId,
            admin: !member.isAdmin,
          ),
    );
  }

  Future<void> _remove(ClubMember member) async {
    final bool ok = await cyConfirm(
      context,
      title: '移除成员',
      content: '确定将该成员移出俱乐部?',
      danger: true,
      nativePresenter: widget.confirmPresenter,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref
          .read(clubApiProvider)
          .removeMember(clubId: widget.clubId, memberId: member.memberId),
      refreshDetail: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ClubMember m = widget.member;
    final bool canRole = canSetClubMemberRole(
      viewerIsCreator: widget.viewerIsCreator,
      member: m,
    );
    final bool canRemove = canRemoveClubMember(
      viewerIsCreator: widget.viewerIsCreator,
      member: m,
    );
    // 创建者本人不能被封(js:2080 与 club.memberId 比对);App 里 member.isOwner
    // 就是那条判据。
    final bool canBan = widget.canGovernMembers && !m.isOwner;
    if (!canRole && !canRemove && !canBan) return const SizedBox.shrink();

    final TextStyle labelStyle = TextStyle(
      fontSize: CyTokens.typeLabel,
      fontWeight: FontWeight.w500,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (canRole)
          Semantics(
            label: m.isAdmin ? '取消管理' : '设管理',
            button: true,
            child: CupertinoButton(
              key: Key('member-role-${m.memberId}'),
              minimumSize: const Size(44, CyTokens.btnH),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _busy ? null : () => _setRole(m),
              child: ExcludeSemantics(
                child: Text(m.isAdmin ? '取消管理' : '设管理', style: labelStyle),
              ),
            ),
          ),
        if (canBan)
          Semantics(
            label: '临时封禁',
            button: true,
            child: CupertinoButton(
              key: Key('member-governance-${m.memberId}'),
              minimumSize: const Size(44, CyTokens.btnH),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _busy
                  ? null
                  : () => context.push(
                      '/club/${widget.clubId}/governance?memberId=${m.memberId}',
                    ),
              child: ExcludeSemantics(child: Text('临时封禁', style: labelStyle)),
            ),
          ),
        if (canRemove)
          Semantics(
            label: '移除',
            button: true,
            child: CupertinoButton(
              key: Key('member-remove-${m.memberId}'),
              minimumSize: const Size(44, CyTokens.btnH),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _busy ? null : () => _remove(m),
              child: ExcludeSemantics(
                child: Text(
                  '移除',
                  style: labelStyle.copyWith(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
