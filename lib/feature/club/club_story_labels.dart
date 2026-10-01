import 'package:flutter/widgets.dart';

import '../../data/models/club_topic_ops.dart';
import '../../data/models/topic.dart';
import '../../l10n/strings.dart';

/// Localize presentation metadata using the original structured public projection.
/// The existing builder still owns sequencing, walking estimates and answer access.
List<TopicStoryChapter> localizedClubStoryChapters(
  BuildContext context,
  List<TopicChapter> source,
) {
  final chapters = buildTopicStoryChapters(source);
  final strings = stringsOf(context);
  if (strings.localeName.startsWith('zh')) return chapters;
  return [
    for (var index = 0; index < chapters.length; index++)
      _chapter(context, chapters[index], source[index], index),
  ];
}

TopicStoryChapter _chapter(BuildContext context, TopicStoryChapter chapter,
    TopicChapter source, int index) {
  final strings = stringsOf(context);
  final rawTitle = source.title.trim();
  final ordinal = strings.clubStoryChapterNumber(index + 1);
  final duration = topicDurationText(source.totalTime);
  return TopicStoryChapter(
    id: chapter.id,
    title: RegExp(r'^第.{1,3}章').hasMatch(rawTitle)
        ? rawTitle
        : rawTitle.isEmpty ? ordinal : '$ordinal · $rawTitle',
    meta: chapter.stops.isEmpty
        ? strings.clubStoryAwaitingMerchants
        : [duration, strings.clubStoryStopCount(chapter.stops.length)]
            .where((value) => value.isNotEmpty).join(' · '),
    story: chapter.story,
    stops: [for (final stop in chapter.stops) TopicStoryStop(
      id: stop.id, seq: stop.seq, time: stop.time, name: stop.name,
      address: stop.address, cover: stop.cover,
      // walkText is generated exclusively by topicWalkText, never server copy.
      walkText: stop.walkText.isEmpty ? '' : strings.clubStoryWalk(
        stop.walkText.substring(0, stop.walkText.length - ' 步行'.length)),
    )],
    plays: [for (final play in chapter.plays) _play(context, play, source, chapter)],
  );
}

TopicStoryPlay _play(BuildContext context, TopicStoryPlay play,
    TopicChapter source, TopicStoryChapter chapter) {
  final strings = stringsOf(context);
  final node = source.nodes.firstWhere((node) => node.id == play.nodeId);
  final template = node.template!;
  final stop = chapter.stops.firstWhere((stop) => stop.id == '${node.id}');
  final label = switch (template.validationMethod) {
    0 => strings.clubStoryValidationNone,
    1 => strings.clubStoryValidationText,
    2 => strings.clubStoryValidationPhoto,
    3 => strings.clubStoryValidationChoice,
    4 => strings.clubStoryValidationScan,
    5 => strings.clubStoryValidationGps,
    6 => strings.clubStoryValidationPreference,
    7 => strings.clubStoryValidationSensor,
    _ => (template.validationMethodStr ?? '').trim(),
  };
  final resolved = label.isEmpty ? strings.clubStoryPlay : label;
  return TopicStoryPlay(
    nodeId: play.nodeId, templateId: play.templateId, title: play.title,
    badge: play.hasAnswer ? resolved : strings.clubStoryNoAnswerBadge(resolved),
    cover: play.cover, hasAnswer: play.hasAnswer,
    meta: [
      strings.clubStoryStopName(stop.seq, node.name.trim()),
      (template.players ?? '').trim(),
      if (template.duration != null) strings.clubStoryMinutes('${template.duration}'),
      if ((template.difficulty ?? '').trim().isNotEmpty)
        strings.clubStoryDifficulty(template.difficulty!.trim()),
    ].where((value) => value.isNotEmpty).join(' · '),
  );
}
