import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/strings.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_ops_api.dart';
import '../../data/models/club_ops.dart';
import 'club_login_gate.dart';
import 'club_ops_access.dart';
import 'club_ops_sections.dart';

/// 群发通知:选择受众 → 写内容 → **先预览受众** → 发送站内通知 → 失败项重试。
/// 对齐小程序 `pages/club/notify`(@90e66d70):
/// - 受众分组的禁用由权限决定(本场三组要 `club:event:operate`,其余要 `club:notify:send`);
/// - 人数只是行内装饰,算不出来不显示、也不弹 toast;
/// - 分群为空时**不创建空任务**(预览给「0 人」并禁发送);
/// - 回执 `phoneIncluded` 必须为 false —— 服务端越界下发手机号判回执坏了。
class ClubNotifyPage extends ConsumerStatefulWidget {
  const ClubNotifyPage({super.key, required this.clubId, this.activityId});

  final int clubId;
  final int? activityId;

  @override
  ConsumerState<ClubNotifyPage> createState() => _ClubNotifyPageState();
}

class _AudienceOption {
  const _AudienceOption({
    required this.value,
    required this.eventOnly,
    this.disabled = false,
    this.hint = '',
    this.countText = '',
  });

  final String value;
  final bool eventOnly;
  final bool disabled;
  final String hint;
  final String countText;

  _AudienceOption copyWith({
    bool? disabled,
    String? hint,
    String? countText,
  }) => _AudienceOption(
    value: value,
    eventOnly: eventOnly,
    disabled: disabled ?? this.disabled,
    hint: hint ?? this.hint,
    countText: countText ?? this.countText,
  );
}

enum _PreviewState { idle, loading, ready, empty, error }

class _ClubNotifyPageState extends ConsumerState<ClubNotifyPage> {
  static const List<_AudienceOption> _baseAudiences = <_AudienceOption>[
    _AudienceOption(value: 'ALL_MEMBERS', eventOnly: false),
    _AudienceOption(value: 'ADMINS', eventOnly: false),
    _AudienceOption(
      value: 'REGISTERED',

      eventOnly: true,
    ),
    _AudienceOption(value: 'WAITLIST', eventOnly: true),
    _AudienceOption(value: 'NO_SHOW', eventOnly: true),
    _AudienceOption(
      value: 'INACTIVE',

      eventOnly: false,
    ),
  ];

  String _audienceLabel(String value) => switch (value) {
    'ALL_MEMBERS' => stringsOf(context).notificationAllMembers,
    'ADMINS' => stringsOf(context).notificationAdmins,
    'REGISTERED' => stringsOf(context).notificationRegistered,
    'WAITLIST' => stringsOf(context).notificationWaitlist,
    'NO_SHOW' => stringsOf(context).notificationNoShow,
    'INACTIVE' => stringsOf(context).notificationInactive,
    _ => value,
  };

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();

  ClubOpsLoadState _state = ClubOpsLoadState.loading;
  String _error = '';
  bool _loginRequired = false;
  List<_AudienceOption> _audiences = _baseAudiences;
  String _audienceType = 'ALL_MEMBERS';
  _PreviewState _previewState = _PreviewState.idle;
  int _recipientCount = 0;
  String _previewError = '';
  bool _sending = false;
  bool _retrying = false;
  bool _refreshingCampaign = false;
  NotificationCampaign? _campaign;
  String _draftRequestId = '';

