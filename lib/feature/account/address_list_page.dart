import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/address_api.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'account_login_gate.dart';

final addressApiProvider = Provider<AddressApi>((ref) {
  return AddressApi(ref.watch(dioClientProvider));
});

final addressListProvider = FutureProvider.autoDispose<List<MemberAddress>>((
  ref,
) {
  return ref.watch(addressApiProvider).list();
});

/// 参与人信息。1:1 对齐小程序 `pages/address`(标题/行内文案/空态/错误态/底栏新增)。
///
/// ★ 真源这页**不是收货地址簿**:标题「参与人信息」,行内说明「用于报名联系和
///   到场核验」;`pages/addressinfo/addressinfo.wxml` 里「设为默认地址」开关
///   与列表里的「默认」角标都已被注释停用 —— setDefault 端点保留在后端与
///   `AddressApi`,但 UI 不调用(B1 账号域报告 P1-3)。
///   App 侧「收货地址」标题 /「新增收货地址」FAB /「寄送实物奖励」副文案系虚构,已收口。
///
/// ★★ 与「参与人」是同一张表(`ums_member_address`,同一组 `/api/user/address/*`)——
///   所以这里删一条,报名时的参与人也没了(确认文案必须说清)。
class AddressListPage extends ConsumerWidget {
  const AddressListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 游客短路:不发注定 401 的请求,页内给登录门(B1 报告 P1-1/P1-4)。
    final bool guest = accountGuest(ref);

    Future<void> openAdd() async {
      final Object? ok = await GoRouter.of(context).push('/address/edit');
      if (ok == true) ref.invalidate(addressListProvider);
    }

    final Widget body = guest
        ? AccountLoginGate(
            key: const Key('address-login-gate'),
            message: stringsOf(context).accountParticipantsLogin,
            sub: stringsOf(context).accountParticipantsLoginHint,
            onSignedIn: () => ref.invalidate(addressListProvider),
          )
        : _AddressListBody(onAdd: openAdd);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: body),
      ),
    );
  }
}

class _AddressListBody extends ConsumerWidget {
  const _AddressListBody({required this.onAdd});
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(addressListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CyPageTitle(stringsOf(context).accountParticipants),
        Expanded(
          child: async.when(
            // 真源 `cy-skeleton type="list" count="4"`(address.wxml:13)。
            loading: () =>
                const CySkeleton(type: CySkeletonType.card, count: 4),
            error: (Object e, StackTrace st) => accountLoginRequired(e)
                ? AccountLoginGate(
                    message: stringsOf(context).accountParticipantsLogin,
                    sub: stringsOf(context).accountParticipantsLoginHint,
                    onSignedIn: () => ref.invalidate(addressListProvider),
                  )
                : StatusView(
                    // 真源 cy-error:title=后端原话,sub 固定一句「数据不会丢失」。
                    message: accountFailureCopy(
                      e,
                      strings: stringsOf(context),
                      networkFallback: stringsOf(context).accountParticipantsLoadError,
                    ),
                    sub: stringsOf(context).accountDataSafeRetry,
                    large: true,
                    onRetry: () => ref.invalidate(addressListProvider),
                  ),
            data: (List<MemberAddress> rows) {
              if (rows.isEmpty) {
                // 真源 cy-empty 逐字(address.wxml:34-35)。
                return StatusView(
                  icon: CupertinoIcons.person_2,
                  message: stringsOf(context).accountParticipantsEmpty,
                  sub: stringsOf(context).accountParticipantsEmptyHint,
                  large: true,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async => ref.invalidate(addressListProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CyTokens.space3),
                  itemBuilder: (_, int i) => _Card(row: rows[i]),
                ),
              );
            },
          ),
        ),
        // 真源 cy-footer-bar 只在 loadState==='ready' 时挂出底栏,
        // 新增按钮是整宽主按钮,不是悬浮 FAB(address.wxml:41-45)。
        if (async.hasValue)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space2,
              CyTokens.pageX,
              CyTokens.space3,
            ),
            child: CyNativeButton(
              key: const Key('address-add'),
              label: stringsOf(context).accountParticipantAdd,
              icon: const CyNativeButtonIcon(
                sfSymbol: 'person.badge.plus',
                fallback: CupertinoIcons.person_add,
              ),
              width: double.infinity,
              onPressed: onAdd,
            ),
          ),
      ],
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.row});
  final MemberAddress row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final Widget editRow = Semantics(
      container: true,
      label: stringsOf(context).accountEditPerson(row.fullName),
      button: true,
      child: ExcludeSemantics(
        child: CupertinoButton(
          key: Key('address-edit-${row.id}'),
          minimumSize: const Size(44, 48),
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          onPressed: () async {
            final Object? ok = await GoRouter.of(
              context,
            ).push('/address/edit/${row.id}');
            if (ok == true) ref.invalidate(addressListProvider);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space1,
                children: <Widget>[
                  Text(row.fullName, style: t.titleSmall),
                  Text(
                    // 真源列表行直接显示手机号(address.wxml:17);
                    // 它只是显示,提交用的一直是原值。
                    row.mobilePhone,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: CyTokens.space1),
              // 真源行内说明逐字(address.wxml:21)。
              Text(
                stringsOf(context).accountParticipantPurpose,
                key: const Key('address-participant-purpose'),
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Row(
        children: <Widget>[
          Expanded(child: editRow),
          // 真源行上有独立的「编辑」钮(address.wxml:22),与整行点击同途。
          Semantics(
            container: true,
            label: stringsOf(context).accountEditPerson(row.fullName),
            button: true,
            enabled: true,
            onTap: () async {
              final Object? ok = await GoRouter.of(
                context,
              ).push('/address/edit/${row.id}');
              if (ok == true) ref.invalidate(addressListProvider);
            },
            child: ExcludeSemantics(
              child: CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                ),
                onPressed: () async {
                  final Object? ok = await GoRouter.of(
                    context,
                  ).push('/address/edit/${row.id}');
                  if (ok == true) ref.invalidate(addressListProvider);
                },
                child: Text(stringsOf(context).accountEdit),
              ),
            ),
          ),
          Semantics(
            container: true,
            label: stringsOf(context).accountDeletePerson(row.fullName),
            button: true,
            enabled: true,
            onTap: () => _remove(context, ref),
            child: ExcludeSemantics(
              child: CupertinoButton(
                key: Key('address-remove-${row.id}'),
                minimumSize: const Size.square(48),
                padding: EdgeInsets.zero,
                onPressed: () => _remove(context, ref),
                child: Icon(
                  CupertinoIcons.delete,
                  size: 20,
                  color: p.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).accountDeleteTitle,
      // ★★ 同一张表 —— 必须说清"参与人"那边也会消失。
      content: stringsOf(context).accountDeleteParticipantWarning(row.fullName),
      confirmText: stringsOf(context).accountDelete,
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(addressApiProvider).remove(row.id);
      ref.invalidate(addressListProvider);
    } catch (e) {
      if (!context.mounted) return;
      CyNativeNotice.show(
        context,
        accountFailureCopy(e, strings: stringsOf(context), networkFallback: stringsOf(context).accountDeleteError),
        isError: true,
      );
    }
  }
}
