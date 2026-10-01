import 'package:flutter/widgets.dart';

import '../../data/models/team_map.dart';
import '../../data/api/team_map_api.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/strings.dart';

String _text(Object? value) => value?.toString().trim() ?? '';
int _number(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String teamNameDisplay(BuildContext context, Map<String, dynamic> source) {
  final name = _text(source['title']);
  return name.isEmpty ? stringsOf(context).teamMapPlayerTeamFallback : name;
}

String teamExpiryDisplay(BuildContext context, Object? value, {DateTime? now}) {
  final minutes = teamExpireMinutes(value, now ?? DateTime.now());
  if (minutes == null) return '';
  return minutes < 60 ? stringsOf(context).teamMapMinuteCount(minutes)
      : stringsOf(context).teamMapHourCount(minutes ~/ 60);
}

/// Decorate only app-generated copy; the model remains the state/action authority.
TeamNearbyCard localizedTeamCard(BuildContext context, Map<String, dynamic> source) {
  final card = decorateTeam(source);
  final strings = stringsOf(context);
  final name = teamNameDisplay(context, source);
  final address = _text(source['addressName']);
  final leader = _text(source['leaderName']);
  final left = card.maxMembers - card.joinedCount;
  final expiry = teamExpiryDisplay(context, source['applyExpireTime']);
  final foot = switch (card.card.mode) {
    'pending' => expiry.isEmpty ? strings.teamMapPendingFoot : strings.teamMapPendingExpiry(expiry),
    'apply' => strings.teamMapApplyFoot,
    'buy' => strings.teamMapBuyFoot,
    _ => card.card.foot,
  };
  return TeamNearbyCard(
    teamId: card.teamId, activityId: card.activityId, topicId: card.topicId,
    name: name,
    heading: _text(source['activityName']).isEmpty ? name : _text(source['activityName']),
    sub: [
      _number(source['productType']) == 2 ? strings.teamMapFreeExplore : strings.teamMapUrbanExplore,
      if (address.isNotEmpty) _text(source['coordSource']) == 'GATHER'
          ? strings.teamMapGather(address) : strings.teamMapNearby(address),
      if (source['distance'] != null) strings.teamMapDistance(teamFmtKm(source['distance'])),
    ].join(' · '),
    membersLine: [strings.teamMapLeader(leader.isEmpty ? strings.teamMapPlayer : leader),
      strings.teamMapJoinedCount(card.joinedCount),
      left > 0 ? strings.teamMapRemainingCount(left) : strings.teamDetailFull].join(' · '),
    faces: card.faces,
    plate: card.viewerStatus == 'LEADER' ? strings.teamMapApplicantsPlate(_number(source['pendingCount']))
        : card.viewerStatus == 'PENDING' ? strings.teamMapPendingPlate(name)
        : '$name · ${card.joinedCount}/${card.maxMembers}',
    joinedCount: card.joinedCount, maxMembers: card.maxMembers,
    viewerStatus: card.viewerStatus, viewerHasTicket: card.viewerHasTicket,
    latitude: card.latitude, longitude: card.longitude,
    card: TeamCardState(mode: card.card.mode, notice: card.card.notice,
        primary: card.card.primary, secondary: card.card.secondary, foot: foot),
  );
}

MyTeamRow localizedMyTeamRow(BuildContext context, MyTeamRow row) {
  final source = row.displaySource;
  if (source.isEmpty) return row; // No provenance: never translate by string equality.
  final strings = stringsOf(context);
  final leader = _text(source['leaderName']);
  final expiry = teamExpiryDisplay(context, source['applyExpireTime']);
  final sub = switch (row.action) {
    'enter' => strings.teamMapMemberRatio(_number(source['joinedCount']), _number(source['maxMembers'])),
    'withdraw' => [strings.teamMapLeader(leader.isEmpty ? strings.teamMapPlayer : leader),
      if (expiry.isNotEmpty) strings.teamMapExpiry(expiry)].join(' · '),
    'nearby' => strings.teamDetailRejectedNotice,
    _ => row.sub,
  };
  return MyTeamRow(key: row.key, teamId: row.teamId, name: teamNameDisplay(context, source),
    sub: sub, badge: switch (row.action) {
      'enter' => strings.teamDetailJoined,
      'withdraw' => strings.teamDetailApplying,
      'nearby' => strings.teamDetailLeaderNotApproved,
      _ => row.badge,
    }, tone: row.tone, actionText: switch (row.action) {
      'enter' => strings.teamDetailEnter,
      'withdraw' => strings.teamDetailWithdrawApplication,
      'nearby' => strings.teamMapLookNearby,
      _ => row.actionText,
    }, actionKind: row.actionKind, action: row.action, displaySource: source);
}

TeamErrorOutcome localizedTeamError(BuildContext context, TeamErrorOutcome outcome) {
  if (!outcome.hasDisplayProvenance) return outcome;
  final s = stringsOf(context);
  final key = '${outcome.operation}:${outcome.errorCode}';
  final title = switch (key) {
    'apply:TICKET_REQUIRED' => s.teamMapBuyFirst,
    'apply:APPLY_REJECTED' => s.teamDetailRejectedNotice,
    'apply:APPLY_PENDING' => s.teamMapAlreadyApplied,
    'apply:ALREADY_JOINED' => s.teamMapAlreadyJoined,
    'apply:TEAM_FULL' || 'apply:ACTIVITY_STARTED' || 'apply:TEAM_UNDER_REVIEW' => s.teamMapCannotApply,
    'apply:TEAM_NOT_PUBLIC' => s.teamMapPrivate,
    'apply:APPLY_BLOCKED' => s.teamMapBlocked,
    'withdraw:APPLY_NOT_PENDING' || 'handle:APPLY_NOT_PENDING' => s.teamMapApplicationExpired,
    'handle:TICKET_REQUIRED' => s.teamMapApplicantRefunded,
    'handle:TEAM_FULL' => s.teamMapFullError,
    'handle:APPLY_BLOCKED' => s.teamMapCannotApprove,
    _ => switch (outcome.operation) {
      'apply' => s.teamMapApplyFailed,
      'withdraw' => s.teamMapWithdrawFailed,
      'handle' => s.teamMapHandleFailed,
      'my' => s.teamMapMyLoadFailed,
      'applications' => s.teamMapApplicantsLoadFailed,
      _ => s.teamMapGenericFailed,
    },
  };
  final why = outcome.whyIsServerMessage ? outcome.why :
      teamLocalFailureText(outcome.localFailureKey, s) ?? switch (key) {
    'apply:TEAM_FULL' || 'apply:ACTIVITY_STARTED' || 'apply:TEAM_UNDER_REVIEW' => s.teamMapGoneReason,
    'apply:TEAM_NOT_PUBLIC' => s.teamMapPrivateReason,
    _ => s.teamMapTryLater,
  };
  return TeamErrorOutcome(title: title, why: why, patch: outcome.patch,
    dropTeam: outcome.dropTeam, dropApplicant: outcome.dropApplicant, refresh: outcome.refresh,
    primary: outcome.primaryAction == 'buy' ? s.teamMapBuy : outcome.primary,
    secondary: outcome.primaryAction == 'buy' ? s.teamMapNotBuy : outcome.secondary,
    primaryAction: outcome.primaryAction, operation: outcome.operation,
    errorCode: outcome.errorCode, hasDisplayProvenance: true,
    whyIsServerMessage: outcome.whyIsServerMessage, localFailureKey: outcome.localFailureKey);
}

String? teamLocalFailureText(String key, AppLocalizations strings) => switch (key) {
  'nearby' => strings.teamApiNearby,
  'apply' => strings.teamApiApply,
  'withdraw' => strings.teamApiWithdraw,
  'applications' => strings.teamApiApplications,
  'handle' => strings.teamApiHandle,
  'mine' => strings.teamApiMine,
  'joinMode' => strings.teamApiJoinMode,
  'create' => strings.teamApiCreate,
  'network' => strings.teamApiNetwork,
  _ => null,
};

String teamApiFailureText(TeamMapApiException error, AppLocalizations strings) =>
    teamLocalFailureText(error.localReason?.name ?? '', strings) ?? error.message;
