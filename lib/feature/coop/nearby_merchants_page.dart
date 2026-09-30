import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/nearby_merchant.dart';
import '../map/map_controller.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'package:go_router/go_router.dart';
import 'coop_guard.dart';

/// 附近商家。定位复用 map_controller 里已有的 provider
/// (它顺带做了 WGS84→GCJ02 转换,自己再写一份必然漂)。
final nearbyMerchantsProvider =
    FutureProvider.autoDispose<List<NearbyMerchant>>((ref) async {
      final loc = await ref.watch(currentMapLocationProvider.future);
      return ref
          .watch(merchantApiProvider)
          .nearby(longitude: loc.longitude, latitude: loc.latitude);
    });

/// 附近商家 / 找商家承接。对齐小程序 `pages/coop/nearby`。
///
/// ★ 从项目/发件箱带着主题进来时(URL `topicId`,可带 `topicName`),标题换成
///   「找商家承接」、主题名挂在标题下当副句 —— 同真源 onLoad。
///   参数**存在但解析不出正整数**是真源的 `missing-param` 终态
///   (「主题参数无效,无法查询可承接商家」+ 返回上一页),不兜 0 也不静默丢:
///   丢了参数页面会假装是一次普通的「附近商家」搜索。
///   (真源此页还把 invitable 章节并进名单按距离排 —— 那块按 B 线判定另议,
///   未在本页实现,已记偏差。)
class NearbyMerchantsPage extends ConsumerWidget {
  const NearbyMerchantsPage({super.key, this.topicIdRaw, this.topicName});

  final String? topicIdRaw;
  final String? topicName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String raw = (topicIdRaw ?? '').trim();
    final int? parsed = raw.isEmpty ? null : int.tryParse(raw);
    final bool hasTopic = parsed != null && parsed > 0;
    final bool missingParam = raw.isNotEmpty && !hasTopic;
    final String title = hasTopic || missingParam ? '找商家承接' : '附近商家';
    const String needLogin = '登录后查看附近商家';
    if (missingParam) {
      return CupertinoPageScaffold(
        backgroundColor: CyPalette.of(context).bgPage,
        navigationBar: const CupertinoNavigationBar(middle: Text('找商家承接')),
        child: SafeArea(
          bottom: false,
          // 真源 missing-param 终态的 cta 就是「返回上一页」——
          // 参数是坏的,重试也没用,给路。
          child: StatusView(
            message: '主题参数无效',
            sub: '主题参数无效，无法查询可承接商家',
            large: true,
            retryLabel: '返回上一页',
            onRetry: () => context.pop(),
          ),
        ),
      );
    }
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final async = ref.watch(nearbyMerchantsProvider);
    final String name = (topicName ?? '').trim();
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: name.isEmpty
            ? Text(title)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) {
              // ★ 定位失败要说清是定位问题,而不是「附近没有商家」——
              //   后者是在陈述一个我们根本没查过的事实。
              if (e is MapLocationException) {
                return StatusView(
                  message: '需要定位才能找附近商家',
                  sub: e.message,
                  large: true,
                  onRetry: () => ref.invalidate(currentMapLocationProvider),
                );
              }
              if (isCoopUnauthorized(e)) {
                return coopLoginStatus(
                  context,
                  ref,
                  message: needLogin,
                  refetch: () => ref.invalidate(nearbyMerchantsProvider),
                );
              }
              return StatusView(
                message: '附近商家没能加载出来',
                sub: coopErrorSub(e),
                large: true,
                onRetry: () => ref.invalidate(nearbyMerchantsProvider),
              );
            },
            data: (List<NearbyMerchant> rows) {
              if (rows.isEmpty) {
                // ★ 文案里说了「再试」就必须给按钮 —— 门禁
                //   test/status_view_retry_gate_test.dart 盯着这条,刚抓到我一次。
                return StatusView(
                  message: '附近暂时没有商家',
                  sub: '换个位置再看看',
                  large: true,
                  onRetry: () => ref.invalidate(nearbyMerchantsProvider),
                  retryLabel: '重新搜索',
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async => ref.invalidate(nearbyMerchantsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  itemCount: rows.length,
                  itemBuilder: (_, int i) => _NearbyTile(
                    merchant: rows[i],
                    onTap: () => _openMerchant(context, rows[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 点整行进商家主页 —— 邀约在那儿发起(真源 openMerchant:先看承接档案
  /// 再定条款,不在名单里拍脑袋)。未入驻的 lead 没有 memberId,
  /// 也就没有主页主体,只能留电话这条路。
  ///
  /// 真源把 topicId/topicName 作合作上下文追加进主页链接;App 侧商家主页
  /// 还没有「发起合作」消费端,挂死参数只会固化一个没人读的查询串 ——
  /// 上下文衔接已记偏差。
  void _openMerchant(BuildContext context, NearbyMerchant m) {
    final int? memberId = m.memberId;
    if (memberId == null) {
      CyNativeNotice.show(context, '这家还没在平台建档，先电话联系');
      return;
    }
    context.push('/merchant/public-home/member/$memberId');
  }
}

class _NearbyTile extends StatelessWidget {
  const _NearbyTile({required this.merchant, required this.onTap});
  final NearbyMerchant merchant;

  /// 点整行 = 进商家主页(openMerchant 的行级化身)。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final m = merchant;
    final dist = m.distanceText;
    final phone = m.dialablePhone;

    return CupertinoButton(
      // 对齐仓内卡片行的既有写法(_FinanceTile):padding 归零,
      // 命中区是整张卡,press 态交给按钮自己管。
      padding: EdgeInsets.zero,
      key: Key('nearby-merchant-${m.id}'),
      onPressed: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: CyTokens.space2),
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: CyPalette.of(context).borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(m.name, style: textTheme.titleSmall)),
                // 后端没给距离就整行不显示,不写「0m」让人以为就在脚下。
                if (dist != null)
                  Text(
                    dist,
                    style: textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
              ],
            ),
            if ((m.address ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  m.address!,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (m.tagList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Wrap(
                  spacing: CyTokens.space1,
                  runSpacing: CyTokens.space1,
                  children: m.tagList
                      .map((String t) => CyTag(label: t))
                      .toList(),
                ),
              ),
            // 联系方式。
            //
            // ★ 只做「复制号码」不做「一键拨号」:项目里没有 url_launcher,
            //   自己 spawn intent 不可靠。**宁可给一个真能用的小动作,
            //   也不摆一个点了没反应的拨号按钮。**
            // ★ 邀约不在这张卡上:真源动线是「点行进商家主页 → 看承接档案 →
            //   发起合作」,行内不直接发邀请。
            if (phone != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              SizedBox(
                width: double.infinity,
                child: CyNativeButton(
                  label: '复制电话 $phone',
                  role: CyNativeButtonRole.secondary,
                  icon: const CyNativeButtonIcon(
                    sfSymbol: 'doc.on.doc',
                    fallback: CupertinoIcons.doc_on_doc,
                  ),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: phone));
                    if (!context.mounted) return;
                    CyNativeNotice.show(context, '已复制 $phone');
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
