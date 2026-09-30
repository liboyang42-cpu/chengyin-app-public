import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_native_progress.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../data/models/checkin_models.dart';
import 'finish_route_recommendation.dart';

Future<void> showClassicPlayStorySheet(
  BuildContext context, {
  required PlayNode node,
  required int step,
}) => showCyNativeSheet<void>(
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  context,
  // 真源剧情面近乎全屏(`topGap .08` 即 B1 回退档的默认值)。
  detents: CyNativeSheetDetents.large,
  // 面自带关闭钮,系统 grabber 让路,免得两条叠着。
  grabber: false,
  builder: (BuildContext sheetContext) => ClassicPlayStorySurface(
    node: node,
    step: step,
    onClose: () => Navigator.of(sheetContext).pop(),
  ),
);

class ClassicPlayJournalPage extends StatelessWidget {
  const ClassicPlayJournalPage({
    super.key,
    required this.chapter,
    required this.nodes,
  });

  final PlayChapter chapter;
  final List<PlayNode> nodes;

  @override
  Widget build(BuildContext context) {
    final List<PlayNode> ordered = <PlayNode>[...nodes]
      ..sort((PlayNode a, PlayNode b) => a.sortId.compareTo(b.sortId));
    final int done = ordered.where((PlayNode node) => node.done).length;
    final double progress = ordered.isEmpty ? 0 : done / ordered.length;

    return CupertinoPageScaffold(
      key: const Key('classic-play-journal'),
      backgroundColor: CupertinoColors.black,
      child: Material(
        color: CupertinoColors.black,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 14, 0),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            chapter.title ?? chapter.meta ?? '旅程手记',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF999999),
                              fontSize: 15,
                              letterSpacing: 5,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          key: const Key('classic-play-journal-close'),
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Semantics(
                            // 小程序这枚关闭钮的 aria-label(pages/play/index.wxml:1248)。
                            // 可见字仍是一个「合上」,读屏得听到关的是哪一页。
                            label: '合上旅程手记',
                            button: true,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  '合上',
                                  style: TextStyle(color: Color(0xFF999999)),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  CupertinoIcons.arrow_right,
                                  size: 16,
                                  color: Color(0xFF999999),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    CyNativeProgress(
                      progress: progress,
                      semanticLabel: '章节完成进度',
                      height: 2,
                      progressColor: const Color(0xFF8D715B),
                      trackColor: const Color(0xFF111111),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(32, 210, 32, 120),
                  itemCount: ordered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 72),
                  itemBuilder: (BuildContext context, int index) {
                    final PlayNode node = ordered[index];
                    return _JournalEntry(
                      node: node,
                      step: index + 1,
                      onOpen: node.done
                          ? () => showClassicPlayStorySheet(
                              context,
                              node: node,
                              step: index + 1,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JournalEntry extends StatelessWidget {
  const _JournalEntry({
    required this.node,
    required this.step,
    required this.onOpen,
  });

  final PlayNode node;
  final int step;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (!node.done) {
      return const Opacity(
        opacity: 0.18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '尚未抵达',
              style: TextStyle(color: CupertinoColors.white, fontSize: 14),
            ),
            SizedBox(height: 22),
            Text(
              '城市的下一段故事还在前方。',
              style: TextStyle(
                color: CupertinoColors.white,
                fontSize: 20,
                height: 1.7,
              ),
            ),
          ],
        ),
      );
    }
    final String body = (node.description ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          step == 1 ? '此刻' : '第 $step 站',
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          body.isEmpty ? node.name : body,
          style: const TextStyle(
            color: Color(0xFFF2F2F2),
            fontSize: 21,
            height: 1.72,
          ),
        ),
        const SizedBox(height: 24),
        CupertinoButton(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          onPressed: onOpen,
          child: const Text(
            '展开',
            style: TextStyle(color: Color(0xFFB5B5B5), fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class ClassicPlayStorySurface extends StatelessWidget {
  const ClassicPlayStorySurface({
    super.key,
    required this.node,
    required this.step,
    this.scrollController,
    required this.onClose,
  });

  final PlayNode node;
  final int step;
  final ScrollController? scrollController;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('classic-play-story'),
    color: CupertinoColors.black,
    child: SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 16,
              16,
              10,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '第 $step 站',
                        style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  key: const Key('classic-play-story-close'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(99),
                  onPressed: onClose,
                  child: const Icon(
                    CupertinoIcons.xmark,
                    size: 18,
                    color: CupertinoColors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF111111)),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: <Widget>[
                SizedBox(
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if ((node.imgUrl ?? '').trim().isNotEmpty)
                        Image.network(
                          node.imgUrl!.split(',').first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const DecoratedBox(
                            decoration: BoxDecoration(color: Color(0xFF101010)),
                          ),
                        )
                      else
                        const CustomPaint(painter: _StoryBackdropPainter()),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x88000000),
                              CupertinoColors.black,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                  child: Text(
                    (node.description ?? '').trim().isEmpty
                        ? node.name
                        : node.description!.trim(),
                    style: const TextStyle(
                      color: Color(0xFFB5B5B5),
                      fontSize: 17,
                      height: 1.75,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showClassicPlayFinishSheet(
  BuildContext context, {
  required PlayNodesResult result,
  required VoidCallback onJournal,
  required VoidCallback onLeaderboard,
  required VoidCallback onShare,
  required VoidCallback onSave,
  int? activityId,
  int? topicId,
  List<PlayNode> nodes = const <PlayNode>[],
}) => showCyNativeSheet<void>(
  context,
  detents: CyNativeSheetDetents.large,
  builder: (BuildContext sheetContext) => ClassicPlayFinishSurface(
    result: result,
    onContinue: () => Navigator.of(sheetContext).pop(),
    onJournal: onJournal,
    onLeaderboard: onLeaderboard,
    onShare: onShare,
    onSave: onSave,
    activityId: activityId,
    topicId: topicId,
    nodes: nodes,
  ),
);

class ClassicPlayFinishSurface extends StatelessWidget {
  const ClassicPlayFinishSurface({
    super.key,
    required this.result,
    this.scrollController,
    required this.onContinue,
    required this.onJournal,
    required this.onLeaderboard,
    required this.onShare,
    required this.onSave,
    this.activityId,
    this.topicId,
    this.nodes = const <PlayNode>[],
  });

  final PlayNodesResult result;
  final ScrollController? scrollController;
  final VoidCallback onContinue;
  final VoidCallback onJournal;
  final VoidCallback onLeaderboard;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final int? activityId;
  final int? topicId;
  final List<PlayNode> nodes;

  @override
  Widget build(BuildContext context) {
    final String title = result.chapters.isEmpty
        ? '这一趟'
        : result.chapters.first.title ?? result.chapters.first.meta ?? '这一趟';
    final bool freeExplore = result.mode == 2;
    final ({int score, int count}) puzzle = result.finishPuzzle;
    final int? personalBest = result.puzzlePersonalBest;
    final int? xp = result.finishXp;
    final List<PlayNode> stamped = result.nodes
        .where((PlayNode node) => node.done)
        .toList(growable: false);
    return Material(
      key: const Key('classic-play-finish'),
      color: const Color(0xFFF7F7F8),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: <Widget>[
            Text(
              // 真源 index.wxml:1269:同一张结算半屏,mode2 的眉标是「我的探索顺序」。
              freeExplore ? '我的探索顺序' : '主题通关',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6A7282),
                fontSize: 14,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6E4FF),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '已通关',
                  style: TextStyle(
                    color: Color(0xFF5E5CE6),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: const SizedBox(
                height: 214,
                child: CustomPaint(painter: _FinishMapPainter()),
              ),
            ),
            const SizedBox(height: 22),
            // 真源 index.js:5071-5090 + index.wxml:1299-1315:mode1 报
            // 「点亮坐标/本次解谜分/探索值」三个真读数;mode2(探店日)这些
            // 经典定向读数会撒谎,只报「商户核销 + 本期集章」。
            if (freeExplore)
              Row(
                children: <Widget>[
                  _FinishStat(
                    value: '${result.doneCount}/${result.total}',
                    label: '商户核销',
                  ),
                  _FinishStat(value: '${stamped.length}', label: '本期集章'),
                  const Expanded(child: SizedBox.shrink()),
                ],
              )
            else
              Row(
                children: <Widget>[
                  _FinishStat(value: '${result.doneCount}', label: '点亮坐标'),
                  _FinishStat(
                    value: '${puzzle.score}',
                    label: puzzle.count > 0
                        ? '本次解谜分 · ${puzzle.count}题'
                        : '本次解谜分',
                    sub: (personalBest ?? 0) > 0 ? '个人最佳 $personalBest' : null,
                  ),
                  _FinishStat(
                    // 缺服务端 xp 投影就是「未知」(—),不许用站数估一个数。
                    value: xp == null ? '—' : '$xp',
                    label: '探索值',
                  ),
                ],
              ),
            if (freeExplore && stamped.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final PlayNode node in stamped)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              CupertinoIcons.checkmark_seal_fill,
                              size: 15,
                              color: Color(0xFF5E5CE6),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                node.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF111111),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            CupertinoButton(
              key: const Key('classic-play-finish-journal'),
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              color: const Color(0xFFF0F1F4),
              borderRadius: BorderRadius.circular(14),
              onPressed: onJournal,
              child: Semantics(
                // 小程序这条入口的 aria-label(pages/play/index.wxml:1348):可见标题
                // 已经是「回看旅程手记」,读屏补全成同一句完整动作。
                button: true,
                label: '回看本次旅程手记',
                child: const Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '回看旅程手记',
                            style: TextStyle(
                              color: Color(0xFF111111),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            '按到达顺序重读已经解锁的章节',
                            style: TextStyle(
                              color: Color(0xFF6A7282),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.arrow_right,
                      color: Color(0xFF111111),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            // wxml 顺序:回看手记 → 附近下一程推荐 → 「继续」CTA。
            // 卡片自带 margin-top(space-4),无卡时零高度,不改原有间距。
            FinishRouteRecommendationSlot(
              activityId: activityId,
              topicId: topicId,
              nodes: nodes,
            ),
            const SizedBox(height: 20),
            CupertinoButton(
              key: const Key('classic-play-finish-continue'),
              onPressed: onContinue,
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(99),
              minimumSize: const Size(double.infinity, 54),
              child: const Text(
                '继续',
                style: TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _FinishLink(label: '同行者榜', onPressed: onLeaderboard),
                const Text(' · ', style: TextStyle(color: Color(0xFF6A7282))),
                _FinishLink(label: '分享足迹', onPressed: onShare),
                const Text(' · ', style: TextStyle(color: Color(0xFF6A7282))),
                _FinishLink(label: '保存足迹卡', onPressed: onSave),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishStat extends StatelessWidget {
  const _FinishStat({required this.value, required this.label, this.sub});

  final String value;
  final String label;

  /// 第三行小字(真源 `fst__sub`,如「个人最佳 92」)——没有就不占行。
  final String? sub;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 31,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF6A7282), fontSize: 12),
        ),
        if (sub != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            sub!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6A7282), fontSize: 11),
          ),
        ],
      ],
    ),
  );
}

class _FinishLink extends StatelessWidget {
  const _FinishLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: 2),
    onPressed: onPressed,
    child: Text(
      label,
      style: const TextStyle(color: Color(0xFF6A7282), fontSize: 13),
    ),
  );
}

class _StoryBackdropPainter extends CustomPainter {
  const _StoryBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF121516),
    );
    final Paint line = Paint()
      ..color = const Color(0xFF262A2C)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(-20, size.height * .3)
        ..cubicTo(
          size.width * .3,
          0,
          size.width * .5,
          size.height,
          size.width + 20,
          size.height * .4,
        ),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FinishMapPainter extends CustomPainter {
  const _FinishMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE6E9DE),
    );
    final Paint street = Paint()
      ..color = CupertinoColors.white
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;
    for (double y = 24; y < size.height; y += 48) {
      canvas.drawLine(
        Offset.zero.translate(0, y),
        Offset(size.width, y + 12),
        street,
      );
    }
    final Path route = Path()
      ..moveTo(12, size.height - 34)
      ..cubicTo(
        size.width * .32,
        size.height * .4,
        size.width * .62,
        size.height * .8,
        size.width - 10,
        28,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF111111)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke,
    );
    for (final double t in <double>[.18, .42, .67, .9]) {
      final Offset p = _pointOn(route, t);
      canvas.drawCircle(p, 13, Paint()..color = const Color(0xFF111111));
      final TextPainter check = TextPainter(
        text: const TextSpan(
          text: '✓',
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      check.paint(canvas, p - Offset(check.width / 2, check.height / 2));
    }
  }

  Offset _pointOn(Path path, double t) {
    final metric = path.computeMetrics().first;
    return metric.getTangentForOffset(metric.length * t)!.position;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
