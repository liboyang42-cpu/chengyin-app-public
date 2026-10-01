import '../../data/api/coupon_api.dart';
import 'merchant_coupon_strings.dart';
import '../../l10n/strings.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../merchant/merchant_error_view.dart';
import 'coupon_publish_sheet.dart';

/// 我发布的券(商家侧):`POST /api/coupon/mypublishlist`。
/// ★ 此前商家发了券之后看不到自己发过什么。
final myPublishedCouponsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.watch(couponApiProvider).myPublishedList();
    });

/// 券模板状态字典。对齐后端 `SmsCoupon.status`
/// (0未开始/1进行中/2已结束/3手动失效/4商家已停发)。
/// ★ 状态 4「已停发」的文案与停发按钮对齐真源 `coupon.js` `COUPON_STATUS_TEXTS`。
String couponPublishStatusText(int? status) {
  switch (status) {
    case 0:
      return '未开始';
    case 1:
      return '进行中';
    case 2:
      return '已结束';
    case 3:
      return '已失效';
    case 4:
      return '已停发';
    default:
      return status == null ? '' : '状态 $status';
  }
}

/// 能不能停发。真源 `coupon.js:34 canStop` = `status in (0,1)`,
/// 与后端 CAS 同一口径 —— 已结束/已失效/已停发的券不再摆入口。
bool couponCanStop(int? status) => status == 0 || status == 1;

