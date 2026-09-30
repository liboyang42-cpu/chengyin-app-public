// 积分页顶部 hero:我的积分 / 本周获得。
//
// 对应小程序 components/cy/profile 的 .pts-hero(积分弹窗顶部两栏)。
// ★ 落点选积分页而不是「我的」:小程序那两栏本来就长在积分弹窗里,
//   而 App 的「我的」那份文件正在被别的工作改。
//
// ★★ 口径不许合并 —— 小程序那段注释专门写了这条:
//   「我的积分」是累计余额,「本周获得」是周值(weekPoints),
//   两个口径不同,别用一个「本周」把它们盖在一起。
//
// ⚠️ 拿不到就**不显示这一栏**,不兜 0。「这周没赚到」和「统计没算出来」
//   是两回事,兜 0 会把后者说成前者。PointsStatistics.weekPoints 因此是可空的。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/points_statistics.dart';

/// 统计拉失败**不该把整页打红** —— 明细才是这页的主体。
/// 所以这里吞掉异常返回 null,由 UI 决定不渲染那一栏。
final pointsStatProvider = FutureProvider.autoDispose<PointsStatistics?>((
  Ref ref,
) async {
  try {
    return await ref.watch(registrationApiProvider).pointsStatistics();
  } catch (_) {
    return null;
  }
});

class PointsHero extends ConsumerWidget {
  const PointsHero({super.key, required this.balance});

  /// 当前可用积分(明细里最新一条的 afterPoints)。null = 还没拿到。
  final int? balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CyPalette p = CyPalette.of(context);
    final PointsStatistics? stat = ref.watch(pointsStatProvider).value;
    final String? week = stat?.weekPoints?.trim();
    final String? rank = stat?.rankPercentage?.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        0,
        CyTokens.space4,
        CyTokens.space3,
      ),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _Col(
                  label: '我的积分',
                  // 余额没拿到给「—」,不给 0。
                  value: balance?.toString() ?? '—',
                  valueKey: const Key('points-hero-balance'),
                ),
              ),
              // 分隔线两侧要留白 —— 贴着数字会被读成数字的一部分(实拍确认)。
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
                // 强分隔档:subtle 在 28pt 数字旁边几乎看不见(小程序同一处用
                // --cy-color-border-strong)。
                color: p.borderStrong,
              ),
              Expanded(
                child: week == null || week.isEmpty
                    // ★ 统计没算出来 ⇒ 说「暂无」,不写 +0。
                    ? const _Col(
                        label: '本周获得',
                        value: '暂无',
                        valueKey: Key('points-hero-week'),
                      )
                    : _Col(
                        label: '本周获得',
                        value: '+$week',
                        valueKey: const Key('points-hero-week'),
                      ),
              ),
            ],
          ),
          if (rank != null && rank.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              // 后端给的是**字符串**(可能自带 % 号),原样透出,别自己拼百分号。
              '超过 $rank 的探索者',
              key: const Key('points-hero-rank'),
              style: CyType.caption2.copyWith(color: p.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Col extends StatelessWidget {
  const _Col({
    required this.label,
    required this.value,
    required this.valueKey,
  });
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          // T2:12pt 落 caption1 梯级(原 typeLabel 同值),随 Dynamic Type 缩放。
          style: CyType.caption1.copyWith(color: p.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          key: valueKey,
          // title1 28 = 原 typeDisplay 同值;T3 强调用 Bold(小程序同一数值 700)。
          style: CyType.title1.copyWith(
            height: 1,
            fontWeight: FontWeight.w700,
            // 等宽数字:防止刷新时数字换位抖动。
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            color: p.textPrimary,
          ),
        ),
      ],
    );
  }
}
