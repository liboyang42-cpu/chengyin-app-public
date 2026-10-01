import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_insight.dart';
import 'merchant_error_view.dart';

final merchantInsightProvider = FutureProvider.autoDispose<MerchantInsight>((
  Ref ref,
) {
  return ref.watch(merchantApiProvider).merchantInsight();
});

/// 商家店铺参谋。对齐小程序
/// `pages/merchant/marketing/ai-insight/index`。
class MerchantAiInsightPage extends ConsumerWidget {
  const MerchantAiInsightPage({super.key, this.onOpenSuggestion});

  /// 页面默认用白名单路径导航；注入回调只用于宿主或测试接管导航。
  final ValueChanged<String>? onOpenSuggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MerchantInsight> async = ref.watch(
      merchantInsightProvider,
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 标题照小程序 `pages/merchant/marketing/ai-insight/index.wxml:7`(cy-nav-bar title)。
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantCouponAdvisor)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () =>
                // 真源 pages/merchant/marketing/ai-insight 用 merchant-metric 档。
                const CySkeleton(
                  type: CySkeletonType.merchantMetric,
                  count: 3,
                ),
            error: (Object error, StackTrace _) =>
                _errorView(context, ref, error),
            data: (MerchantInsight insight) => _InsightBody(
              insight: insight,
              refreshing: async.isRefreshing,
              onOpenSuggestion: (String route) {
                HapticFeedback.selectionClick();
                final ValueChanged<String>? callback = onOpenSuggestion;
                if (callback != null) {
                  callback(route);
                } else {
                  context.push(route);
                }
              },
              onRefresh: () => ref
                  .refresh(merchantInsightProvider.future)
                  .then<void>((MerchantInsight _) {}),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    void retry() => ref.invalidate(merchantInsightProvider);
    if (error is MerchantApiException &&
        (error.isClubLeaderConflict ||
            error.isPendingReview ||
            error.isNotMerchant)) {
      return merchantErrorView(context, error, what: stringsOf(context).merchantCouponStoreData, onRetry: retry);
    }
    return StatusView(
      message: stringsOf(context).merchantCouponDataFailed,
      sub: error.toString().replaceFirst('Exception: ', ''),
      large: true,
      onRetry: retry,
      retryLabel: stringsOf(context).merchantCouponReload,
    );
  }
}

class _InsightBody extends StatelessWidget {
  const _InsightBody({
    required this.insight,
    required this.refreshing,
    required this.onOpenSuggestion,
    required this.onRefresh,
  });

  final MerchantInsight insight;

