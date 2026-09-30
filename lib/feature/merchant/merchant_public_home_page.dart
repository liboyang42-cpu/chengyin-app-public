import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/feature_flags.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../npc/widgets/merchant_npc_chat_sheet.dart';
import 'merchant_error_view.dart';

/// 商家公开主页:`POST /api/merchant/public-home`(匿名可访问)。
/// 对齐小程序 `pages/merchant/profile` + `components/cy/profile`——
/// 别人(玩家/其他商家)看到的这一面,这里主要给商家自己预览。
/// 主体 ID 与小程序 canonical 链接一致：只用 memberId，不用商家档案 id。
final merchantPublicHomeProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, int memberId) {
      return ref
          .watch(merchantApiProvider)
          .merchantPublicHomeByMember(memberId);
    });

/// 兼容旧版 App 已发出的 `/merchant/public-home/:id` 深链：
/// 该 path 的 id 历史语义是商家档案 id，不能静默改成 memberId。
final merchantPublicHomeByIdProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, int merchantId) {
      return ref.watch(merchantApiProvider).merchantPublicHomeById(merchantId);
    });

List<String> _csv(Object? raw) => ((raw as String?) ?? '')
    .split(';')
    .map((String s) => s.trim())
    .where((String s) => s.isNotEmpty)
    .toList();

