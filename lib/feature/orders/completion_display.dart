import 'package:flutter/widgets.dart';

import '../../data/models/explore_completion.dart';
import '../../l10n/strings.dart';

String? completionProgressLabel(BuildContext context, ExploreCompletion completion) =>
    completion.requiredChapterCount > 0
        ? stringsOf(context).ticketCompletionProgress(
            completion.redeemedChapterCount, completion.requiredChapterCount)
        : null;

String? completionAwardsEmptyLabel(BuildContext context, ExploreCompletion completion) =>
    completion.awardsCredited
        ? null
        : completion.completed
            ? stringsOf(context).ticketCompletionPendingAwards
            : stringsOf(context).ticketCompletionVisitAll(completion.requiredChapterCount);

String completionStampLabel(BuildContext context, ExploreStamp stamp) =>
    stamp.hasServerTitle ? stamp.title : stringsOf(context).ticketCompletionChapter(stamp.chapterId);

String completionClubLabel(BuildContext context, ExploreRevisit revisit) =>
    revisit.hasServerClubName ? revisit.clubName : stringsOf(context).ticketCompletionHostClub;

String completionNextName(BuildContext context, ExploreNextEdition next) =>
    next.hasServerName ? next.name : stringsOf(context).ticketCompletionNext;
