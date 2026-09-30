import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/cy_confirm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/participant_api.dart';
import '../activity/participant_picker.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'account_login_gate.dart';

/// 参与人信息管理。
///
/// ★ 对齐小程序 `pages/address` + `pages/addressinfo` —— 它们**就是参与人的
///   列表页与编辑页**(报名页带 mode=participant 跳进来),不是收货地址簿:
///   同一组端点 `/api/user/address/*`,同样只填姓名与手机号。
///
/// App 侧此前只有报名时的选择器(participant_picker),**缺一个独立管理入口** ——
/// 于是填错了的参与人没有地方改、也没地方删。这一页补上。
class ParticipantsPage extends ConsumerWidget {
  const ParticipantsPage({
    super.key,
    @visibleForTesting this.liquidGlassSupported,
  });

  /// 仅让 widget 测试走可点击的 Cupertino 降级；生产能力探测仍由组件处理。
  @visibleForTesting
  final bool? liquidGlassSupported;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 游客短路:不发注定 401 的请求,页内给登录门(B1 报告 P1-1)。
    final bool guest = accountGuest(ref);
    final AsyncValue<List<Participant>>? async = guest
        ? null
        : ref.watch(participantsProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const CyPageTitle('参与人信息'),
                    Expanded(
                      child: guest
                          ? AccountLoginGate(
                              key: const Key('participants-login-gate'),
                              message: '登录后查看参与人信息',
                              sub: '参与人存在账号里,登录完就能看到。',
                              onSignedIn: () =>
                                  ref.invalidate(participantsProvider),
                            )
                          : async!.when(
                              // 加载态对齐真源 `cy-skeleton type="list" count="4"`
                              // (pages/address/address.wxml:13),不是转圈。
                              loading: () => const CySkeleton(
                                type: CySkeletonType.list,
                                count: 4,
                              ),
                              error: (Object e, _) => accountLoginRequired(e)
                                  ? AccountLoginGate(
                                      message: '登录后查看参与人信息',
                                      sub: '参与人存在账号里,登录完就能看到。',
                                      onSignedIn: () =>
                                          ref.invalidate(participantsProvider),
                                    )
                                  : StatusView(
                                      message: accountFailureCopy(
                                        e,
                                        networkFallback: '参与人没能加载出来',
                                      ),
                                      sub: '请检查网络后再进来，数据不会丢失',
                                      large: true,
                                      onRetry: () =>
                                          ref.invalidate(participantsProvider),
                                    ),
                              data: (List<Participant> rows) {
                                if (rows.isEmpty) {
                                  return const StatusView(
                                    message: '还没有参与人信息',
                                    sub: '报名活动需要填写联系人；新增后可在报名时直接选用',
                                    large: true,
                                  );
                                }
                                return RefreshIndicator.adaptive(
                                  onRefresh: () async =>
                                      ref.invalidate(participantsProvider),
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: CyTokens.pageX,
                                    ),
                                    itemCount: rows.length,
                                    itemBuilder: (_, int i) =>
                                        _ParticipantTile(participant: rows[i]),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              // 小程序 `pages/address` 的新增入口固定在底部；复用已有编辑路由，
              // 不增加新的页面层级或改变保存后的返回落点。
              if (async != null && async.hasValue)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.pageX,
                      CyTokens.space2,
                      CyTokens.pageX,
                      CyTokens.space3,
                    ),
                    child: CyNativeButton(
                      key: const Key('participant-add'),
                      label: '新增参与人信息',
                      icon: const CyNativeButtonIcon(
                        sfSymbol: 'person.badge.plus',
                        fallback: CupertinoIcons.person_add,
                      ),
                      width: double.infinity,
                      liquidGlassSupported: liquidGlassSupported,
                      onPressed: () async {
                        final Object? saved = await context.push(
                          '/address/edit',
                        );
                        if (saved == true) ref.invalidate(participantsProvider);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantTile extends ConsumerStatefulWidget {
  const _ParticipantTile({required this.participant});
  final Participant participant;

  @override
  ConsumerState<_ParticipantTile> createState() => _ParticipantTileState();
}

class _ParticipantTileState extends ConsumerState<_ParticipantTile> {
  bool _busy = false;

  Future<void> _remove() async {
    final p = widget.participant;
    // ★ 删除不可逆,先确认。文案里带上是谁 —— 只说「确认删除?」
    //   用户在多条之间分不清删的是哪一个。
    final bool ok = await cyConfirm(
      context,
      title: '删除「${p.fullName}」?',
      content: '删除后报名时就选不到这位参与人了,可以重新添加。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(participantApiProvider).remove(p.id);
      ref.invalidate(participantsProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, '已删除');
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        accountFailureCopy(e, networkFallback: '删除没有成功,请稍后重试'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    if (_busy) return;
    final Object? saved = await context.push(
      '/address/edit/${widget.participant.id}',
    );
    if (saved == true) ref.invalidate(participantsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.participant;
    final CyPalette palette = CyPalette.of(context);
    return CyCell(
      title: p.fullName,
      // ★ 列表里用掩码;它只是显示,提交时用的一直是原值
      //   (participant_picker 里有测试锁着这条)。
      subtitle: p.maskedPhone,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 小程序只展示编辑和删除；默认联系人虽然是同一张表的后台字段，
          // 但不在 `mode=participant` 的页面增加额外入口。
          Semantics(
            container: true,
            label: '编辑${p.fullName}',
            button: true,
            enabled: !_busy,
            onTap: _busy ? null : _edit,
            child: ExcludeSemantics(
              child: CupertinoButton(
                key: Key('participant-edit-${p.id}'),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                ),
                onPressed: _busy ? null : _edit,
                child: const Text('编辑'),
              ),
            ),
          ),
          Semantics(
            container: true,
            label: '删除${p.fullName}',
            button: true,
            enabled: !_busy,
            onTap: _busy ? null : _remove,
            child: ExcludeSemantics(
              child: CupertinoButton(
                key: Key('participant-remove-${p.id}'),
                minimumSize: const Size.square(44),
                padding: EdgeInsets.zero,
                onPressed: _busy ? null : _remove,
                child: Icon(CupertinoIcons.delete, color: palette.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