class MyPublishedCouponsPage extends ConsumerWidget {
  const MyPublishedCouponsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 游客深链 `/merchant/coupons` 落地给页内登录门,不再静默弹回首页
    //   (b1-sim-coupon P1-1,同 roam #208 范式);路由侧已放行这一条。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantCouponMyCoupons)),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: StatusView(
              key: const Key('coupon-published-login-gate'),
              message: stringsOf(context).merchantCouponLoginTitle,
              sub: stringsOf(context).merchantCouponLoginBody,
              icon: CupertinoIcons.lock,
              large: true,
              retryLabel: stringsOf(context).merchantCouponLogin,
              onRetry: () => requireLogin(context, ref),
            ),
          ),
        ),
      );
    }
    final async = ref.watch(myPublishedCouponsProvider);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantCouponMyCoupons),
        trailing: CyNativeIconButton(
          key: const Key('coupon-publish-entry'),
          label: stringsOf(context).merchantCouponPublish,
          icon: const CyNativeButtonIcon(
            sfSymbol: 'plus',
            fallback: CupertinoIcons.add,
          ),
          iconSize: 24,
          onPressed: () async {
            final bool? ok = await showCouponPublishSheet(context);
            if (ok == true) ref.invalidate(myPublishedCouponsProvider);
          },
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () =>
                const CySkeleton(type: CySkeletonType.card, count: 3),
            error: (Object e, _) => e is CouponLocalFailure
                ? StatusView(message: couponLocalFailureText(context, e),
                    onRetry: () => ref.invalidate(myPublishedCouponsProvider))
                : merchantErrorView(
              context,
              e,
              onRetry: () => ref.invalidate(myPublishedCouponsProvider),
            ),
            data: (List<Map<String, dynamic>> rows) {
              if (rows.isEmpty) {
                return StatusView(
                  message: stringsOf(context).merchantCouponEmpty,
                  sub: '',
                  large: true,
                  scrollable: true,
                  icon: CupertinoIcons.ticket,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async =>
                    ref.invalidate(myPublishedCouponsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CyTokens.space2),
                  itemBuilder: (_, int i) => _PublishedCard(coupon: rows[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PublishedCard extends ConsumerStatefulWidget {
  const _PublishedCard({required this.coupon});
  final Map<String, dynamic> coupon;

  @override
  ConsumerState<_PublishedCard> createState() => _PublishedCardState();
}

class _PublishedCardState extends ConsumerState<_PublishedCard> {
  /// 真源 `coupon.js dayText`:卡上日期只到日('YYYY.MM.DD'),认不出显「—」。
  static String _dayText(String? value) {
    final s = (value ?? '').trim();
    if (s.length < 10) return '—';
    final day = s.replaceFirst('T', ' ').substring(0, 10);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)
        ? day.replaceAll('-', '.')
        : '—';
  }

  static int? _int(String? key, Map<String, dynamic> row) =>
      (row[key] as num?)?.toInt();

  /// 停发在途:一次只放一个,防连点把「不可撤销」的动作点两遍。
  bool _stopping = false;

  Map<String, dynamic> get coupon => widget.coupon;

  /// 停发自己的券。真源 `subpackageMember/coupon/coupon.js:163-195`:
  /// 二次确认(不可撤销)→ POST /api/coupon/stop → 成功**回读列表**;
  /// 连失败也回读 —— 不让人对着一个可能已经变了的状态再点一次。
  Future<void> _stop() async {
    final int? id = (coupon['id'] as num?)?.toInt();
    final String name = (coupon['name'] as String?) ?? stringsOf(context).merchantCouponThisCoupon;
    if (id == null || _stopping) return;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).merchantCouponStopTitle(name),
      content: stringsOf(context).couponStopDistributionPolicy,
      confirmText: stringsOf(context).merchantCouponStop,
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _stopping = true);
    try {
      await ref.read(couponApiProvider).stop(id);
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantCouponStoppedNotice(name));
    } on Object catch (e) {
      if (!mounted) return;
      // 失败原因点名:后端给的 msg 优先(配额/权限各自的话术),否则说停发失败。
      CyNativeNotice.show(context, _stopErrorText(e), isError: true);
    } finally {
      if (mounted) setState(() => _stopping = false);
      ref.invalidate(myPublishedCouponsProvider);
    }
  }

  String _stopErrorText(Object error) {
    if (error is CouponLocalFailure) return couponLocalFailureText(context, error);
    final String raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty || raw.contains('DioException')) {
      return stringsOf(context).merchantCouponStopUnconfirmed;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String name = (coupon['name'] as String?) ?? '';
    final int? status = _int('status', coupon);
    final int? publishCount = _int('publishCount', coupon);
    final int? receiveCount = _int('receiveCount', coupon);
    final int? useCount = _int('useCount', coupon);
    final String? startTime = coupon['startTime'] as String?;
    final String? endTime = coupon['endTime'] as String?;
    final String description = ((coupon['description'] as String?) ?? '')
        .trim();
    // 真源兜底:缺说明显「未填写说明」,不能空着一行让人猜是不是渲染坏了。
    final descText = description.isEmpty ? stringsOf(context).merchantCouponNoDescription : description;
    // 真源 normalizeCoupon:库存 = 发行 - 已领(钳到 0);任一缺席显「—」不冒充 0。
    final String remainText = publishCount == null || receiveCount == null
        ? '—'
        : '${(publishCount - receiveCount).clamp(0, 1 << 31)}';
    final String typeText = merchantCouponLocalText(context, couponTypeLabel(_int('couponType', coupon)));
    // 真源徽标规则:「进行中」是常态不摆 badge;已失效(3)/已停发(4)danger 色。
    final statusLabel = couponPublishStatusText(status);
    final showBadge = statusLabel.isNotEmpty && statusLabel != '进行中';
    final dangerBadge = statusLabel == '已失效' || statusLabel == '已停发';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 真源 `.david_tkb_li_con_top` 是 **column**(align-items: flex-start,
          // gap space-1):券名 → 日期 → 状态胶囊各占一行。原来把胶囊塞进券名
          // 那行右侧,长券名折到第二行时胶囊就骑在字上、还挤掉一行字宽。
          Text(
            name.isEmpty ? stringsOf(context).merchantCouponCoupons : name,
            // 真源 `.david_tkb_li_con_top_tit` 是加粗标题 + 两行截断;
            // titleSmall(14/500) 比正文还轻,一行 ellipsis 又把长券名吞了。
            // iOS 梯上对应档 = Headline 17 Semibold(列表行标题)。
            style: CyType.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: CyTokens.space1),
          Text(
            '${_dayText(startTime)} – ${_dayText(endTime)}',
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          if (showBadge) ...<Widget>[
            SizedBox(height: CyTokens.space1),
            _StatusTag(label: status != null && (status < 0 || status > 4)
                ? stringsOf(context).merchantCouponUnknownStatus(status)
                : merchantCouponLocalText(context, statusLabel), danger: dangerBadge),
          ],
          const SizedBox(height: CyTokens.space1_5),
          Text(
            descText,
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CyTokens.space1_5),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  typeText,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(stringsOf(context).merchantCouponInventory(remainText), style: textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          Row(
            children: <Widget>[
              _stat(context, stringsOf(context).merchantCouponIssued, publishCount),
              _stat(context, stringsOf(context).merchantCouponClaimed, receiveCount),
              _stat(context, stringsOf(context).merchantCouponRedeemed, useCount),
            ],
          ),
          // 真源 `coupon.wxml` 的 `tkbox_stop`:只有进行中/未开始的券能停发,
          // 且必须写清停发的**边界**(停的是新增发放,不是已领的券)。
          if (couponCanStop(status)) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Divider(
              height: 1,
              color: CyPalette.of(context).borderSubtle,
            ),
            const SizedBox(height: CyTokens.space2),
            CyNativeButton(
              key: Key('coupon-stop-$name'),
              label: stringsOf(context).merchantCouponStop,
              role: CyNativeButtonRole.destructive,
              height: 44,
              loading: _stopping,
              onPressed: _stopping ? null : _stop,
            ),
            const SizedBox(height: CyTokens.space1_5),
            Text(
              '停发后不能再被领取、发放；已领到的券照常可用、可核销。',
              style: CyType.caption1.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, int? value) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ★ 数字缺席(null)与真实的 0 不同——缺席显破折号,不冒充 0。
          Text(value == null ? '—' : '$value', style: textTheme.titleMedium),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 券模板状态徽标(真源 `david_tkb_li_con_top_status`,商家浅端):
/// 中性 = secondary 字 @ bg-card-2(即 surface-subtle);失效/停发 = danger 字
/// @ danger-soft(浅端真源是 10% 透明,不是玩家端的 14%)。
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.danger});
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Color fg = danger ? palette.statusDanger : palette.textSecondary;
    // ConstrainedBox + DecoratedBox 而不是 Container(alignment:):
    // 胶囊现在单独占一行,带 alignment 的 Container 会吃满 Column 给的
    // 最大宽度,把一颗状态丸拉成一条通栏色带。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20), // 真源 min-height 40rpx
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: danger
              ? palette.statusDanger.withValues(alpha: 0.10)
              : palette.bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 5, // 真源 10rpx,量表无此档
            vertical: 2,
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: CyTokens.typeCaption, color: fg),
          ),
        ),
      ),
    );
  }
}