class MerchantPublicHomePage extends ConsumerWidget {
  const MerchantPublicHomePage({super.key, this.memberId, this.merchantId})
    : assert(
        memberId == null || merchantId == null,
        '两个主体 ID 只给一个;都不给是「缺参深链」态,不是编程错误',
      );
  final int? memberId;
  final int? merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 缺参 / 非法 id 是**一个界面态**(对齐小程序 `state === 'invalid'`),
    //   不是编程错误 —— 旧链接、手改的深链都会落到这里。猜一个主体 ID 出来
    //   会把人送到别人主页,比停在这儿说清楚更糟(小程序 profile/index.js 原话)。
    final int? id = memberId ?? merchantId;
    final AsyncValue<Map<String, dynamic>>? async = id == null || id <= 0
        ? null
        : memberId != null
        ? ref.watch(merchantPublicHomeProvider(memberId!))
        : ref.watch(merchantPublicHomeByIdProvider(merchantId!));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 标题照小程序 `pages/merchant/profile/index`(cy-nav-bar title)。
      navigationBar: const CupertinoNavigationBar(middle: Text('商家主页')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async == null
              ? const StatusView(
                  message: '链接参数无效',
                  sub: '这个链接缺少商家或据点信息，无法确定要打开哪一页。',
                  large: true,
                )
              : async.when(
                  loading: () =>
                      const Center(child: CupertinoActivityIndicator()),
                  error: (Object e, _) => _errorView(context, ref, e),
                  data: (Map<String, dynamic> m) => _Body(data: m),
                ),
        ),
      ),
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    // ★ 「不可公开」是**业务空态,不是可重试的故障** ——
    //   小程序把这两态分开,给一个点了永远不会好的「重试」人就一直在点
    //   (网络失败也不能反过来说成「这家不存在」,那是把「没查到」伪装成事实)。
    if (error is MerchantApiException && error.isPublicHomeUnavailable) {
      return const StatusView(
        message: '商家不存在或未开放',
        sub: '这家店暂时无法查看，去首页看看其他城市内容。',
        large: true,
      );
    }
    return merchantErrorView(
      context,
      error,
      what: '商家资料',
      onRetry: () {
        if (memberId != null) {
          ref.invalidate(merchantPublicHomeProvider(memberId!));
        } else {
          ref.invalidate(merchantPublicHomeByIdProvider(merchantId!));
        }
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final String name = (data['name'] as String?) ?? '';
    final String? logo = data['logo'] as String?;
    final String? cover = data['coverImage'] as String?;
    final String? slogan = data['slogan'] as String?;
    final String? cityRole = data['cityRole'] as String?;
    final String? address = data['address'] as String?;
    final String? businessTime = data['businessTime'] as String?;
    final int? businessStatus = (data['businessStatus'] as num?)?.toInt();
    final String? storyTitle = data['storyTitle'] as String?;
    final String? description = data['description'] as String?;
    final List<String> gallery = _csv(data['gallery']);
    final List<String> tags = _csv(data['tags']);
    final List<dynamic> categories =
        (data['sysCategoryList'] as List<dynamic>?) ?? const <dynamic>[];
    final int? merchantRowId = (data['id'] as num?)?.toInt();
    final int? ownerMemberId = (data['memberId'] as num?)?.toInt();

    final int? capacity = (data['capacity'] as num?)?.toInt();
    final String? availableTime = data['availableTime'] as String?;
    final String? suitActivityTypes = data['suitActivityTypes'] as String?;
    final String? demand = data['demand'] as String?;
    final bool hasCoopInfo =
        (capacity != null && capacity > 0) ||
        (availableTime ?? '').isNotEmpty ||
        (suitActivityTypes ?? '').isNotEmpty ||
        (demand ?? '').isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        if ((cover ?? '').isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            child: CyNetImage(
              cover!,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: CyTokens.space3),
        // 门店 AI 形象。★ 三个条件缺一不显示,且**在这里判**而不是让人点了才失败:
        //   ① 后端下发了 npc(已过审已启用,没配/未审/停用时后端就给 null)
        //   ② shopNpcChat 开关开着(未开时端点恒 403)
        //   ③ 拿得到 merchantId(对话按 merchantId 寻址)
        _npcCard(context, ref),
        Row(
          children: <Widget>[
            CyAvatar(url: logo, size: 56),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name.isEmpty ? '商家' : name, style: textTheme.titleLarge),
                  // ★ businessStatus 缺席(null)时不宣称任何一种状态。
                  if (businessStatus != null)
                    Text(
                      businessStatus == 1 ? '营业中' : '已打烊',
                      style: textTheme.bodySmall?.copyWith(
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if ((slogan ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          Text(slogan!, style: textTheme.bodyLarge),
        ],
        if ((merchantRowId ?? 0) > 0 && (ownerMemberId ?? 0) > 0) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          CyNativeButton(
            label: '查看口碑',
            role: CyNativeButtonRole.secondary,
            width: double.infinity,
            icon: const CyNativeButtonIcon(
              sfSymbol: 'star.bubble',
              fallback: CupertinoIcons.star_fill,
            ),
            onPressed: () => context.push(
              '/merchant/reviews/public/$merchantRowId/$ownerMemberId',
            ),
          ),
        ],
        if ((cityRole ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            cityRole!,
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
        if (categories.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          Wrap(
            spacing: CyTokens.space1,
            runSpacing: CyTokens.space1,
            children: categories
                .whereType<Map<String, dynamic>>()
                .map(
                  (Map<String, dynamic> c) =>
                      CyTag(label: (c['categoryName'] as String?) ?? ''),
                )
                .toList(),
          ),
        ],
        if ((address ?? '').isNotEmpty ||
            (businessTime ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if ((address ?? '').isNotEmpty)
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: CyPalette.of(context).textSecondary,
                      ),
                      const SizedBox(width: CyTokens.space1),
                      Expanded(
                        child: Text(address!, style: textTheme.bodyMedium),
                      ),
                    ],
                  ),
                if ((businessTime ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.schedule_outlined,
                        size: 16,
                        color: CyPalette.of(context).textSecondary,
                      ),
                      const SizedBox(width: CyTokens.space1),
                      Text(businessTime!, style: textTheme.bodyMedium),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        if ((storyTitle ?? '').isNotEmpty ||
            (description ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CySectionTitle(
                  (storyTitle ?? '').isNotEmpty ? storyTitle! : '介绍',
                ),
                if ((description ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space2),
                  Text(description!, style: textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
        if (gallery.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          const CySectionTitle('相册'),
          const SizedBox(height: CyTokens.space2),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: gallery
                .map(
                  (String url) => ClipRRect(
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                    child: CyNetImage(
                      url,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        if (tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          Wrap(
            spacing: CyTokens.space1,
            runSpacing: CyTokens.space1,
            children: tags.map((String t) => CyTag(label: t)).toList(),
          ),
        ],
        if (hasCoopInfo) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const CySectionTitle('承接信息'),
                const SizedBox(height: CyTokens.space2),
                if (capacity != null && capacity > 0)
                  Text('可接待人数:$capacity', style: textTheme.bodyMedium),
                if ((availableTime ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space1),
                    child: Text(
                      '可承接时段:$availableTime',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                if ((suitActivityTypes ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space1),
                    child: Text(
                      '适合类型:$suitActivityTypes',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                if ((demand ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space1),
                    child: Text('合作需求:$demand', style: textTheme.bodyMedium),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

extension _NpcSection on _Body {
  Widget _npcCard(BuildContext context, WidgetRef ref) {
    final Map<String, dynamic>? npc = data['npc'] as Map<String, dynamic>?;
    final int? merchantId = (data['id'] as num?)?.toInt();
    final bool chatOn = ref.watch(featureFlagProvider('shopNpcChat'));
    if (npc == null || merchantId == null) return const SizedBox.shrink();

    final String name = (npc['name'] as String?) ?? '';
    final String? avatar = npc['avatar'] as String?;
    final String? greeting = npc['greeting'] as String?;
    if (name.isEmpty) return const SizedBox.shrink();

    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    // 开关未开时形象仍然出场(它本来就是 PR #820 的静态展示),
    // 只是不给对话入口 —— 而不是整块消失。

    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: _Card(
        child: Row(
          children: <Widget>[
            CyAvatar(url: avatar, size: 44),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: t.titleSmall),
                  if ((greeting ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      greeting!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (chatOn)
              CupertinoButton(
                key: const Key('merchant-npc-chat-entry'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                onPressed: () => showMerchantNpcChatSheet(
                  context,
                  merchantId: merchantId,
                  npcName: name,
                  avatar: avatar,
                  greeting: greeting,
                ),
                child: const Text('聊聊'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: child,
    );
  }
}