  /// 屏上已有事实、正在读新的一份(小程序 `insight-sync`:刷新时得说一句,
  /// 否则用户以为这就是最新一版)。
  final bool refreshing;
  final ValueChanged<String> onOpenSuggestion;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final MerchantInsightFacts facts = insight.facts;
    final MerchantInsightAi? ai = insight.ai;
    final List<MerchantInsightHourBucket> hours = facts.checkin.hourBuckets;

    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space2,
          CyTokens.pageX,
          CyTokens.space8,
        ),
        children: <Widget>[
          if (refreshing)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  stringsOf(context).merchantCouponUpdating,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: CyTokens.typeCaption,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
            ),
          if (insight.generatedAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: CyTokens.space1,
                bottom: CyTokens.space2,
              ),
              child: Text(
                stringsOf(context).merchantCouponGenerated(insight.generatedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: CyTokens.typeCaption,
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
          _MetricCard(
            tone: _MetricTone.a,
            icon: CupertinoIcons.qrcode_viewfinder,
            name: stringsOf(context).merchantCouponCheckins,
            value: '${facts.checkin.total}',
            denominator: '/ ${facts.window.isEmpty ? stringsOf(context).merchantCouponThirtyDays : facts.window}',
            badge: stringsOf(context).merchantCouponRedeemMetric(facts.checkin.redeemRateText),
            filledSegments: facts.checkin.segmentFillCount,
          ),
          const SizedBox(height: CyTokens.space2_5),
          _MetricCard(
            tone: _MetricTone.b,
            icon: CupertinoIcons.heart,
            name: stringsOf(context).merchantCouponCustomers,
            value: '${facts.crowd.members}',
            denominator: '/ ${facts.window.isEmpty ? stringsOf(context).merchantCouponThirtyDays : facts.window}',
            badge: stringsOf(context).merchantCouponRepeatMetric(facts.checkin.repeatRateText),
            filledSegments: facts.checkin.repeatSegmentFillCount,
          ),
          const SizedBox(height: CyTokens.space2_5),
          _MetricCard(
            tone: _MetricTone.a,
            icon: CupertinoIcons.flag,
            name: stringsOf(context).merchantCouponCoopPlaces,
            value: '${facts.supply.activeOffers}',
            denominator: stringsOf(context).merchantCouponListed,
            badge: stringsOf(context).merchantCouponQuotaMetric(facts.supply.quotaUsedRateText),
            filledSegments: facts.supply.segmentFillCount,
          ),
          if (hours.isNotEmpty) ...<Widget>[
            _SectionHeader(
              title: stringsOf(context).merchantCouponVisitTimes,
              trailing: facts.checkin.avgWaitMinutes == null
                  ? null
                  : stringsOf(context).merchantCouponWaitMetric(facts.checkin.avgWaitMinutes.toString()),
            ),
            _SurfaceCard(child: _HourChart(hours: hours)),
          ] else ...<Widget>[
            const SizedBox(height: CyTokens.space4),
            _InlineEmpty(
              title: stringsOf(context).merchantCouponNoVisits,
              sub: stringsOf(context).merchantCouponNoVisitsBody,
            ),
            // 空态光说「还没有」是死路一条;给一条真能走的下一步
            // (小程序 `.empty-cta` → 合作中心)。
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              width: double.infinity,
              height: CyTokens.btnH,
              child: CyNativeButton(
                onPressed: () => onOpenSuggestion('/merchant/coop'),
                label: stringsOf(context).merchantCouponOpenCoop,
                width: double.infinity,
                icon: const CyNativeButtonIcon(
                  sfSymbol: 'chevron.forward',
                  fallback: CupertinoIcons.chevron_forward,
                ),
              ),
            ),
          ],
          if (facts.crowd.members > 0) ...<Widget>[
            _SectionHeader(
              title: stringsOf(context).merchantCouponAudienceMix,
              trailing: stringsOf(context).merchantCouponVisitorCount(facts.crowd.members),
            ),
            _SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (facts.crowd.sexText.isNotEmpty)
                    Row(
                      children: <Widget>[
                        Text(
                          stringsOf(context).merchantCouponGender,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: CyTokens.typeLabel,
                                color: CyPalette.of(context).textSecondary,
                              ),
                        ),
                        const SizedBox(width: CyTokens.space2),
                        Text(
                          stringsOf(context).merchantCouponGenderRates(merchantInsightPercent(facts.crowd.maleRate), merchantInsightPercent(facts.crowd.femaleRate)),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: CyTokens.typeLabel,
                                color: CyPalette.of(context).textPrimary,
                              ),
                        ),
                      ],
                    ),
                  if (facts.crowd.interestTop.isNotEmpty) ...<Widget>[
                    const SizedBox(height: CyTokens.space2),
                    Wrap(
                      spacing: CyTokens.space2,
                      runSpacing: CyTokens.space2,
                      children: facts.crowd.interestTop
                          .map((String label) => _InsightChip(label: label))
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // 区块标题照原文(`index.wxml:137`:sec-title「经营解读」),不带 AI 前缀。
          _SectionHeader(title: stringsOf(context).merchantCouponInsights),
          if (ai != null)
            _SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ★ 样本太少时先说清「仅供参考」(快照 index.wxml:139)——
                  //   拿 3 个玩家编出的经营结论不标,商家会当真。
                  if (facts.lowSample) ...<Widget>[
                    Text(
                      stringsOf(context).merchantCouponLowSample,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: CyTokens.typeCaption,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                  ],
                  Text(
                    ai.summary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: CyTokens.typeLabel,
                      height: CyTokens.leadingLoose,
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                  if (ai.audiences.isNotEmpty) ...<Widget>[
                    const SizedBox(height: CyTokens.space3),
                    Text(
                      stringsOf(context).merchantCouponAudiences,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: CyTokens.typeCaption,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Wrap(
                      spacing: CyTokens.space2,
                      runSpacing: CyTokens.space2,
                      children: ai.audiences
                          .where(
                            (MerchantInsightAudience item) =>
                                item.label.isNotEmpty,
                          )
                          .map(
                            (MerchantInsightAudience item) =>
                                _InsightChip(label: item.label),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            )
          else
            _SurfaceCard(
              child: Column(
                children: <Widget>[
                  Text(
                    // 照原文 `index.wxml:156`:aiError 优先,否则「智能解读暂不可用」,

                    // 句末「，上方经营数据不受影响」。

                    stringsOf(context).merchantCouponAiError(insight.aiError.isEmpty ? stringsOf(context).merchantCouponUnavailable : insight.aiError),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: CyTokens.typeLabel,
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space2),
                  // 解读可以单独重来:AI 空转一次不该逼用户重进整页
                  // (小程序 `ai-down-action`,aria-label「重新生成经营解读」)。
                  Semantics(
                    button: true,
                    label: stringsOf(context).merchantCouponRegenerateSemantics,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      onPressed: onRefresh,
                      child: Text(stringsOf(context).merchantCouponRegenerate),
                    ),
                  ),
                ],
              ),
            ),
          // ★ 推荐区是**后端下发的真实主体**(招商中主题 / 附近商家),不是 AI 编的
          //   —— 所以 AI 降级了它也照常出。
          if (insight.recommendedTopics.isNotEmpty) ...<Widget>[
            _SectionHeader(title: stringsOf(context).merchantCouponRecommendedThemes),
            ...insight.recommendedTopics.map(
              (MerchantInsightTopic topic) => Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2_5),
                child: _RecTopicCard(
                  topic: topic,
                  onOpen: () => onOpenSuggestion('/merchant/coop'),
                ),
              ),
            ),
          ],
          if (insight.recommendedPartners.isNotEmpty) ...<Widget>[
            _SectionHeader(title: stringsOf(context).merchantCouponRecommendedPartners),
            ...insight.recommendedPartners.map(
              (MerchantInsightPartner partner) => Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2_5),
                child: _RecPartnerCard(
                  partner: partner,
                  // 没有 memberId 就拼不出 canonical 主页 —— 不给能按的按钮,
                  // 别送用户去一个猜出来的地址(小程序同判据)。
                  onOpen: partner.memberId > 0
                      ? () => onOpenSuggestion(
                          '/merchant/public-home/member/${partner.memberId}',
                        )
                      : null,
                ),
              ),
            ),
          ],
          if (ai != null && ai.suggestions.isNotEmpty) ...<Widget>[
            _SectionHeader(title: stringsOf(context).merchantCouponSuggestedActivities),
            ...ai.suggestions.map(
              (MerchantInsightSuggestion suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2_5),
                child: _SuggestionCard(
                  suggestion: suggestion,
                  onOpen: onOpenSuggestion,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _MetricTone { a, b }

// 小程序页面私有指标卡 token；它们不是全局品牌色。
const Color _metricCardA = Color(0xFF2A2A47);
const Color _metricCardB = Color(0xFF243039);
const Color _metricSegmentA = Color(0xFFA5A6E8);
const Color _metricSegmentB = Color(0xFF93A9B9);
const Color _metricInk = Color(0xFFF2F0EA);
const Color _metricInkDim = Color(0x8CF2F0EA);
const Color _metricIconBg = Color(0x59000000);
const Color _metricSegmentOff = Color(0x40FFFFFF);

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.tone,
    required this.icon,
    required this.name,
    required this.value,
    required this.denominator,
    required this.badge,
    required this.filledSegments,
  });

  final _MetricTone tone;
  final IconData icon;
  final String name;
  final String value;
  final String denominator;
  final String badge;
  final int filledSegments;

  @override
  Widget build(BuildContext context) {
    final Color card = tone == _MetricTone.a ? _metricCardA : _metricCardB;
    final Color segment = tone == _MetricTone.a
        ? _metricSegmentA
        : _metricSegmentB;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$name，$value，$badge',
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.space4,
          CyTokens.space3_5,
          CyTokens.space4,
          CyTokens.space4,
        ),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(CyTokens.radiusXl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: _metricIconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: _metricInk),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _metricInk,
                      fontSize: CyTokens.typeBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2_5,
                    vertical: CyTokens.space1,
                  ),
                  decoration: BoxDecoration(
                    color: CyPalette.of(context).bgSurface,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  ),
                  child: Text(
                    badge,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textPrimary,
                      fontSize: CyTokens.typeCaption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space2_5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  value,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: _metricInk,
                    fontSize: CyTokens.typeDisplay,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Padding(
                  padding: const EdgeInsets.only(bottom: CyTokens.space1),
                  child: Text(
                    denominator,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _metricInkDim,
                      fontSize: CyTokens.typeCaption,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space3),
            Row(
              children: List<Widget>.generate(10, (int index) {
                final bool on = index < filledSegments;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == 9 ? 0 : CyTokens.space1_5,
                    ),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: on ? segment : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          CyTokens.radiusPill,
                        ),
                        border: Border.all(
                          color: on ? segment : _metricSegmentOff,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space1,
        CyTokens.space4,
        CyTokens.space1,
        CyTokens.space2,
      ),
      child: CySectionTitle(
        title,
        trailing: trailing == null
            ? null
            : Text(
                trailing!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.cardBorder),
        boxShadow: palette.cardShadow,
      ),
      child: child,
    );
  }
}

class _HourChart extends StatelessWidget {
  const _HourChart({required this.hours});

  final List<MerchantInsightHourBucket> hours;

  @override
  Widget build(BuildContext context) {
    final int maxCount = hours.fold<int>(
      0,
      (int max, MerchantInsightHourBucket item) =>
          item.count > max ? item.count : max,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: hours
          .map((MerchantInsightHourBucket item) {
            final double ratio = maxCount == 0
                ? 0
                : (item.count / maxCount).clamp(0.08, 1.0);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space1,
                ),
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 60,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: ratio,
                          child: Container(
                            width: 12,
                            decoration: BoxDecoration(
                              color: CyPalette.of(context).brand,
                              borderRadius: BorderRadius.circular(
                                CyTokens.radiusSm,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      stringsOf(context).merchantCouponHour(item.hour),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: CyTokens.typeCaption,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2_5,
        vertical: CyTokens.space1,
      ),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgPage,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: CyTokens.typeCaption,
          color: CyPalette.of(context).textPrimary,
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.title, required this.sub});

  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space4,
        vertical: CyTokens.space6,
      ),
      child: Column(
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: CyTokens.typeBody,
              color: CyPalette.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: CyTokens.space1_5),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: CyTokens.typeLabel,
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 推荐主题卡:封面 + 自由探索/招商中 + 理由 + 「去申请承接」。
///
/// 对齐小程序 `pages/merchant/marketing/ai-insight/index.wxml` 的 `tcard`:
/// 字段(封面/两枚角标/主题名/理由/承接入口)1:1,外观走 iOS 内容层卡片。
class _RecTopicCard extends StatelessWidget {
  const _RecTopicCard({required this.topic, required this.onOpen});

  final MerchantInsightTopic topic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                child: CyNetImage(topic.coverUrl, width: 64, height: 64),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      topic.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        fontSize: CyTokens.typeBody,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Wrap(
                      spacing: CyTokens.space1_5,
                      runSpacing: CyTokens.space1,
                      children: <Widget>[
                        _InsightChip(label: stringsOf(context).merchantCouponExploration),
                        _InsightChip(label: stringsOf(context).merchantCouponRecruiting),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space2_5),
          Text(
            // 理由缺失时用小程序那句兜底,不留空(空一行比差一句更让人猜)。
            topic.reason.isEmpty ? stringsOf(context).merchantCouponTopicFallback : topic.reason,
            style: t.bodySmall?.copyWith(
              fontSize: CyTokens.typeLabel,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          SizedBox(
            width: double.infinity,
            height: CyTokens.btnH,
            child: CyNativeButton(
              onPressed: onOpen,
              label: stringsOf(context).merchantCouponApply,
              width: double.infinity,
              icon: const CyNativeButtonIcon(
                sfSymbol: 'chevron.forward',
                fallback: CupertinoIcons.chevron_forward,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 推荐联动商家卡:封面 + 营业态/可联动 + 城市角色/标语 + 距离·品类 + 标签 + 理由 + 「发起接洽」。
class _RecPartnerCard extends StatelessWidget {
  const _RecPartnerCard({required this.partner, required this.onOpen});

  final MerchantInsightPartner partner;

  /// null = 拿不到 memberId,拼不出 canonical 商家主页 ⇒ 按钮置灰。
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final String meta = <String>[
      if (partner.distanceText.isNotEmpty) partner.distanceText,
      if (partner.category.isNotEmpty) partner.category,
    ].join(' · ');
    final String thumb = partner.coverImage.isNotEmpty
        ? partner.coverImage
        : partner.logo;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                child: CyNetImage(thumb, width: 64, height: 64),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        fontSize: CyTokens.typeBody,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Wrap(
                      spacing: CyTokens.space1_5,
                      runSpacing: CyTokens.space1,
                      children: <Widget>[
                        if (partner.isOpen) _InsightChip(label: stringsOf(context).merchantCouponOpen),
                        _InsightChip(label: stringsOf(context).merchantCouponAvailable),
                      ],
                    ),
                    if (partner.cityRole.isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space1_5),
                      Text(
                        partner.cityRole,
                        style: t.bodySmall?.copyWith(
                          fontSize: CyTokens.typeCaption,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                    if (partner.slogan.isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        partner.slogan,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(
                          fontSize: CyTokens.typeLabel,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              meta,
              style: t.bodySmall?.copyWith(
                fontSize: CyTokens.typeCaption,
                color: p.textSecondary,
              ),
            ),
          ],
          if (partner.tagsArr.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Wrap(
              spacing: CyTokens.space1_5,
              runSpacing: CyTokens.space1,
              children: partner.tagsArr
                  .map((String tag) => CyTag(label: tag))
                  .toList(growable: false),
            ),
          ],
          if (partner.reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              partner.reason,
              style: t.bodySmall?.copyWith(
                fontSize: CyTokens.typeLabel,
                color: p.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space3),
          SizedBox(
            width: double.infinity,
            height: CyTokens.btnH,
            child: CyNativeButton(
              onPressed: onOpen,
              label: stringsOf(context).merchantCouponContact,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onOpen});

  final MerchantInsightSuggestion suggestion;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final String? route = suggestion.routePath;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  suggestion.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: CyTokens.typeBody,
                    color: CyPalette.of(context).textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (suggestion.timeSlot.isNotEmpty)
                Text(
                  suggestion.timeSlot,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: CyTokens.typeCaption,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
            ],
          ),
          if (suggestion.audience.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space1_5),
            Text(
              stringsOf(context).merchantCouponForAudience(suggestion.audience),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: CyTokens.typeLabel,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
          ],
          if (suggestion.reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space1_5),
            Text(
              suggestion.reason,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: CyTokens.typeLabel,
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space3),
          SizedBox(
            width: double.infinity,
            height: CyTokens.btnH,
            child: CyNativeButton(
              onPressed: route == null ? null : () => onOpen(route),
              label: stringsOf(context).merchantCouponOrganize,
              width: double.infinity,
              icon: const CyNativeButtonIcon(
                sfSymbol: 'chevron.forward',
                fallback: CupertinoIcons.chevron_forward,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
