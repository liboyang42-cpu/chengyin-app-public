import '../../l10n/strings.dart';
import 'merchant_directory_strings.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant_relation.dart';
import 'merchant_error_view.dart';

final merchantRelationProvider =
    FutureProvider.autoDispose<MerchantRelationHome>((ref) {
      return ref.watch(merchantApiProvider).relationHome();
    });

/// 商家关系与发现。合并小程序 `pages/merchant/relation` 与 `discover` 两页 ——
/// 两者数据同源(relation-home 一次返回 relations 与 discovery.merchants),
/// 分成两个页面只是小程序的导航惯例,App 用两档更省一次往返。
class MerchantRelationPage extends ConsumerStatefulWidget {
  const MerchantRelationPage({super.key});

  @override
  ConsumerState<MerchantRelationPage> createState() =>
      _MerchantRelationPageState();
}

class _MerchantRelationPageState extends ConsumerState<MerchantRelationPage> {
  String _active = 'relations';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(merchantRelationProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantDirectoryPartners)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  CyTokens.space2,
                ),
                child: CyTabs(
                  variant: CyTabsVariant.segmented,
                  tabs: <CyTab>[
                    CyTab(key: 'relations', label: stringsOf(context).merchantDirectoryEstablished),
                    CyTab(key: 'discover', label: stringsOf(context).merchantDirectoryDiscover),
                  ],
                  active: _active,
                  onChanged: (String value) => setState(() => _active = value),
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CupertinoActivityIndicator()),
                  error: (Object e, _) => merchantErrorView(
                    context,
                    e,
                    onRetry: () => ref.invalidate(merchantRelationProvider),
                  ),
                  data: (MerchantRelationHome home) => IndexedStack(
                    index: _active == 'relations' ? 0 : 1,
                    children: <Widget>[
                      _RelationList(
                        rows: home.relations,
                        stats: home.stats,
                        emptyTitle: stringsOf(context).merchantDirectoryNoPartners,
                        emptySub: stringsOf(context).merchantDirectoryNoPartnersHint,
                        onRefresh: () =>
                            ref.invalidate(merchantRelationProvider),
                      ),
                      _RelationList(
                        rows: home.discoveryMerchants,
                        emptyTitle: stringsOf(context).merchantDirectoryNoNearby,
                        emptySub: stringsOf(context).merchantDirectoryCheckLater,
                        onRefresh: () =>
                            ref.invalidate(merchantRelationProvider),
                      ),
                    ],
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

class _RelationList extends StatelessWidget {
  const _RelationList({
    required this.rows,
    required this.emptyTitle,
    required this.emptySub,
    required this.onRefresh,
    this.stats,
  });

  final List<MerchantRelation> rows;
  final MerchantRelationStats? stats;
  final String emptyTitle;
  final String emptySub;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator.adaptive(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.pageX),
        children: <Widget>[
          if (stats != null) ...<Widget>[
            Row(
              children: <Widget>[
                Text(
                  stringsOf(context).merchantDirectoryMerchantCount(stats!.merchantCount),
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Text(
                  stringsOf(context).merchantDirectoryClubCount(stats!.clubCount),
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                // ★ 待办为 0 时不显示 —— 「待处理 0」是噪音。
                if (stats!.pendingCoopCount > 0) ...<Widget>[
                  const SizedBox(width: CyTokens.space3),
                  Text(
                    stringsOf(context).merchantDirectoryPendingCount(stats!.pendingCoopCount),
                    style: textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).statusWarning,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: CyTokens.space3),
          ],
          if (rows.isEmpty)
            StatusView(message: emptyTitle, sub: emptySub, large: true)
          else
            // 没名字的行在解析阶段已被丢掉,这里不会出现只有「—」的卡片。
            ...rows.map(
              (MerchantRelation r) =>
                  CyCell(title: r.name, subtitle: merchantDirectoryRelationDescription(context, r)),
            ),
        ],
      ),
    );
  }
}
