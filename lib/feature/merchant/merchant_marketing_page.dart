import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/merchant_access_provider.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_progress.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_marketing.dart';
import 'merchant_error_view.dart';

final merchantMarketingProvider = FutureProvider.autoDispose<MerchantMarketing>(
  (ref) async {
    // ★ 前端闸先行:access/me 没确认过 marketing:read 就**不发这一枪**
    //   (小程序 #817 同口径 —— 403 只说明"这次请求身份没通过",
    //    岗位到底有没有权限是 access/me 的结论,不该拿 403 反推)。
    final MerchantAccess access = await ref.watch(
      merchantAccessProvider.future,
    );
    access.require('merchant:marketing:read', '营销数据');
    return ref.watch(merchantApiProvider).marketingHome();
  },
);

/// 商家营销。对齐小程序 `pages/merchant/marketing`。
class MerchantMarketingPage extends ConsumerWidget {
  const MerchantMarketingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantMarketingProvider);
    final textTheme = Theme.of(context).textTheme;

    final Widget body = async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (Object e, _) => switch (e) {
        // 无权限不是"页面坏了":说清缺哪项权限、出路在哪(店主调岗),
        // 按钮是「重新确认」——重读 access/me,调完岗一按就真的会变。
        MerchantAccessDeniedException() => merchantDeniedView(
          title: '你的岗位还没有营销数据权限',
          onRetry: () {
            ref.invalidate(merchantAccessProvider);
            ref.invalidate(merchantMarketingProvider);
          },
        ),
        _ => merchantErrorView(
          context,
          e,
          what: '营销',
          onRetry: () => ref.invalidate(merchantMarketingProvider),
        ),
      },
      data: (MerchantMarketing m) => RefreshIndicator.adaptive(
        onRefresh: () async => ref.invalidate(merchantMarketingProvider),
        child: ListView(
          padding: const EdgeInsets.all(CyTokens.pageX),
          children: <Widget>[
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const CySectionTitle('优惠券'),
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    children: <Widget>[
                      _kv(context, '在投', '${m.couponCount}'),
                      _kv(context, '已领', '${m.couponReceived}'),
                      _kv(context, '已核销', '${m.couponVerified}'),
                    ],
                  ),
                  // ★ 没人领过券时**整行不显示** —— 显示「核销率 0%」
                  //   会让商家以为券做得差,其实是根本没人领过。
                  if (m.verifyRate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space2),
                      child: Text(
                        '核销率 ${(m.verifyRate! * 100).toStringAsFixed(0)}%',
                        style: textTheme.bodySmall?.copyWith(
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: CyTokens.space2),
                  CupertinoButton(
                    onPressed: () => context.push('/merchant/coupons'),
                    padding: EdgeInsets.zero,
                    child: const Text('我发布的券 ›'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            _ActionRow(
              // 标题照小程序 `pages/merchant/marketing/index.js` 的入口 tile(店铺参谋)。
              title: '店铺参谋',
              onTap: () => context.push('/merchant/marketing/ai-insight'),
            ),
            const SizedBox(height: CyTokens.space3),
            _ActionRow(
              title: '口碑评价管理',
              onTap: () => context.push('/merchant/reviews'),
            ),
            // 真源 tiles「发主题/发自由探索」(marketing/index.js CONTENT_ROUTES):
            // 必须带 scope=MERCHANT,否则发布记到个人名下。
            const SizedBox(height: CyTokens.space3),
            _ActionRow(
              title: '发主题',
              onTap: () => context.push('/publish/pro?scope=MERCHANT'),
            ),
            const SizedBox(height: CyTokens.space3),
            _ActionRow(
              title: '发自由探索',
              onTap: () => context.push('/publish/pro?mode=2&scope=MERCHANT'),
            ),
            const SizedBox(height: CyTokens.space3),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const CySectionTitle('我的内容'),
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    children: <Widget>[
                      _kv(context, '主题', '${m.topicCount}'),
                      _kv(context, '自由探索', '${m.freeExploreCount}'),
                      _kv(context, '活动', '${m.activityCount}'),
                    ],
                  ),
                ],
              ),
            ),
            if (m.funnel.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const CySectionTitle('转化漏斗'),
                    const SizedBox(height: CyTokens.space2),
                    ...m.funnel.map((FunnelStep s) => _FunnelRow(step: s)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(middle: Text('营销')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: body),
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: textTheme.titleLarge),
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    void activate() {
      HapticFeedback.selectionClick();
      onTap();
    }

    return Semantics(
      button: true,
      label: title,
      onTap: activate,
      excludeSemantics: true,
      child: CupertinoButton(
        onPressed: activate,
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: CyTokens.space2,
            ),
            decoration: BoxDecoration(
              color: CyPalette.of(context).bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CyPalette.of(context).textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: CyPalette.of(context).textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  const _FunnelRow({required this.step});
  final FunnelStep step;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pct = step.ratePercent;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(step.step, style: textTheme.bodyMedium)),
              Text('${step.count}', style: textTheme.bodyMedium),
              // 比例解析不出来时不显示,不冒充 0%。
              if (pct != null)
                Padding(
                  padding: const EdgeInsets.only(left: CyTokens.space2),
                  child: Text(
                    pct,
                    style: textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            child: CyNativeProgress(
              progress: step.ratio,
              height: 4,
              semanticLabel: '${step.step}转化进度',
              trackColor: CyPalette.of(context).bgSurfaceStrong,
            ),
          ),
        ],
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