  int? get _activityId => widget.activityId;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    setState(() {
      _state = ClubOpsLoadState.loading;
      _error = '';
      _loginRequired = false;
    });
    try {
      final ClubOpsAccess access = await ref
          .read(clubOpsApiProvider)
          .access(clubId: widget.clubId, activityId: _activityId);
      if (!mounted) return;
      final bool canNotifyAllMembers = access.has(kClubNotifySend);
      final bool canOperateEvent =
          _activityId != null && access.has(kClubEventOperate);
      final String? denied = clubOpsDenyReason(
        access,
        clubId: widget.clubId,
        allowed: (ClubOpsAccess a) =>
            a.has(kClubNotifySend) ||
            (_activityId != null && a.has(kClubEventOperate)),
        deniedMessage: stringsOf(context).notificationDeniedRole,
      );
      if (denied != null) {
        setState(() {
          _state = ClubOpsLoadState.noPermission;
          _error = !access.active || access.clubId != widget.clubId
              ? stringsOf(context).notificationNotMember
              : denied;
        });
        return;
      }
      final List<_AudienceOption> audiences = _baseAudiences
          .map(
            (_AudienceOption item) => item.copyWith(
              disabled: item.eventOnly
                  ? !canOperateEvent
                  : !canNotifyAllMembers,
              hint: item.eventOnly
                  ? (_activityId == null
                        ? stringsOf(context).notificationNeedsEvent
                        : (canOperateEvent ? '' : stringsOf(context).notificationDeniedEvent))
                  : '',
            ),
          )
          .toList();
      setState(() {
        _state = ClubOpsLoadState.ready;
        _audiences = audiences;
        // 带活动进来且能操作本场时默认选「本场已报名」。
        _audienceType = (_activityId != null && canOperateEvent)
            ? 'REGISTERED'
            : 'ALL_MEMBERS';
      });
      // 人数拉取放在权限确认之后,不是 initState —— 提前发等于让没权限的人平白吃一个 403。
      await _loadAudienceCounts();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).notificationAccessUnavailable);
      });
    }
  }

  Future<void> _loadAudienceCounts() async {
    try {
      final AudienceCounts? counts = await ref
          .read(clubOpsApiProvider)
          .audienceCounts(clubId: widget.clubId, activityId: _activityId);
      if (!mounted || counts == null) return;
      setState(() {
        _audiences = _audiences
            .map(
              (_AudienceOption item) => item.copyWith(
                countText:
                    counts.counts[item.value] == null
                    ? ''
                    : stringsOf(context).notificationAudienceCount(counts.counts[item.value]!),
              ),
            )
            .toList();
      });
    } catch (_) {
      // 人数是这一行的装饰,算不出来就不显示。为它弹 toast 是噪音。
    }
  }

  void _resetDraft() {
    setState(() {
      _previewState = _PreviewState.idle;
      _campaign = null;
      _draftRequestId = '';
      _previewError = '';
    });
  }

  void _chooseAudience(_AudienceOption option) {
    if (_sending || _retrying || option.disabled) return;
    setState(() {
      _audienceType = option.value;
      _previewState = _PreviewState.idle;
      _campaign = null;
      _draftRequestId = '';
    });
  }

  bool get _draftValid {
    final String title = _titleCtrl.text.trim();
    final String content = _contentCtrl.text.trim();
    if (title.isEmpty || title.length > 80) {
      CyNativeNotice.show(context, stringsOf(context).notificationTitleValidation, isError: true);
      return false;
    }
    if (content.isEmpty || content.length > 1000) {
      CyNativeNotice.show(context, stringsOf(context).notificationContentValidation, isError: true);
      return false;
    }
    return true;
  }

  Future<void> _preview() async {
    if (!_draftValid ||
        _previewState == _PreviewState.loading ||
        _sending) {
      return;
    }
    setState(() {
      _previewState = _PreviewState.loading;
      _previewError = '';
      _campaign = null;
    });
    try {
      final NotificationPreview? preview = await ref
          .read(clubOpsApiProvider)
          .notificationPreview(
            clubId: widget.clubId,
            activityId: _activityId,
            audienceType: _audienceType,
            title: _titleCtrl.text.trim(),
            content: _contentCtrl.text.trim(),
          );
      if (!mounted) return;
      if (preview == null) {
        setState(() {
          _previewState = _PreviewState.error;
          _previewError = stringsOf(context).notificationPreviewUnavailable;
        });
        return;
      }
      setState(() {
        _recipientCount = preview.recipientCount;
        _previewState = preview.recipientCount == 0
            ? _PreviewState.empty
            : _PreviewState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewState = _PreviewState.error;
        _previewError = clubOpsErrorMessage(error, stringsOf(context).notificationPreviewUnavailable);
      });
    }
  }

  Future<void> _send() async {
    if (!_draftValid ||
        _previewState != _PreviewState.ready ||
        _sending) {
      return;
    }
    final String requestId = _draftRequestId.isNotEmpty
        ? _draftRequestId
        : ClubOpsApi.newRequestId('campaign');
    setState(() {
      _sending = true;
      _draftRequestId = requestId;
    });
    try {
      final NotificationCampaign? campaign = await ref
          .read(clubOpsApiProvider)
          .notificationSend(
            clubId: widget.clubId,
            activityId: _activityId,
            audienceType: _audienceType,
            title: _titleCtrl.text.trim(),
            content: _contentCtrl.text.trim(),
            requestId: requestId,
          );
      if (!mounted) return;
      if (campaign == null) {
        CyNativeNotice.show(context, stringsOf(context).notificationSendFailed, isError: true);
        return;
      }
      setState(() => _campaign = campaign);
      CyNativeNotice.show(
        context,
        campaign.failedCount > 0
            ? stringsOf(context).notificationPartiallyFailed
            : campaign.successCount < campaign.totalCount
            ? stringsOf(context).notificationSubmitted
            : stringsOf(context).notificationSent,
        isError: campaign.failedCount > 0,
      );
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).networkError),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshCampaign() async {
    final campaign = _campaign;
    if (campaign == null || _refreshingCampaign || _retrying || _sending) return;
    setState(() => _refreshingCampaign = true);
    try {
      final refreshed = await ref.read(clubOpsApiProvider)
          .notificationStatus(campaignId: campaign.id);
      if (!mounted || _campaign?.id != campaign.id) return;
      if (refreshed == null || refreshed.id != campaign.id) {
        CyNativeNotice.show(context, stringsOf(context).notificationStatusUnavailable, isError: true);
        return;
      }
      setState(() => _campaign = refreshed);
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(context,
        clubOpsErrorMessage(error, stringsOf(context).notificationStatusUnavailable), isError: true);
    } finally {
      if (mounted) setState(() => _refreshingCampaign = false);
    }
  }

  Future<void> _retryFailed() async {
    final NotificationCampaign? campaign = _campaign;
    if (campaign == null || _retrying || _refreshingCampaign ||
        campaign.failedCount <= 0) return;
    setState(() => _retrying = true);
    try {
      final NotificationCampaign? retried = await ref
          .read(clubOpsApiProvider)
          .notificationRetry(campaignId: campaign.id);
      if (!mounted) return;
      if (retried == null) {
        CyNativeNotice.show(context, stringsOf(context).notificationRetryFailed, isError: true);
        return;
      }
      setState(() => _campaign = retried);
      CyNativeNotice.show(
        context,
        retried.failedCount > 0 ? stringsOf(context).notificationFailuresRemain : stringsOf(context).notificationRetried,
        isError: retried.failedCount > 0,
      );
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).networkError),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              CyPageTitle(stringsOf(context).notificationTitle),
              Expanded(child: _body()),
              if (_state == ClubOpsLoadState.ready)
                CyFooterBar(
                  primary: CyNativeButton(
                    key: const Key('notify-send'),
                    label: _sending ? stringsOf(context).notificationSending : stringsOf(context).notificationSend,
                    width: double.infinity,
                    onPressed: (_sending || _previewState != _PreviewState.ready)
                        ? null
                        : _send,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    // 游客先登录:401 说成「你没有发通知的权限」会让人去查自己的角色,
    // 而真因只是没登录 —— 登录后原地重取,人留在这一页。
    if (_loginRequired) {
      return ClubLoginGate(
        message: stringsOf(context).notificationLogin,
        onSignedIn: _loadAccess,
      );
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: stringsOf(context).notificationNoPermission,
          sub: _error.isEmpty
              ? stringsOf(context).notificationPermissionHint
              : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: stringsOf(context).notificationNetworkFailed,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _loadAccess,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: stringsOf(context).notificationUnavailable,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _loadAccess,
        );
      case ClubOpsLoadState.ready:
        return _readyBody();
    }
  }

  Widget _readyBody() {
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space6),
      children: <Widget>[
        ClubOpsSection(
          title: stringsOf(context).notificationChooseAudience,
          children: <Widget>[
            ClubOpsCard(
              children: _audiences
                  .map(
                    (_AudienceOption item) => ClubOpsRow(
                      key: Key('notify-audience-${item.value}'),
                      title: _audienceLabel(item.value),
                      meta: item.hint.isEmpty ? null : item.hint,
                      value: item.countText.isEmpty ? null : item.countText,
                      trailing: Text(
                        _audienceType == item.value ? stringsOf(context).notificationSelected : stringsOf(context).notificationSelect,
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: _audienceType == item.value
                              ? palette.brand
                              : palette.textTertiary,
                        ),
                      ),
                      enabled: !item.disabled && !_sending && !_retrying,
                      onTap: () => _chooseAudience(item),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        ClubOpsSection(
          title: stringsOf(context).notificationContent,
          children: <Widget>[
            ClubOpsCard(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.space4,
                    CyTokens.space3,
                    CyTokens.space4,
                    CyTokens.space3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CyField(
                        label: stringsOf(context).notificationDraftTitle,
                        child: _OpsTextField(
                          key: const Key('notify-title'),
                          controller: _titleCtrl,
                          placeholder: stringsOf(context).notificationTitleHint,
                          maxLength: 80,
                          onChanged: (_) => _resetDraft(),
                        ),
                      ),
                      CyField(
                        label: stringsOf(context).notificationContent,
                        child: _OpsTextField(
                          key: const Key('notify-content'),
                          controller: _contentCtrl,
                          placeholder: stringsOf(context).notificationContentHint,
                          maxLength: 1000,
                          maxLines: 5,
                          onChanged: (_) => _resetDraft(),
                        ),
                      ),
                      _previewButton(palette),
                      if (_previewState == _PreviewState.error)
                        _previewCard(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  _previewError,
                                  style: TextStyle(
                                    fontSize: CyTokens.typeLabel,
                                    color: CyTokens.statusDanger,
                                  ),
                                ),
                              ),
                              ClubOpsRowLink(
                                label: stringsOf(context).retry,
                                onTap: _preview,
                                enabled:
                                    _previewState != _PreviewState.loading &&
                                    !_sending,
                              ),
                            ],
                          ),
                        ),
                      if (_previewState == _PreviewState.empty)
                        _previewCard(
                          child: Text(
                            stringsOf(context).notificationEmptyAudience,
                            style: TextStyle(
                              fontSize: CyTokens.typeLabel,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      if (_previewState == _PreviewState.ready)
                        _previewCard(
                          child: Text(
                            stringsOf(context).notificationPreviewSummary(_recipientCount),
                            style: TextStyle(
                              fontSize: CyTokens.typeLabel,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_campaign != null)
          ClubOpsSection(
            title: stringsOf(context).notificationDeliveryStatus,
            children: <Widget>[
              ClubOpsCard(
                children: <Widget>[
                  ClubOpsRow(
                    title: stringsOf(context).notificationTotal,
                    value: '${_campaign!.totalCount}',
                    valueColor: palette.textPrimary,
                  ),
                  ClubOpsRow(
                    title: stringsOf(context).notificationDelivered,
                    value: '${_campaign!.successCount}',
                    valueColor: CyTokens.statusSuccess,
                  ),
                  ClubOpsRow(
                    title: stringsOf(context).notificationFailed,
                    meta: _campaign!.failedCount > 0 ? stringsOf(context).retry : null,
                    value: '${_campaign!.failedCount}',
                    valueColor: CyTokens.statusDanger,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(CyTokens.space3),
                    child: CyNativeButton(
                      key: const Key('notify-refresh'),
                      label: _refreshingCampaign ? stringsOf(context).notificationRefreshing : stringsOf(context).notificationRefresh,
                      role: CyNativeButtonRole.secondary,
                      onPressed: _refreshingCampaign || _retrying || _sending
                          ? null : _refreshCampaign,
                    ),
                  ),
                  if (_campaign!.failedCount > 0)
                    Padding(
                      padding: const EdgeInsets.all(CyTokens.space3),
                      child: CyNativeButton(
                        key: const Key('notify-retry'),
                        label: _retrying ? stringsOf(context).notificationRetrying : stringsOf(context).notificationRetryFailedOnly,
                        role: CyNativeButtonRole.secondary,
                        width: double.infinity,
                        onPressed: _retrying || _refreshingCampaign ? null : _retryFailed,
                      ),
                    ),
                ],
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            0,
          ),
          child: Text(
            stringsOf(context).notificationPrivacyHint,
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              height: 1.5,
              color: palette.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewButton(CyPalette palette) {
    final bool busy = _previewState == _PreviewState.loading;
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space1),
      child: CyNativeButton(
        key: const Key('notify-preview'),
        label: busy ? stringsOf(context).notificationPreviewing : stringsOf(context).notificationPreview,
        role: CyNativeButtonRole.secondary,
        width: double.infinity,
        onPressed: (busy || _sending) ? null : _preview,
      ),
    );
  }

  Widget _previewCard({required Widget child}) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: CyTokens.space2),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
      child: child,
    );
  }
}

/// 通知表单输入框:走 CyPalette 双值,不用 Material 默认外观。
class _OpsTextField extends StatelessWidget {
  const _OpsTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.maxLength,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String placeholder;
  final int maxLength;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      maxLength: maxLength,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(
        fontSize: CyTokens.typeBody,
        color: palette.textPrimary,
      ),
      placeholderStyle: TextStyle(
        fontSize: CyTokens.typeBody,
        color: palette.textPlaceholder,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2_5,
        vertical: CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: palette.inputBgEmpty,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        border: Border.all(color: palette.borderSubtle),
      ),
    );
  }
}
