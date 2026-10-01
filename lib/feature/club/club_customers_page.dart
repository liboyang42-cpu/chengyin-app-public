import 'club_api_messages.dart';
import 'club_customer_labels.dart';
import '../../l10n/strings.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_crm.dart';
import 'club_access_gate.dart';
import 'club_controller.dart';

/// K1 客户名单:按**人**聚合(这个人在我这买过几次、什么时候来的)。
///
/// 真源:`pages/club/customers/index`;筛选 / 搜索 / 状态与小程序 1:1,
/// 外观用 iOS 原生(Cupertino 分组列表 + CySearchField + 胶囊筛选)。
class ClubCustomersPage extends ConsumerStatefulWidget {
  const ClubCustomersPage({super.key, required this.clubId});

  final int clubId;

  @override
  ConsumerState<ClubCustomersPage> createState() => _ClubCustomersPageState();
}

class _ClubCustomersPageState extends ConsumerState<ClubCustomersPage> {
  List<CyTab> get _filters => <CyTab>[
    CyTab(key: 'all', label: stringsOf(context).clubCustomersAll),
    CyTab(key: 'repeat', label: stringsOf(context).clubCustomersRepeat),
    CyTab(key: 'new', label: stringsOf(context).clubCustomersNew),
    CyTab(key: 'remark', label: stringsOf(context).clubCustomersWithRemark),
  ];

  String _filter = 'all';

  /// 输入框即时值。
  String _keywordInput = '';

  /// 已提交给接口的值(300ms 防抖后才跟随输入)。
  String _keyword = '';
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onKeywordChanged(String value) {
    setState(() => _keywordInput = value);
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _keyword != _keywordInput) {
        setState(() => _keyword = _keywordInput);
      }
    });
  }

  void _onKeywordSubmitted(String value) {
    _searchTimer?.cancel();
    setState(() {
      _keywordInput = value;
      _keyword = value;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/club/${widget.clubId}');
  }

  @override
  Widget build(BuildContext context) {
    final gate = evaluateClubAccess(
      ref.watch(clubAccessProvider(widget.clubId)),
      clubId: widget.clubId,
      permission: kClubMemberListRead,
    );
    final customers = ref.watch(
      clubCustomersProvider((
        clubId: widget.clubId,
        filter: _filter,
        keyword: _keyword,
      )),
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).clubCustomersTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubCustomersTitle),
              Expanded(
                child: switch (gate.decision) {
                  ClubAccessDecision.deny => StatusView(
                    message: stringsOf(context).clubCustomersNoPermission,
                    sub: localizedClubAccessReason(context, gate),
                    icon: CupertinoIcons.lock,
                    large: true,
                    onRetry: _goBack,
                    retryLabel: stringsOf(context).clubCustomersBack,
                  ),
                  ClubAccessDecision.checking => const CySkeleton(),
                  _ => customers.when(
                    loading: () => CySkeleton(label: stringsOf(context).clubCustomersLoading),
                    error: (Object error, StackTrace _) {
                      final failure = classifyClubCrmFailure(error);
                      if (failure.auth) {
                        return StatusView(
                          message: stringsOf(context).clubCustomersNoPermission,
                          sub: clubApiErrorMessage(context,
                            error,
                            fallback: stringsOf(context).clubCustomersSessionChanged,
                          ),
                          icon: CupertinoIcons.lock,
                          large: true,
                          onRetry: _goBack,
                          retryLabel: stringsOf(context).clubCustomersBack,
                        );
                      }
                      return StatusView(
                        message: stringsOf(context).clubCustomersLoadFailed,
                        sub: failure.network
                            ? stringsOf(context).clubCustomersNetworkRetry
                            : clubApiErrorMessage(context,
                                error,
                                fallback: stringsOf(context).clubCustomersRetryLater,
                              ),
                        icon: CupertinoIcons.cloud,
                        large: true,
                        onRetry: () => ref.invalidate(
                          clubCustomersProvider((
                            clubId: widget.clubId,
                            filter: _filter,
                            keyword: _keyword,
                          )),
                        ),
                      );
                    },
                    data: (ClubCustomerList list) => _body(context, ref, list),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, ClubCustomerList list) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
          child: Text(
            stringsOf(context).clubCustomersCount(list.total, list.monthNew),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
          child: CyTabs(
            tabs: _filters,
            active: _filter,
            variant: CyTabsVariant.chip,
            onChanged: (String key) {
              if (key == _filter) return;
              setState(() => _filter = key);
            },
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
          child: CySearchField(
            value: _keywordInput,
            placeholder: stringsOf(context).clubCustomersSearch,
            onChanged: _onKeywordChanged,
            onSubmitted: _onKeywordSubmitted,
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        Expanded(
          child: list.items.isEmpty
              ? StatusView(
                  message: stringsOf(context).clubCustomersEmpty,
                  sub: stringsOf(context).clubCustomersEmptyBody,
                  icon: CupertinoIcons.person_2,
                  large: true,
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: CyTokens.space6),
                  children: <Widget>[
                    CupertinoListSection.insetGrouped(
                      margin: const EdgeInsets.symmetric(
                        horizontal: CyTokens.pageX,
                        vertical: CyTokens.space2,
                      ),
                      children: <Widget>[
                        for (final ClubCustomerItem item in list.items)
                          _CustomerRow(clubId: widget.clubId, item: item),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.clubId, required this.item});

  final int clubId;
  final ClubCustomerItem item;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoListTile(
      key: Key('club-customer-${item.memberId}'),
      onTap: () => context.push('/club/$clubId/customers/${item.memberId}'),
      leading: CyAvatar(url: item.avatar, fallback: clubCustomerItemName(context, item), size: 44),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(clubCustomerItemName(context, item), overflow: TextOverflow.ellipsis),
          ),
          if (item.hasRemark) ...<Widget>[
            const SizedBox(width: CyTokens.space2),
            CyTag(label: stringsOf(context).clubCustomersRemark),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(clubCustomerItemMeta(context, item)),
          if (item.subText.isNotEmpty)
            Text(
              item.subText,
              style: TextStyle(color: palette.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: palette.textTertiary,
      ),
    );
  }
}
