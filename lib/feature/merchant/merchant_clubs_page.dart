import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_search_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/status_view.dart';
import 'merchant_error_view.dart';

/// 商家看俱乐部列表(发邀请用):`POST /api/merchant/clubs`。
/// 后端强制 status=1(仅已开放),前端不传这个参数。
///
/// ★ 这里只做**目录浏览**,不接发邀请的写动作 ——
///   邀请走的是 `/api/coop/invite` 那条完整流程(选主题、写留言、握手确认),
///   属于合作招商域,不在这一批范围内。
final merchantClubsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, String keyword) {
      return ref.watch(merchantApiProvider).clubsForInvite(name: keyword);
    });

class MerchantClubsPage extends ConsumerStatefulWidget {
  const MerchantClubsPage({super.key});

  @override
  ConsumerState<MerchantClubsPage> createState() => _MerchantClubsPageState();
}

class _MerchantClubsPageState extends ConsumerState<MerchantClubsPage> {
  String _query = '';
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(merchantClubsProvider(_keyword));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('可邀请的俱乐部')),
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
                child: CySearchField(
                  value: _query,
                  placeholder: '搜索俱乐部名称',
                  onChanged: (String v) => setState(() => _query = v),
                  onSubmitted: (String v) =>
                      setState(() => _keyword = v.trim()),
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CupertinoActivityIndicator()),
                  error: (Object e, _) => merchantErrorView(
                    context,
                    e,
                    what: '俱乐部列表',
                    onRetry: () =>
                        ref.invalidate(merchantClubsProvider(_keyword)),
                  ),
                  data: (List<Map<String, dynamic>> rows) {
                    if (rows.isEmpty) {
                      return StatusView(
                        message: _keyword.isEmpty ? '暂时没有已开放的俱乐部' : '没有匹配的俱乐部',
                        sub: _keyword.isEmpty ? '' : '换个关键词试试',
                        large: true,
                        scrollable: true,
                      );
                    }
                    return RefreshIndicator.adaptive(
                      onRefresh: () async =>
                          ref.invalidate(merchantClubsProvider(_keyword)),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.pageX,
                        ),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: CyTokens.space2),
                        itemBuilder: (_, int i) => _ClubTile(club: rows[i]),
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

class _ClubTile extends StatelessWidget {
  const _ClubTile({required this.club});
  final Map<String, dynamic> club;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String name = (club['name'] as String?) ?? '';
    final String? logo =
        (club['logo'] as String?) ?? (club['cover'] as String?);
    final String? city = club['city'] as String?;
    final int? memberCount = (club['memberCount'] as num?)?.toInt();
    return Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          child: CyNetImage(logo, width: 48, height: 48, fit: BoxFit.cover),
        ),
        const SizedBox(width: CyTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name.isEmpty ? '俱乐部' : name,
                style: textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // 城市与人数都可能缺席;都缺时不留孤零零的「· 」。
              if ((city ?? '').isNotEmpty || memberCount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    <String>[
                      if ((city ?? '').isNotEmpty) city!,
                      if (memberCount != null) '$memberCount 位成员',
                    ].join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
