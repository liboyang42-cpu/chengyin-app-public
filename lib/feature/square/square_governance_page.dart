import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feature_flags.dart';
import '../../core/network/login_required.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../auth/login_gate.dart';
import 'square_controller.dart';

/// 当前账号的社区处置与申诉入口；处置事实来自后端，不在客户端推断。
class SquareGovernancePage extends ConsumerStatefulWidget {
  const SquareGovernancePage({super.key});

  @override
  ConsumerState<SquareGovernancePage> createState() =>
      _SquareGovernancePageState();
}

class _SquareGovernancePageState extends ConsumerState<SquareGovernancePage> {
  final List<Map<String, dynamic>> _extraRecords = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _extraNotifications =
      <Map<String, dynamic>>[];
  bool _recordsExhausted = false;
  bool _loadingMoreRecords = false;
  bool _notificationsExhausted = false;
  bool _loadingMoreNotifications = false;
  bool _savingPreferences = false;

  Future<void> _updatePreference({
    bool? interactionEnabled,
    bool? mentionEnabled,
    bool? socialEnabled,
  }) async {
    if (_savingPreferences) return;
    setState(() => _savingPreferences = true);
    try {
      await ref
          .read(squareApiProvider)
          .updateNotificationPreferences(
            interactionEnabled: interactionEnabled,
            mentionEnabled: mentionEnabled,
            socialEnabled: socialEnabled,
          );
      ref.invalidate(squareNotificationPreferencesProvider);
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _loadMoreRecords(List<Map<String, dynamic>> first) async {
    if (_loadingMoreRecords || _recordsExhausted) return;
    final all = <Map<String, dynamic>>[...first, ..._extraRecords];
    if (all.isEmpty) return;
    final cursor = all
        .map((item) => (item['id'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .fold<int?>(null, (min, id) => min == null || id < min ? id : min);
    if (cursor == null) return;
    setState(() => _loadingMoreRecords = true);
    try {
      final next = await ref
          .read(squareApiProvider)
          .myEnforcements(cursor: cursor);
      if (!mounted) return;
      final known = all.map((item) => (item['id'] as num?)?.toInt()).toSet();
      setState(() {
        _extraRecords.addAll(
          next.where((item) => known.add((item['id'] as num?)?.toInt())),
        );
        _recordsExhausted = next.length < 30;
      });
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMoreRecords = false);
    }
  }

  Future<void> _loadMoreNotifications(List<Map<String, dynamic>> first) async {
    if (_loadingMoreNotifications || _notificationsExhausted) return;
    final all = <Map<String, dynamic>>[...first, ..._extraNotifications];
    if (all.isEmpty) return;
    final cursor = all
        .map((item) => (item['id'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .fold<int?>(null, (min, id) => min == null || id < min ? id : min);
    if (cursor == null) return;
    setState(() => _loadingMoreNotifications = true);
    try {
      final next = await ref
          .read(squareApiProvider)
          .notifications(cursor: cursor);
      if (!mounted) return;
      final known = all.map((item) => (item['id'] as num?)?.toInt()).toSet();
      setState(() {
        _extraNotifications.addAll(
          next.where((item) => known.add((item['id'] as num?)?.toInt())),
        );
        _notificationsExhausted = next.length < 50;
      });
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMoreNotifications = false);
    }
  }

  Future<void> _appeal(
    BuildContext context,
    WidgetRef ref,
    int enforcementId,
  ) async {
    final controller = TextEditingController();
    final reason = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('提交申诉'),
        content: Padding(
          padding: const EdgeInsets.only(top: CyTokens.space2),
          child: CupertinoTextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            placeholder: '说明你认为需要复核的事实',
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    controller.dispose();
    if ((reason ?? '').trim().isEmpty || !context.mounted) return;
    try {
      await ref
          .read(squareApiProvider)
          .appealEnforcement(enforcementId, reason!.trim());
      ref.invalidate(squareEnforcementsProvider);
      if (context.mounted) CyNativeNotice.show(context, '申诉已提交，平台会独立复核');
    } catch (error) {
      if (context.mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _markRead(BuildContext context, WidgetRef ref, int id) async {
    try {
      await ref.read(squareApiProvider).readNotification(id);
      ref.invalidate(squareNotificationsProvider);
      if (mounted) {
        setState(() {
          for (final item in _extraNotifications) {
            if ((item['id'] as num?)?.toInt() == id) item['read_at'] = 'now';
          }
        });
      }
    } catch (error) {
      if (context.mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(squareEnforcementsProvider);
    final notifications = ref.watch(squareNotificationsProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('社区治理')),
      child: SafeArea(
        child: records.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          // 处置记录按账号取,无 token 一律 401(同草稿页,2026-09-18 截图实证)。
          error: (error, stack) => isLoginRequiredError(error)
              ? StatusView(
                  key: const Key('square-governance-login-required'),
                  message: '登录后查看社区处置记录',
                  sub: '处置和申诉都记在账号下,登录完会自动回到这一页。',
                  icon: CupertinoIcons.lock,
                  retryLabel: '去登录',
                  onRetry: () async {
                    if (!await requireLogin(context, ref)) return;
                    ref.invalidate(squareEnforcementsProvider);
                  },
                )
              : StatusView(
                  message: '未能加载处置记录',
                  icon: CupertinoIcons.exclamationmark_shield,
                  onRetry: () => ref.invalidate(squareEnforcementsProvider),
                ),
          data: (rows) => notifications.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (error, stack) => isLoginRequiredError(error)
                ? StatusView(
                    key: const Key('square-governance-login-required'),
                    message: '登录后查看社区通知',
                    sub: '通知按账号下发,登录完会自动回到这一页。',
                    icon: CupertinoIcons.lock,
                    retryLabel: '去登录',
                    onRetry: () async {
                      if (!await requireLogin(context, ref)) return;
                      ref.invalidate(squareNotificationsProvider);
                    },
                  )
                : StatusView(
                    message: '未能加载社区通知',
                    icon: CupertinoIcons.bell_slash,
                    onRetry: () => ref.invalidate(squareNotificationsProvider),
                  ),
            data: (items) => _content(
              context,
              ref,
              <Map<String, dynamic>>[...rows, ..._extraRecords],
              <Map<String, dynamic>>[...items, ..._extraNotifications],
              firstRecords: rows,
              firstNotifications: items,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> records,
    List<Map<String, dynamic>> notifications, {
    required List<Map<String, dynamic>> firstRecords,
    required List<Map<String, dynamic>> firstNotifications,
  }) {
    final bool communityOpen = ref.watch(
      featureFlagProvider('communityPostRead'),
    );
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        CupertinoButton.tinted(
          onPressed: () => context.push('/square/drafts'),
          child: const Text('查看我的草稿与待复审内容'),
        ),
        const SizedBox(height: CyTokens.space3),
        Text('通知偏好', style: Theme.of(context).textTheme.titleLarge),
        ref
            .watch(squareNotificationPreferencesProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(CyTokens.space2),
                child: CupertinoActivityIndicator(),
              ),
              error: (error, stack) => CupertinoButton(
                onPressed: () =>
                    ref.invalidate(squareNotificationPreferencesProvider),
                child: const Text('重试加载通知偏好'),
              ),
              data: (preferences) => CupertinoListSection.insetGrouped(
                margin: const EdgeInsets.symmetric(vertical: CyTokens.space2),
                children: <Widget>[
                  _preferenceTile(
                    '互动与回复',
                    preferences['interactionEnabled'] == true,
                    (value) => _updatePreference(interactionEnabled: value),
                  ),
                  _preferenceTile(
                    '提及我',
                    preferences['mentionEnabled'] == true,
                    (value) => _updatePreference(mentionEnabled: value),
                  ),
                  _preferenceTile(
                    '社交动态',
                    preferences['socialEnabled'] == true,
                    (value) => _updatePreference(socialEnabled: value),
                  ),
                  const CupertinoListTile(
                    title: Text('平台治理'),
                    subtitle: Text('安全、处置与申诉结果始终送达'),
                    trailing: Icon(CupertinoIcons.lock_shield_fill),
                  ),
                ],
              ),
            ),
        const SizedBox(height: CyTokens.space3),
        Text('社区通知', style: Theme.of(context).textTheme.titleLarge),
        if (notifications.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: CyTokens.space3),
            child: Text('暂无新通知'),
          ),
        for (final item in notifications) ...<Widget>[
          CupertinoListTile(
            padding: EdgeInsets.zero,
            title: Text(_notificationTitle(item)),
            subtitle: Text(item['read_at'] == null ? '未读' : '已读'),
            trailing: item['read_at'] == null
                ? const Icon(CupertinoIcons.circle_fill, size: 9)
                : null,
            onTap: () async {
              final id = (item['id'] as num?)?.toInt() ?? 0;
              if (item['read_at'] == null && id > 0) {
                await _markRead(context, ref, id);
              }
              final postId = (item['post_id'] as num?)?.toInt();
              if (context.mounted && postId != null && postId > 0) {
                if (!communityOpen) {
                  CyNativeNotice.show(context, '社区广场灰度中，动态详情暂不开放');
                } else {
                  context.push('/square/$postId');
                }
              }
            },
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: CyPalette.of(context).borderSubtle,
          ),
        ],
        if (!_notificationsExhausted && firstNotifications.length >= 50)
          CupertinoButton(
            onPressed: _loadingMoreNotifications
                ? null
                : () => _loadMoreNotifications(firstNotifications),
            child: _loadingMoreNotifications
                ? const CupertinoActivityIndicator()
                : const Text('加载更多通知'),
          ),
        const SizedBox(height: CyTokens.space3),
        Text('处置与申诉', style: Theme.of(context).textTheme.titleLarge),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: CyTokens.space3),
            child: Text('没有社区处置记录'),
          ),
        for (final row in records) _enforcementTile(context, ref, row),
        if (!_recordsExhausted && firstRecords.length >= 30)
          CupertinoButton(
            onPressed: _loadingMoreRecords
                ? null
                : () => _loadMoreRecords(firstRecords),
            child: _loadingMoreRecords
                ? const CupertinoActivityIndicator()
                : const Text('加载更多处置记录'),
          ),
      ],
    );
  }

  Widget _preferenceTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return CupertinoListTile(
      title: Text(title),
      trailing: CupertinoSwitch(
        value: value,
        onChanged: _savingPreferences ? null : onChanged,
      ),
    );
  }

  String _notificationTitle(Map<String, dynamic> item) {
    Map<String, dynamic> payload = const <String, dynamic>{};
    final raw = item['payload_json'];
    if (raw is Map) {
      payload = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      } catch (_) {
        payload = const <String, dynamic>{};
      }
    }
    final action = '${payload['action'] ?? ''}';
    if (action.startsWith('REPORT_STAGE_')) {
      final note = '${payload['publicNote'] ?? ''}'.trim();
      return note.isEmpty ? '你的举报进度已更新' : note;
    }
    return <String, String>{
          'LIKE': '有人喜欢了你的帖文',
          'BOOKMARK': '有人收藏了你的帖文',
          'COMMENT': '有人回复了你的帖文',
          'REPLY': '有人回复了你的评论',
          'COMMENT_LIKE': '有人喜欢了你的评论',
          'POST_MENTION': '有人在帖文中提及你',
          'APPROVED': '你的帖文已通过审核',
          'REMOVED': '你的帖文未通过审核',
          'APPEAL_SUBMITTED': '申诉已提交',
          'APPEAL_UPHELD': '申诉复核已完成',
          'APPEAL_REVERSED': '申诉成功，处置已撤销',
          'FEATURED': '你的帖文已被收录到精选',
          'FOLLOW': '有人关注了你',
          'GUIDELINE_UPDATED': '社区规范已更新，请在下次发布前查看',
          'REPORT_RECEIVED': '你的举报已受理',
        }[action] ??
        '社区动态';
  }

  Widget _enforcementTile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) {
    final id = (row['id'] as num?)?.toInt() ?? 0;
    final type = '${row['enforcement_type'] ?? 'COMMUNITY_ACTION'}';
    final rule = '${row['rule_code'] ?? ''}';
    final status = '${row['status'] ?? ''}';
    final appealStatus = row['appeal_status']?.toString();
    return Semantics(
      label: '社区处置 $type，状态 $status',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(type, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: CyTokens.space1),
            Text(
              rule.isEmpty ? status : '$rule · $status',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (appealStatus == null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: id > 0 ? () => _appeal(context, ref, id) : null,
                child: const Text('申请复核'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  '申诉状态：$appealStatus',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            Divider(
              height: 1,
              thickness: 1,
              color: CyPalette.of(context).borderSubtle,
            ),
          ],
        ),
      ),
    );
  }
}
