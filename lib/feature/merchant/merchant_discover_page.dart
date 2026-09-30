// 发现商家 —— 对应小程序 pages/merchant/discover。
//
// ★★ 这是**玩家侧按调性找店**,与「关系页的可合作商家」(B2B,/api/club/merchants)
//   不是一回事 —— 小程序那页开头的注释专门写了这一句。
//
// ★ App 此前只有**按店名搜**(搜索页的 merchantApi.searchByName)。
//   想找「适合组队的店」是找不到的 —— 而这正是这个产品的用法:
//   用户通常不知道店名,知道的是自己想要什么调性。
//   后端 MmsMerchantMapper.xml:60 一直支持 `tags like`。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant.dart';

/// 热门标签。★ 与小程序 `HOT_TAGS` 逐字一致 ——
/// 标签是**匹配用的字符串**(后端 `tags like '%x%'`),
/// 改一个字就搜不到同一批店了。
const List<String> kHotMerchantTags = <String>[
  '夜间友好',
  '可拍照',
  '适合组队',
  '宠物友好',
  '安静',
  '适合亲子',
];

final discoverMerchantsProvider = FutureProvider.autoDispose
    .family<List<Merchant>, String>(
      (Ref ref, String tag) => tag.isEmpty
          ? ref.watch(merchantApiProvider).searchByName('')
          : ref.watch(merchantApiProvider).discoverByTag(tag),
    );

/// 一张卡上显示的标签:城市角色排第一,然后是自定义标签,最多 3 个。
/// 与小程序 `(m.cityRole ? [m.cityRole] : []).concat(tags).slice(0, 3)` 同一条。
List<String> merchantChips(Merchant m) {
  final List<String> out = <String>[
    if ((m.cityRole ?? '').trim().isNotEmpty) m.cityRole!.trim(),
  ];
  // 后端 tags 是**逗号/分号分隔的字符串**,不是数组。
  // ⚠️ 分隔符要写 **unicode 转义**:全角逗号/分号直接写进源码,
  //   经过某些编辑链路会被规范化成半角,正则里就只剩两个 ASCII 符号 ——
  //   表现是「用全角逗号分隔的标签切不开」。(2026-08-20 实测踩到。)
  for (final String t in (m.tags ?? '').split(
    RegExp('[,;\u{FF0C}\u{FF1B}\u{3001}]'),
  )) {
    final String s = t.trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out.take(3).toList();
}

class MerchantDiscoverPage extends ConsumerStatefulWidget {
  const MerchantDiscoverPage({super.key});
  @override
  ConsumerState<MerchantDiscoverPage> createState() => _State();
}

class _State extends ConsumerState<MerchantDiscoverPage> {
  String _tag = '';

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final AsyncValue<List<Merchant>> async = ref.watch(
      discoverMerchantsProvider(_tag),
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('发现商家')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(CyTokens.space4),
                child: Row(
                  children: <Widget>[
                    for (final String t in <String>['', ...kHotMerchantTags])
                      Padding(
                        padding: const EdgeInsets.only(right: CyTokens.space2),
                        child: _Chip(
                          label: t.isEmpty ? '全部' : t,
                          on: _tag == t,
                          onTap: () => setState(() => _tag = t),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CupertinoActivityIndicator()),
                  error: (Object e, StackTrace _) => StatusView(
                    message: '商家列表暂时没能加载',
                    sub: e.toString().replaceFirst('Exception: ', ''),
                    large: true,
                    onRetry: () =>
                        ref.invalidate(discoverMerchantsProvider(_tag)),
                  ),
                  data: (List<Merchant> rows) => rows.isEmpty
                      ? StatusView(
                          message: '没有找到匹配的商家',
                          // ★ 说清判据 —— 否则用户以为这个标签下真的一家都没有。
                          sub: _tag.isEmpty
                              ? '只有审核通过并开放合作的商家会出现在这里'
                              : '换个标签,或看「全部」',
                          large: true,
                          // ⚠️ 文案里不说「再试试」就不必给重试钮 ——
                          //   空态不是故障,给「重试」会让人以为是加载失败。
                          //   (门禁 status_view_retry_gate 拦「说了重试却没按钮」。)
                        )
                      : RefreshIndicator.adaptive(
                          onRefresh: () async =>
                              ref.invalidate(discoverMerchantsProvider(_tag)),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CyTokens.space4,
                            ),
                            itemCount: rows.length,
                            itemBuilder: (BuildContext c, int i) =>
                                _Card(rows[i], palette: p),
                          ),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // ⚠️ 这一页是**浅色**(商家域)—— 颜色必须走 CyPalette 取当前主题的值,
    //   写死 CyTokens.* 拿到的是深色系,在白底上就是一块黑
    //   (门禁 light_pages_no_static_colors 当场抓到我这一处)。
    final CyPalette p = CyPalette.of(context);
    return Semantics(
      key: Key('discover-tag-$label'),
      button: true,
      selected: on,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: CupertinoButton(
        onPressed: onTap,
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        child: Container(
          height: 44, // 最小触达尺寸
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? p.textPrimary : p.bgElevated,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              color: on ? p.bgSurface : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.m, {required this.palette});
  final Merchant m;
  final CyPalette palette;

  @override
  Widget build(BuildContext context) {
    final List<String> chips = merchantChips(m);
    final int? memberId = m.memberId;
    final bool canOpenHome = memberId != null && memberId > 0;
    final String name = (m.name ?? '').trim().isEmpty
        ? '未命名商家'
        : m.name!.trim();
    final String summary = (m.slogan ?? '').trim().isNotEmpty
        ? m.slogan!.trim()
        : (m.description ?? '').trim();
    final String semanticLabel = <String>[
      name,
      if (summary.isNotEmpty) summary,
      ...chips,
    ].join('，');
    void activate() {
      if (!canOpenHome) {
        CyNativeNotice.show(context, '该商家暂不可查看');
        return;
      }
      context.push('/merchant/public-home/member/$memberId');
    }

    return Semantics(
      key: Key('discover-merchant-${m.id}'),
      button: true,
      enabled: true,
      label: semanticLabel,
      hint: canOpenHome ? null : '该商家暂不可查看',
      onTap: activate,
      excludeSemantics: true,
      child: CupertinoButton(
        onPressed: activate,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        child: Container(
          margin: const EdgeInsets.only(bottom: CyTokens.space3),
          padding: const EdgeInsets.all(CyTokens.space3),
          decoration: BoxDecoration(
            color: palette.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                child: CyNetImage(
                  m.logo ?? m.coverImage,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    // slogan 拿不到时退到 description(小程序同样的兜底顺序)。
                    if (((m.slogan ?? '').trim().isNotEmpty ||
                        (m.description ?? '').trim().isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          (m.slogan ?? '').trim().isNotEmpty
                              ? m.slogan!.trim()
                              : m.description!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: CyTokens.typeCaption,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    if (chips.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          chips.join(' · '),
                          style: TextStyle(
                            fontSize: CyTokens.typeCaption,
                            color: palette.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
