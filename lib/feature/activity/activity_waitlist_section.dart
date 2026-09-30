import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../data/api/activity_waitlist_api.dart';
import '../../data/models/activity_waitlist.dart';

/// 报名 Sheet 内的候补区。只有售罄或已存在候补/报名状态时才显示。
class ActivityWaitlistSection extends ConsumerStatefulWidget {
  const ActivityWaitlistSection({
    super.key,
    required this.activityId,
    required this.ticketId,
    required this.soldOut,
    required this.onChanged,
    this.api,
    this.onOpenRegistration,
    this.onInventoryMayHaveChanged,
  });

  final int activityId;
  final int ticketId;
  final bool soldOut;
  final ValueChanged<ActivityWaitlistStatus?> onChanged;
  final ActivityWaitlistGateway? api;
  final ValueChanged<int>? onOpenRegistration;
  final VoidCallback? onInventoryMayHaveChanged;

  @override
  ConsumerState<ActivityWaitlistSection> createState() =>
      _ActivityWaitlistSectionState();
}

class _ActivityWaitlistSectionState
    extends ConsumerState<ActivityWaitlistSection> {
  ActivityWaitlistStatus? _status;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int _generation = 0;
  Timer? _offerTimer;

  ActivityWaitlistGateway get _api =>
      widget.api ?? ref.read(activityWaitlistApiProvider);

  @override
  void initState() {
    super.initState();
    _load(showLoading: false);
  }

  @override
  void didUpdateWidget(covariant ActivityWaitlistSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activityId == widget.activityId &&
        oldWidget.ticketId == widget.ticketId) {
      return;
    }
    _offerTimer?.cancel();
    _status = null;
    _error = null;
    _loading = true;
    widget.onChanged(null);
    _load(showLoading: false);
  }

  @override
  void dispose() {
    _generation += 1;
    _offerTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    final int generation = ++_generation;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final ActivityWaitlistStatus value = await _api.status(
        activityId: widget.activityId,
        ticketId: widget.ticketId,
      );
      if (!mounted || generation != _generation) return;
      _apply(value);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = _message(error, '候补状态加载失败');
      });
      widget.onChanged(null);
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    final int activityId = widget.activityId;
    final int ticketId = widget.ticketId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ActivityWaitlistStatus value = await _api.join(
        activityId: activityId,
        ticketId: ticketId,
      );
      if (!mounted ||
          activityId != widget.activityId ||
          ticketId != widget.ticketId) {
        return;
      }
      _apply(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error, '加入候补失败'));
      widget.onChanged(null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final bool confirmed = await cyConfirm(
      context,
      title: '退出候补',
      content: _status?.state == ActivityWaitlistState.offered
          ? '退出后，已为你保留的名额会立即让给下一位。'
          : '退出后将离开当前候补队列。',
      confirmText: '退出候补',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final int activityId = widget.activityId;
    final int ticketId = widget.ticketId;
    final bool releasedOffer = _status?.state == ActivityWaitlistState.offered;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ActivityWaitlistStatus value = await _api.cancel(
        activityId: activityId,
        ticketId: ticketId,
      );
      if (!mounted ||
          activityId != widget.activityId ||
          ticketId != widget.ticketId) {
        return;
      }
      _apply(value);
      if (releasedOffer) widget.onInventoryMayHaveChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error, '退出候补失败'));
      widget.onChanged(null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(ActivityWaitlistStatus value) {
    _offerTimer?.cancel();
    setState(() {
      _status = value;
      _error = null;
      _loading = false;
    });
    widget.onChanged(value);
    final DateTime? expiresAt = value.offerExpiresAt;
    if (!value.hasActiveOffer || expiresAt == null) return;
    final Duration delay = expiresAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _load();
      return;
    }
    _offerTimer = Timer(delay + const Duration(milliseconds: 50), _load);
  }

  String _message(Object error, String fallback) =>
      error is ActivityWaitlistException ? error.message : fallback;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      if (!widget.soldOut) return const SizedBox.shrink();
      return _WaitlistSurface(
        child: Semantics(
          container: true,
          liveRegion: true,
          label: '正在读取候补状态',
          child: ExcludeSemantics(
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      );
    }
    final ActivityWaitlistStatus? status = _status;
    final bool shouldShow =
        widget.soldOut ||
        (status != null && status.state != ActivityWaitlistState.none) ||
        status?.eligibility == ActivityWaitlistEligibility.alreadyRegistered;
    if (!shouldShow) return const SizedBox.shrink();
    if (_error != null) {
      return _WaitlistSurface(
        child: _WaitlistContent(
          title: '候补状态读取失败',
          detail: _error!,
          actions: <Widget>[
            CyNativeButton(
              label: '重试',
              onPressed: _busy ? null : _load,
              loading: _busy,
              width: double.infinity,
            ),
          ],
        ),
      );
    }
    if (status == null) return const SizedBox.shrink();
    final _WaitlistCopy copy = _copy(status);
    return _WaitlistSurface(
      child: _WaitlistContent(
        title: copy.title,
        detail: copy.detail,
        actions: _actions(status),
      ),
    );
  }

  List<Widget> _actions(ActivityWaitlistStatus status) {
    if (widget.soldOut && status.canJoin) {
      return <Widget>[
        CyNativeButton(
          label: '加入候补',
          onPressed: _busy ? null : _join,
          loading: _busy,
          width: double.infinity,
        ),
      ];
    }
    if (status.state == ActivityWaitlistState.waiting) {
      return <Widget>[
        CyNativeButton(
          label: '刷新状态',
          onPressed: _busy ? null : _load,
          role: CyNativeButtonRole.secondary,
          width: double.infinity,
        ),
        CyNativeButton(
          label: '退出候补',
          onPressed: _busy ? null : _cancel,
          role: CyNativeButtonRole.destructive,
          loading: _busy,
          width: double.infinity,
        ),
      ];
    }
    if (status.state == ActivityWaitlistState.offered) {
      return <Widget>[
        CyNativeButton(
          label: '放弃名额',
          onPressed: _busy ? null : _cancel,
          role: CyNativeButtonRole.destructive,
          loading: _busy,
          width: double.infinity,
        ),
      ];
    }
    final int? registrationId = status.registrationId;
    if ((status.state == ActivityWaitlistState.claimed ||
            status.state == ActivityWaitlistState.converted) &&
        registrationId != null &&
        widget.onOpenRegistration != null) {
      return <Widget>[
        CyNativeButton(
          label: '查看报名订单',
          onPressed: () => widget.onOpenRegistration!(registrationId),
          width: double.infinity,
        ),
      ];
    }
    return const <Widget>[];
  }
}

