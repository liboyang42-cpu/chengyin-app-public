import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../data/models/official_event.dart';

/// 「即将开始」的窗口:开始时刻落在 `[now, now + 24h)`。
const Duration squareUpcomingWindow = Duration(hours: 24);

/// 横滑卡的数据(纯值,渲染层不碰时钟)。
@immutable
class SquareUpcomingCard {
  const SquareUpcomingCard({
    required this.eventId,
    required this.title,
    required this.sub,
    required this.countdown,
    required this.avatars,
    required this.overflow,
  });

  final int eventId;
  final String title;

  /// 副标:优先 `subtitle`,没有就用城市(真源 `subtitle || city`)。
  final String sub;
  final String countdown;

  /// 最多 3 个,多了折成 [overflow]。
  final List<String> avatars;
  final int overflow;
}

/// 挑出「即将开始」的活动。三个条件缺一不可,顺序就是它们各自挡掉的东西:
///   1. [OfficialEvent.bannerEnabled] —— 复用运营既有的推广开关,不另造一套;
///   2. `status` 1(即将开始)/ 2(报名中)—— 已开赛/已结束的不是「即将」;
///   3. 开始时刻在 `[now, now + 24h)` —— 「临近」的量化,已过开始时刻的落在窗口外。
///
/// 真源 `pages/square/list/index.js:657-722`。`now` 由调用方传,
/// 不在函数里取 —— 否则测不了(本项目栽过「当前时间不可控」的坑)。
List<OfficialEvent> selectSquareUpcomingEvents(
  List<OfficialEvent> rows,
  DateTime now,
) {
  final List<OfficialEvent> near = <OfficialEvent>[];
  for (final OfficialEvent e in rows) {
    if (!e.bannerEnabled) continue;
    if (e.status != 1 && e.status != 2) continue;
    final DateTime? start = e.activityStart;
    if (start == null) continue;
    final Duration delta = start.difference(now);
    if (delta.isNegative || delta >= squareUpcomingWindow) continue;
    near.add(e);
  }
  near.sort(
    (OfficialEvent a, OfficialEvent b) =>
        a.activityStart!.compareTo(b.activityStart!),
  );
  return near;
}

/// 倒计时文案,**逐字**照真源 `pages/square/list/index.js:24-33`。
///
/// ★ 不足 1 分钟说「马上开始」而不是「即将开始」:卡片左上角的 kicker
///   已经写着「即将开始」,同一张卡上重复两遍读起来像渲染出错。
String squareUpcomingCountdown(Duration delta) {
  if (delta <= Duration.zero) return '马上开始';
  final int hours = delta.inHours;
  if (hours >= 24) return '${hours ~/ 24} 天后开始';
  if (hours >= 1) return '$hours 小时后开始';
  final int minutes = delta.inMinutes;
  return minutes >= 1 ? '$minutes 分钟后开始' : '马上开始';
}

/// 活动列表 → 横滑卡数据。参与者人数取 `participants`,头像最多留 3 个,
/// 溢出数按「人数 - 已显示头像数」算(与真源一致:人数少于头像数时取 0)。
List<SquareUpcomingCard> squareUpcomingCards(
  List<OfficialEvent> rows,
  DateTime now,
) {
  return selectSquareUpcomingEvents(rows, now)
      .map((OfficialEvent e) {
        final List<String> avatars = e.participantAvatars
            .take(3)
            .toList(growable: false);
        final int known = e.participants < e.participantAvatars.length
            ? e.participantAvatars.length
            : e.participants;
        return SquareUpcomingCard(
          eventId: e.id,
          title: e.title,
          sub: (e.subtitle ?? '').trim().isNotEmpty
              ? e.subtitle!.trim()
              : (e.city ?? '').trim(),
          countdown: squareUpcomingCountdown(e.activityStart!.difference(now)),
          avatars: avatars,
          overflow: avatars.isEmpty || known <= avatars.length
              ? 0
              : known - avatars.length,
        );
      })
      .toList(growable: false);
}

/// 广场顶部「即将开始」的数据源。
///
/// ★ 与官方活动列表**同一个端点**(`GET /api/official/events`),不另开后门;
///   筛选与倒计时在客户端做(真源也是这么做的,后端不下发「倒计时」)。
/// ★ `autoDispose`:离开广场就释放,不进页面不请求。
/// ★ 失败**静默**:真源 `silentError: true` —— 这块是锦上添花的提醒,
///   它挂了不该在信息流顶上糊一张错误卡(阅读体验被一块推广位打断)。
final squareUpcomingCardsProvider =
    FutureProvider.autoDispose<List<SquareUpcomingCard>>((Ref ref) async {
      final List<OfficialEvent> rows = await ref
          .watch(officialApiProvider)
          .events();
      return squareUpcomingCards(rows, DateTime.now());
    });

/// 广场顶部「即将开始」横滑卡(真源 `pages/square/list/index.wxml:20-38`)。
///
/// ★ 一条都没有时**整块不渲染** —— 真源同理(`upcomingCards.length` 为 0
///   时 WXML 整块不出现),不留一个空标题或空轨道。
/// ★ 卡片是 `CupertinoButton`:44pt 最小热区、原生按压态、语义齐全。
class SquareUpcomingTrack extends StatelessWidget {
  const SquareUpcomingTrack({super.key, required this.cards, this.onOpen});

  final List<SquareUpcomingCard> cards;

  /// 测试注入用。缺省直接 `context.push('/official/<id>')`。
  final void Function(BuildContext context, int eventId)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 单张时铺满(真源 `is-single`),多张时固定宽度并露出下一张的边。
        final double cardWidth = cards.length == 1
            ? constraints.maxWidth
            : (constraints.maxWidth * 0.72).clamp(200.0, 280.0);
        return SingleChildScrollView(
          key: const Key('square-upcoming-track'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            0,
          ),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < cards.length; i++) ...<Widget>[
                SizedBox(
                  width: cardWidth,
                  child: _UpcomingCard(
                    card: cards[i],
                    onPressed: () {
                      if (onOpen != null) {
                        onOpen!(context, cards[i].eventId);
                        return;
                      }
                      context.push('/official/${cards[i].eventId}');
                    },
                  ),
                ),
                if (i < cards.length - 1)
                  const SizedBox(width: CyTokens.space2),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.card, required this.onPressed});

  final SquareUpcomingCard card;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${card.title}，${card.countdown}',
      child: CupertinoButton(
        key: Key('square-upcoming-card-${card.eventId}'),
        padding: EdgeInsets.zero,
        minimumSize: const Size.fromHeight(44),
        onPressed: onPressed,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: palette.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '即将开始',
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      card.countdown,
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CyTokens.space2),
                Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (card.sub.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    card.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ],
                if (card.avatars.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    children: <Widget>[
                      for (final String url in card.avatars)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: ClipOval(
                            child: CyNetImage(url, width: 20, height: 20),
                          ),
                        ),
                      if (card.overflow > 0) ...<Widget>[
                        const SizedBox(width: CyTokens.space1),
                        Text(
                          '+${card.overflow}',
                          style: textTheme.labelSmall?.copyWith(
                            color: palette.textTertiary,
                          ),
                        ),
                      ],
                      const SizedBox(width: CyTokens.space1),
                      Text(
                        '参与者',
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
