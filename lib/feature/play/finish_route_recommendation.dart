// 完赛弹层「附近下一程」推荐卡 —— 1:1 移植 pages/play/finish-route-recommendation.js
// 与 pages/play/index.js loadFinishRouteRecommendation。
// 差异登记:真源长按/滑动之外用 this._loc(游玩期已采集的被动定位),App 在弹层打开时
// 重新取一次 current(),失败即回退到节点坐标;端上无 analytics,shown/click 埋点不移植。
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feature_flags.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../data/models/activity.dart';
import '../../data/models/checkin_models.dart';
import 'play_session_controller.dart';

/// utils/geo.js distanceText:>=1km 显示 "N.N 公里",否则 "N 米"。
String cyDistanceText(double? meters) {
  if (meters == null) return '';
  return meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)} 公里'
      : '${meters.round()} 米';
}

class FinishRouteRecommendation {
  const FinishRouteRecommendation({
    required this.id,
    required this.title,
    required this.cover,
    required this.meta,
    required this.priceText,
  });

  final int id;
  final String title;
  final String cover;
  final String meta;
  final String priceText;
}

/// resolveOrigin:优先有效坐标,否则回退最后一个已打卡(含坐标)节点。
/// 真源按 doneAt 降序取最近完成节点,App 的 PlayNode 无 doneAt,按 sortId 取最大。
({double latitude, double longitude})? resolveFinishOrigin({
  double? latitude,
  double? longitude,
  List<PlayNode> nodes = const <PlayNode>[],
}) {
  if ((latitude?.isFinite ?? false) && (longitude?.isFinite ?? false)) {
    return (latitude: latitude!, longitude: longitude!);
  }
  PlayNode? last;
  for (final PlayNode node in nodes) {
    if (!node.done) continue;
    final double? lat = node.latitude;
    final double? lng = node.longitude;
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat == 0 ||
        lng == 0) {
      continue;
    }
    if (last == null || node.sortId > last.sortId) last = node;
  }
  if (last == null) return null;
  return (latitude: last.latitude!, longitude: last.longitude!);
}

/// pickCandidate:第一条既不是本次活动也不是本主题的候选。
FinishRouteRecommendation? pickFinishRouteCandidate(
  List<Activity> rows, {
  int? currentActivityId,
  int? currentTopicId,
}) {
  for (final Activity row in rows) {
    if (row.id == 0) continue;
    if ((currentActivityId ?? 0) != 0 &&
        row.id.toString() == currentActivityId.toString()) {
      continue;
    }
    if ((currentTopicId ?? 0) != 0 &&
        (row.topicId?.toString() ?? '') == currentTopicId.toString()) {
      continue;
    }
    final double? distance = row.distance;
    final String address = (row.addressName ?? '').isNotEmpty
        ? row.addressName!
        : (row.address ?? '');
    final String meta = <String>[
      (distance?.isFinite ?? false) ? cyDistanceText(distance) : '',
      address,
    ].where((String part) => part.isNotEmpty).join(' · ');
    final double? amount = row.minAmount;
    return FinishRouteRecommendation(
      id: row.id,
      title: row.name.isEmpty ? '附近路线' : row.name,
      cover: (row.imgUrl ?? '').split(',').first,
      meta: meta,
      priceText: amount == null
          ? ''
          : amount > 0
          ? '¥${_numberText(amount)} 起'
          : '免费',
    );
  }
  return null;
}

/// JS `Number(x) + ''` 的显示口径:整数不带 .0。
String _numberText(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class FinishRouteRecommendationSlot extends ConsumerStatefulWidget {
  const FinishRouteRecommendationSlot({
    super.key,
    required this.activityId,
    required this.topicId,
    required this.nodes,
  });

  final int? activityId;
  final int? topicId;
  final List<PlayNode> nodes;

  @override
  ConsumerState<FinishRouteRecommendationSlot> createState() =>
      _FinishRouteRecommendationSlotState();
}

class _FinishRouteRecommendationSlotState
    extends ConsumerState<FinishRouteRecommendationSlot> {
  FinishRouteRecommendation? _card;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final int requestEpoch = ++_epoch;
    if (!ref.read(featureFlagProvider('finishNearbyRoute'))) return;
    final ({double latitude, double longitude})? origin =
        await _resolveOrigin();
    if (origin == null || !mounted || requestEpoch != _epoch) return;
    List<Activity> rows;
    try {
      rows = await ref
          .read(activityApiProvider)
          .list(
            isMy: 0,
            sortType: '1',
            pageNum: 1,
            pageSize: 5,
            longitude: origin.longitude.toString(),
            latitude: origin.latitude.toString(),
          );
    } catch (_) {
      // 推荐是完赛后的增强能力;加载失败只表现为「没有这张卡」。
      return;
    }
    if (!mounted || requestEpoch != _epoch) return;
    final FinishRouteRecommendation? card = pickFinishRouteCandidate(
      rows,
      currentActivityId: widget.activityId,
      currentTopicId: widget.topicId,
    );
    if (card == null) return;
    setState(() => _card = card);
  }

  Future<({double latitude, double longitude})?> _resolveOrigin() async {
    double? latitude;
    double? longitude;
    try {
      final PlayNavigationPosition position = await ref
          .read(playNavigationLocationSourceProvider)
          .current();
      latitude = position.latitude;
      longitude = position.longitude;
    } catch (_) {
      // 定位不可用时回退节点坐标。
    }
    if (!mounted) return null;
    return resolveFinishOrigin(
      latitude: latitude,
      longitude: longitude,
      nodes: widget.nodes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final FinishRouteRecommendation? card = _card;
    if (card == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space4),
      child: Semantics(
        button: true,
        label: '查看附近路线${card.title}并购票',
        child: CupertinoButton(
          key: const Key('finish-route-recommendation'),
          onPressed: () => context.push('/activity/${card.id}'),
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          padding: const EdgeInsets.all(CyTokens.space3),
          child: Row(
            children: <Widget>[
              if (card.cover.isNotEmpty) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  child: SizedBox.square(
                    dimension: 66,
                    child: CyNetImage(
                      card.cover,
                      width: 66,
                      height: 66,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      '附近下一程',
                      style: TextStyle(
                        color: Color(0xFF5E5CE6),
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (card.meta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        card.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6A7282),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (card.priceText.isNotEmpty) ...<Widget>[
                          Text(
                            card.priceText,
                            style: const TextStyle(
                              color: Color(0xFF111111),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        const Text(
                          '查看票价并购票',
                          style: TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          CupertinoIcons.arrow_right,
                          color: Color(0xFF111111),
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
