import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
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
    required this.label,
    required this.eventOnly,
    this.disabled = false,
    this.hint = '',
    this.countText = '',
  });

  final String value;
  final String label;
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
    label: label,
    eventOnly: eventOnly,
    disabled: disabled ?? this.disabled,
    hint: hint ?? this.hint,
    countText: countText ?? this.countText,
  );
}

enum _PreviewState { idle, loading, ready, empty, error }

class _ClubNotifyPageState extends ConsumerState<ClubNotifyPage> {
  static const List<_AudienceOption> _baseAudiences = <_AudienceOption>[
    _AudienceOption(value: 'ALL_MEMBERS', label: '全部成员', eventOnly: false),
    _AudienceOption(value: 'ADMINS', label: '管理员', eventOnly: false),
    _AudienceOption(
      value: 'REGISTERED',
      label: '本场已报名',
      eventOnly: true,
    ),
    _AudienceOption(value: 'WAITLIST', label: '本场候补', eventOnly: true),
    _AudienceOption(value: 'NO_SHOW', label: '本场未到场', eventOnly: true),
    _AudienceOption(
      value: 'INACTIVE',
      label: '近 90 天未活跃',
      eventOnly: false,
    ),
  ];

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
        deniedMessage: '当前角色没有成员通知权限',
      );
      if (denied != null) {
        setState(() {
          _state = ClubOpsLoadState.noPermission;
          _error = denied;
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
                        ? '从具体活动进入后才可选'
                        : (canOperateEvent ? '' : '当前角色没有本场通知权限'))
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
        _error = clubOpsErrorMessage(error, '通知权限暂时不可用');
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
                    : '${counts.counts[item.value]} 人',
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
      CyNativeNotice.show(context, '标题需为 1–80 字', isError: true);
      return false;
    }
    if (content.isEmpty || content.length > 1000) {
      CyNativeNotice.show(context, '内容需为 1–1000 字', isError: true);
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
          _previewError = '受众预览不可用';
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
        _previewError = clubOpsErrorMessage(error, '受众预览不可用');
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
        CyNativeNotice.show(context, '通知发送失败', isError: true);
        return;
      }
      setState(() => _campaign = campaign);
      CyNativeNotice.show(
        context,
        campaign.failedCount > 0 ? '部分发送失败' : '站内通知已发送',
        isError: campaign.failedCount > 0,
      );
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '网络异常，请稍后重试'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retryFailed() async {
    final NotificationCampaign? campaign = _campaign;
    if (campaign == null || _retrying || campaign.failedCount <= 0) return;
    setState(() => _retrying = true);
    try {
      final NotificationCampaign? retried = await ref
          .read(clubOpsApiProvider)
          .notificationRetry(campaignId: campaign.id);
      if (!mounted) return;
      if (retried == null) {
        CyNativeNotice.show(context, '重试失败', isError: true);
        return;
      }
      setState(() => _campaign = retried);
      CyNativeNotice.show(
        context,
        retried.failedCount > 0 ? '仍有失败项' : '失败项已重试',
        isError: retried.failedCount > 0,
      );
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '网络异常，请稍后重试'),
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
              const CyPageTitle('群发通知'),
              Expanded(child: _body()),
              if (_state == ClubOpsLoadState.ready)
                CyFooterBar(
                  primary: CyNativeButton(
                    key: const Key('notify-send'),
                    label: _sending ? '正在投递…' : '发送站内通知',
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
        message: '登录后查看群发通知',
        onSignedIn: _loadAccess,
      );
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: '你没有发通知的权限',
          sub: _error.isEmpty
              ? '发俱乐部通知需要「通知成员」权限,可以请主理人给你委派。'
              : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: '网络连接失败',
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _loadAccess,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: '通知工具暂时不可用',
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
          title: '选择受众',
          children: <Widget>[
            ClubOpsCard(
              children: _audiences
                  .map(
                    (_AudienceOption item) => ClubOpsRow(
                      key: Key('notify-audience-${item.value}'),
                      title: item.label,
                      meta: item.hint.isEmpty ? null : item.hint,
                      value: item.countText.isEmpty ? null : item.countText,
                      trailing: Text(
                        _audienceType == item.value ? '已选' : '选择',
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
          title: '内容',
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
                        label: '标题',
                        child: _OpsTextField(
                          key: const Key('notify-title'),
                          controller: _titleCtrl,
                          placeholder: '例如：周六集合提醒',
                          maxLength: 80,
                          onChanged: (_) => _resetDraft(),
                        ),
                      ),
                      CyField(
                        label: '内容',
                        child: _OpsTextField(
                          key: const Key('notify-content'),
                          controller: _contentCtrl,
                          placeholder: '写清集合时间、地点与需要准备的物品',
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
                                label: '重试',
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
                            '0 人 · 当前分群没有可发送成员，不会创建空任务。',
                            style: TextStyle(
                              fontSize: CyTokens.typeLabel,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      if (_previewState == _PreviewState.ready)
                        _previewCard(
                          child: Text(
                            '$_recipientCount 人 · 不会下发手机号；发送后可按失败项重试。',
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
            title: '投递状态',
            children: <Widget>[
              ClubOpsCard(
                children: <Widget>[
                  ClubOpsRow(
                    title: '总人数',
                    value: '${_campaign!.totalCount}',
                    valueColor: palette.textPrimary,
                  ),
                  ClubOpsRow(
                    title: '已送达站内',
                    value: '${_campaign!.successCount}',
                    valueColor: CyTokens.statusSuccess,
                  ),
                  ClubOpsRow(
                    title: '失败',
                    meta: _campaign!.failedCount > 0 ? '重试' : null,
                    value: '${_campaign!.failedCount}',
                    valueColor: CyTokens.statusDanger,
                  ),
                  if (_campaign!.failedCount > 0)
                    Padding(
                      padding: const EdgeInsets.all(CyTokens.space3),
                      child: CyNativeButton(
                        key: const Key('notify-retry'),
                        label: _retrying ? '正在重试…' : '只重试失败项',
                        role: CyNativeButtonRole.secondary,
                        width: double.infinity,
                        onPressed: _retrying ? null : _retryFailed,
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
            '不会下发手机号；发送后可按失败项重试。分群为空时不会创建空任务。',
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
        label: busy ? '正在预览…' : '预览受众',
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
