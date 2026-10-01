import '../../l10n/strings.dart';
import 'coupon_copy.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coupon.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 我领取的优惠券:`POST /api/coupon/myrecvlist`。
/// 非 200 / 网络异常进 error 态,不兜底假数据。
final myCouponsProvider = FutureProvider.autoDispose<List<CouponRecord>>((ref) {
  return ref.watch(couponApiProvider).myReceivedList();
});

/// 券包页(对齐小程序 `scene-game-coupon-wallet`):
/// 顶部四个等宽 tab(全部/待使用/已使用/已过期),useStatus 由服务端落库
/// (myrecvlist 前会先 updateExpiredCouponsByMemberId),前端只按它过滤。
/// 待使用券卡描边高亮、带「出示核销码 ›」入口,点击进券码出示页。
class MyCouponsPage extends ConsumerStatefulWidget {
  const MyCouponsPage({super.key});

  @override
  ConsumerState<MyCouponsPage> createState() => _MyCouponsPageState();
}

class _MyCouponsPageState extends ConsumerState<MyCouponsPage> {
  int _tab = 0;

  List<String> get _tabs => <String>[stringsOf(context).couponWalletAll, stringsOf(context).couponWalletUnused, stringsOf(context).couponWalletUsed, stringsOf(context).couponWalletExpired];

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    // 真源 owner-guard:持有券是账号私产,静默换号后旧列表不许留在屏上,
    // 也不许被上一账号的在途回包写回 —— 换账号即重拉。
    ref.listen(authControllerProvider, (AuthState? prev, AuthState next) {
      if ((prev?.user?.id ?? -1) != (next.user?.id ?? -2)) {
        ref.invalidate(myCouponsProvider);
      }
    });
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).couponWalletTitle),
              // ★ 游客深链落地给登录门而不是静默弹回首页(b1-sim-coupon P1-1,
              //   同 roam #208 范式);游客短路掉注定 401 的请求。
              if (!auth.isLoggedIn)
                Expanded(
                  child: StatusView(
                    key: const Key('coupons-login-gate'),
                    message: stringsOf(context).couponWalletLogin,
                    sub: stringsOf(context).couponWalletLoginDetail,
                    icon: CupertinoIcons.lock,
                    large: true,
                    retryLabel: stringsOf(context).couponWalletSignIn,
                    onRetry: () async {
                      if (!await requireLogin(context, ref)) return;
                      if (!mounted) return;
                      ref.invalidate(myCouponsProvider);
                    },
                  ),
                )
              else ...<Widget>[
                // .wallet-tabs:等宽 tab 行,选中态 = 实心反色。
                // 真源 padding: space-1(4) 上 / space-3(12) 下。
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space1,
                    CyTokens.pageX,
                    CyTokens.space3,
                  ),
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < _tabs.length; i++) ...<Widget>[
                        if (i > 0) SizedBox(width: CyTokens.space1),
                        Expanded(
                          child: _Tab(
                            label: _tabs[i],
                            selected: _tab == i,
                            onTap: () => setState(() => _tab = i),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator.adaptive(
                    onRefresh: () async => ref.invalidate(myCouponsProvider),
                    child: ref
                        .watch(myCouponsProvider)
                        .when(
                          loading: () => const CySkeleton(
                            type: CySkeletonType.list,
                            count: 3,
                          ),
                          error: (Object err, StackTrace st) =>
                              _loadErrorView(context, err),
                          data: (List<CouponRecord> all) {
                            final items = _tab == 0
                                ? all
                                : all
                                      .where(
                                        (CouponRecord c) =>
                                            c.useStatus == _tab - 1,
                                      )
                                      .toList();
                            if (items.isEmpty) {
                              return StatusView(
                                message: _tab == 0 ? stringsOf(context).couponWalletEmpty : stringsOf(context).couponWalletFilterEmpty,
                                sub: _tab == 0
                                    ? stringsOf(context).couponWalletEmptyDetail
                                    : stringsOf(context).couponWalletFilterEmptyDetail,
                                large: true,
                                icon: CupertinoIcons.ticket,
                                scrollable: true,
                              );
                            }
                            return ListView.separated(
                              // 横向内距跟 tab 行同一个 page-x(16):用 space-3(12)
                              // 会把卡片左边缘顶到 tab 左边缘外面,两条线对不上。
                              padding: const EdgeInsets.fromLTRB(
                                CyTokens.pageX,
                                CyTokens.space3,
                                CyTokens.pageX,
                                CyTokens.space3,
                              ),
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: CyTokens.space3),
                              itemBuilder: (context, i) =>
                                  _CouponCard(record: items[i]),
                            );
                          },
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 错误态按真源四句分开:网络 / 会话待确认 / 没能打开(服务异常与未知),
  /// 不把 dio 原文糊到屏上。
  Widget _loadErrorView(BuildContext context, Object err) {
    final text = '$err';
    final String message;
    if (RegExp(
      r'ConnectionException|SocketException|NetworkException|connection (error|timeout)|Failed host lookup|未找到主机|超时',
      caseSensitive: false,
    ).hasMatch(text)) {
      message = stringsOf(context).couponWalletNetwork;
    } else if (RegExp(
      r'登录|未登录|401|token',
      caseSensitive: false,
    ).hasMatch(text)) {
      message = stringsOf(context).couponWalletSession;
    } else {
      message = stringsOf(context).couponWalletTryLater;
    }
    return StatusView(
      message: stringsOf(context).couponWalletLoadError,
      sub: message,
      icon: CupertinoIcons.exclamationmark_triangle,
      scrollable: true,
      onRetry: () => ref.invalidate(myCouponsProvider),
    );
  }
}

/// .wallet-tab 单个 tab:flex 等宽、btn-h-sm 高、药丸角;选中白底黑字。
class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      // 自定义筛选片没有系统分段控件的自带触感,补 selectionClick
      // (口径同 orders 筛选行)。
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 真源 `.wallet-tab`:未选中**无底色**(只有文字 secondary),
          // 选中才给 action-primary-bg 实心反色。
          color: selected ? CyTokens.actionPrimaryBg : Colors.transparent,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: CyTokens.typeLabel,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? CyTokens.actionPrimaryFg : CyTokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// .wallet-card:卡名 + 状态 tag + 描述 + 有效期/出示入口。
/// 待使用券描边加亮(border-strong)、带「出示核销码 ›」并整卡可点。
class _CouponCard extends StatelessWidget {
  const _CouponCard({required this.record});
  final CouponRecord record;

  @override
  Widget build(BuildContext context) {
    // 真源 `_canView/_isUsable` 拆分:待使用(0)可点开详情 —— 未到 start 的
    // 显示「查看可用时间」,已到 start 才显示「出示核销码」;已失效(3)等终态
    // 两者都不给,点进去是服务端挡死的死路。
    final canView = record.canView;
    final desc = record.displayDescription;
    return CupertinoButton(
      onPressed: canView
          ? () => context.push('/coupon/${record.id}/code')
          : null,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      child: Container(
        decoration: BoxDecoration(
          color: CyTokens.bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          border: Border.all(
            color: record.isUsable
                ? CyTokens.borderStrong
                : CyTokens.borderSubtle,
            width: 1,
          ),
        ),
        padding: EdgeInsets.all(CyTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    couponName(context, record),
                    style: const TextStyle(
                      fontSize: CyTokens.typeCardTitle,
                      fontWeight: FontWeight.w700,
                      color: CyTokens.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: CyTokens.space2),
                _CouponTag(record: record),
              ],
            ),
            if (desc.isNotEmpty) ...<Widget>[
              SizedBox(height: CyTokens.space2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: CyTokens.textSecondary,
                  height: CyTokens.leadingNormal,
                ),
              ),
            ],
            SizedBox(height: CyTokens.space2),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    couponDateLine(context, record),
                    style: const TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: CyTokens.textSecondary,
                    ),
                  ),
                ),
                if (canView)
                  // 真源 `.wallet-card__action`:文字 + 独立右箭头图标,
                  // 「›」字符冒充图标是小程序观感,换成系统符号。
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        record.isUsable ? stringsOf(context).couponWalletShowCode : stringsOf(context).couponWalletViewAvailability,
                        style: const TextStyle(
                          fontSize: CyTokens.typeCaption,
                          fontWeight: FontWeight.w600,
                          color: CyTokens.textPrimary,
                        ),
                      ),
                      SizedBox(width: CyTokens.space1),
                      const Icon(
                        CupertinoIcons.chevron_forward,
                        size: 12,
                        color: CyTokens.textPrimary,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态胶囊(对齐小程序 `cy-badge type="status"` 2026-09-01 改造版):
/// 前景 = 状态色、底 = 该色低透明软底、**前置 24rpx 图标在左**、无描边。
/// 待使用 = info(带 info 图标);已失效 = danger(带 warning 图标);
/// 已使用/已过期/未知 = neutral(真源 neutral 无默认图标 → 纯文字胶囊)。
/// 高度用 minHeight 而非死高:大字号下胶囊要能长高,不裁字(§9.3 人工清单)。
class _CouponTag extends StatelessWidget {
  const _CouponTag({required this.record});
  final CouponRecord record;

  @override
  Widget build(BuildContext context) {
    final bool danger = record.isDangerStatus;
    final bool info = record.isInfoStatus;
    final Color fg = info
        ? CyTokens.statusInfo
        : danger
        ? CyTokens.statusDanger
        : CyTokens.textTertiary;
    final Color bg = info
        ? CyTokens.statusInfo.withValues(alpha: 0.14)
        : danger
        ? CyTokens.statusDanger.withValues(alpha: 0.14)
        : CyTokens.textTertiary.withValues(alpha: 0.16);
    final IconData? icon = info
        ? CupertinoIcons.info_circle_fill
        : danger
        ? CupertinoIcons.exclamationmark_triangle_fill
        : null;
    return Container(
      constraints: const BoxConstraints(minHeight: 20), // 真源 40rpx
      padding: const EdgeInsets.symmetric(
        horizontal: 9, // 真源 18rpx(手册胶囊内距,量表无此档)
        vertical: 2,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: fg), // 真源 cy-icon size=24rpx
            SizedBox(width: CyTokens.space1), // 真源 gap 8rpx
          ],
          Text(
            couponStatus(context, record.useStatus),
            style: TextStyle(
              fontSize: CyTokens.typeLabel, // 真源 .bd__label 走 type-label
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