class _WaitlistSurface extends StatelessWidget {
  const _WaitlistSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('activity-waitlist-card'),
    constraints: const BoxConstraints(minHeight: 88),
    margin: const EdgeInsets.only(bottom: CyTokens.space3),
    padding: const EdgeInsets.all(CyTokens.space4),
    decoration: BoxDecoration(
      color: CyPalette.of(context).bgSurface,
      border: Border.all(color: CyPalette.of(context).cardBorder),
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
    ),
    child: child,
  );
}

class _WaitlistContent extends StatelessWidget {
  const _WaitlistContent({
    required this.title,
    required this.detail,
    required this.actions,
  });

  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$title。$detail',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            title,
            style: CyType.headline.copyWith(
              color: CyPalette.of(context).textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        ExcludeSemantics(
          child: Text(
            detail,
            style: CyType.footnote.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ),
        for (final Widget action in actions) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          action,
        ],
      ],
    ),
  );
}

class _WaitlistCopy {
  const _WaitlistCopy(this.title, this.detail);

  final String title;
  final String detail;
}

_WaitlistCopy _copy(ActivityWaitlistStatus status) {
  switch (status.eligibility) {
    case ActivityWaitlistEligibility.noSeries:
      return const _WaitlistCopy('本活动未配置候补', '票满后暂不提供排队，请关注其他票种或场次。');
    case ActivityWaitlistEligibility.waitlistClosed:
      return const _WaitlistCopy('本场候补已关闭', '当前不能新加入候补。');
    case ActivityWaitlistEligibility.notMember:
      return const _WaitlistCopy('仅俱乐部成员可候补', '加入俱乐部并保持正常成员状态后才能候补。');
    case ActivityWaitlistEligibility.alreadyRegistered:
      return const _WaitlistCopy('你已有该票种报名', '无需重复候补，请从报名订单继续处理。');
    case ActivityWaitlistEligibility.blocked:
      return const _WaitlistCopy('当前无法参与候补', '你的俱乐部参与资格当前不可用。');
    case ActivityWaitlistEligibility.eligible:
      break;
  }
  switch (status.state) {
    case ActivityWaitlistState.waiting:
      return const _WaitlistCopy('候补排队中', '有名额时系统会按加入顺序保留，请稍后刷新。');
    case ActivityWaitlistState.offered:
      final DateTime? expiresAt = status.offerExpiresAt;
      final String deadline = expiresAt == null
          ? '保留时间内'
          : _deadline(expiresAt);
      return _WaitlistCopy('名额已为你保留', '请在 $deadline 完成报名；下单后以支付结果为准。');
    case ActivityWaitlistState.claimed:
      return const _WaitlistCopy('已生成待支付报名单', '库存已归报名订单管理，请在订单有效期内完成支付。');
    case ActivityWaitlistState.converted:
      return const _WaitlistCopy('报名已确认', '支付结果已确认，名额已转为正式报名。');
    case ActivityWaitlistState.cancelled:
      return const _WaitlistCopy('已退出候补', '本票种仍已满，如仍需参加可重新加入候补。');
    case ActivityWaitlistState.expired:
      return const _WaitlistCopy('候补名额已过期', '本票种仍已满，如仍需参加可重新加入候补。');
    case ActivityWaitlistState.none:
      return const _WaitlistCopy('本票种已满', '加入后按先到先得顺序候补；名额保留有时限。');
  }
}

String _deadline(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}
