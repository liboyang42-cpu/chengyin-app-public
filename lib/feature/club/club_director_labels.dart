import 'package:flutter/widgets.dart';

import '../../data/models/club_director.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/strings.dart';

/// Presentation only. Read the raw projection to distinguish generated fallbacks
/// from authored text, including authored text equal to a Chinese fallback label.
class ClubDirectorLabels {
  ClubDirectorLabels(BuildContext context) : strings = stringsOf(context);
  final AppLocalizations strings;

  String _first(List<String> values, String fallback) =>
      values.where((value) => value.isNotEmpty).firstOrNull ?? fallback;

  String readiness(ClubDirectorReadiness value) =>
      value.readyStations == null || value.requiredStations == null
          ? strings.clubDirectorReadinessPending
          : strings.clubDirectorReadinessCount(value.readyStations!, value.requiredStations!);
  String sessionStatus(String value) => switch (value.toUpperCase()) {
    'NOT_PREPARED' => strings.clubDirectorSessionNotPrepared,
    'DRAFT' => strings.clubDirectorSessionDraft,
    'PREPARING' => strings.clubDirectorSessionPreparing,
    'READY' => strings.clubDirectorSessionReady,
    'RUNNING' => strings.clubDirectorSessionRunning,
    'FINISHED' => strings.clubDirectorSessionFinished,
    'CANCELLED' => strings.clubDirectorSessionCancelled,
    _ => strings.clubDirectorSessionPending,
  };

  String stationName(ClubDirectorStation value) => _first(
      [value.name, value.stationName, value.nodeName], strings.clubDirectorUnnamedNode);
  String teamName(ClubDirectorTeam value) =>
      _first([value.name, value.teamName], strings.clubDirectorUnnamedTeam);
  String teamProgress(ClubDirectorTeam value) =>
      value.completedNodes == null || value.totalNodes == null
          ? strings.clubDirectorProgressPending
          : strings.clubDirectorNodeProgress(value.completedNodes!, value.totalNodes!);
  String teamStuck(ClubDirectorTeam value) =>
      value.currentStuckNode?.nodeName ?? strings.clubDirectorPending;
  String teamHint(ClubDirectorTeam value) => switch (value.hintLevel) {
    1 => strings.clubDirectorHintFirst,
    2 => strings.clubDirectorHintSecond,
    _ => strings.clubDirectorPending,
  };
  String teamEvent(ClubDirectorTeam value) {
    final event = value.recentEvent;
    if (event == null || event.text.isEmpty) return strings.clubDirectorPending;
    final action = switch (event.action) {
      'CONFIRM_ROLE' => strings.clubDirectorEventConfirmRole,
      'PLAYER_CHOICE' => strings.clubDirectorEventChoice,
      'PLAYER_SUBMIT' => strings.clubDirectorEventSubmit,
      'PLAYER_HINT' => strings.clubDirectorEventHint,
      'PLAYER_REVEAL' => strings.clubDirectorEventReveal,
      _ => '',
    };
    final outcome = event.outcome == 'APPLIED'
        ? strings.clubDirectorEventApplied : strings.clubDirectorEventFailed;
    return [action, outcome, event.occurredAt]
        .where((value) => value.isNotEmpty).join(' · ');
  }

  String memberName(ClubDirectorRole value) => _first(
    [value.memberName, value.name], value.memberId == null
        ? strings.clubDirectorMemberSyncPending
        : strings.clubDirectorMemberNumber(value.memberId!),
  );
  String roleName(ClubDirectorRole value) => _first(
    [value.roleName, value.roleLabel, value.roleCode], strings.clubDirectorRoleUnassigned);
  String roleConfirmation(ClubDirectorRole value) {
    if (value.roleCode.isEmpty) return strings.clubDirectorUnassigned;
    return switch (value.confirmationStatus) {
      'CONFIRMED' => strings.clubDirectorConfirmed,
      'PENDING' || 'ASSIGNED' => strings.clubDirectorPending,
      'REJECTED' => strings.clubDirectorNotAccepted,
      _ => strings.clubDirectorConfirmationSyncPending,
    };
  }

  String broadcastContent(ClubDirectorBroadcast value) =>
      value.content.isEmpty ? strings.clubDirectorBroadcastContentPending : value.content;
  String broadcastTarget(ClubDirectorBroadcast value) => _first(
      [value.targetName, value.roleName], scope(_first([value.targetType, value.scope], '')));
  String scope(String value) => switch (value) {
    'ALL' => strings.clubDirectorScopeAll,
    'TEAM' => strings.clubDirectorScopeTeam,
    'ROLE' => strings.clubDirectorScopeRole,
    _ => strings.clubDirectorTargetPending,
  };
  String broadcastReceipt(ClubDirectorBroadcast value) =>
      switch (_first([value.receiptStatus, value.status], '').toUpperCase()) {
        'CONFIRMED' || 'APPLIED' || 'SUCCESS' => strings.clubDirectorDeliveryConfirmed,
        'REJECTED' || 'FAILED' => strings.clubDirectorDeliveryFailed,
        'PENDING' => strings.clubDirectorReceiptPending,
        'SENDING' => strings.clubDirectorSending,
        'SENT' => strings.clubDirectorDelivered,
        'PARTIAL' => strings.clubDirectorPartlyDelivered,
        _ => strings.clubDirectorReceiptSyncPending,
      };

  /// Keep the actual target untouched: recipient counts use its original label.
  String targetLabel(ClubDirectorProjection projection, String scope,
      ClubDirectorBroadcastTarget target) {
    if (scope == 'ALL') return strings.clubDirectorAllPresent;
    if (scope == 'TEAM') {
      final team = projection.teams.where((team) => team.teamId == target.id).firstOrNull;
      if (team != null) return teamName(team);
    }
    return target.label;
  }

  String incidentLabel(ClubDirectorIncident value) => switch (value.kind) {
    ClubDirectorIncidentKind.paused => strings.clubDirectorIncidentPaused,
    ClubDirectorIncidentKind.backlog => strings.clubDirectorIncidentBacklog,
    ClubDirectorIncidentKind.pendingSubmit => strings.clubDirectorIncidentPending,
    ClubDirectorIncidentKind.rejected => strings.clubDirectorIncidentRejected,
  };
  String incidentMode(String value) => switch (value) {
    'resume' => strings.clubDirectorResumeStop,
    'pause' => strings.clubDirectorPauseTitle,
    'reject' => strings.clubDirectorRejectTitle,
    _ => value,
  };
  ({String text, String sub}) incidentDetails(
      ClubDirectorProjection projection, ClubDirectorIncident value) {
    if (value.kind == ClubDirectorIncidentKind.paused || value.kind == ClubDirectorIncidentKind.backlog) {
      final station = projection.stations.where((station) => station.nodeId == value.nodeId).firstOrNull;
      if (station == null) return (text: value.text, sub: value.sub);
      final name = station.nodeName.isEmpty ? strings.clubDirectorUnnamedStop : station.nodeName;
      if (value.kind == ClubDirectorIncidentKind.backlog) {
        return (text: '$name · ${strings.clubDirectorVerificationBacklog(station.pendingVerificationCount)}', sub: '');
      }
      final reason = _first([station.pauseReason, station.pauseReasonCode], strings.clubDirectorMissingReason);
      return (
        text: '$name · $reason${station.resumeEta.isEmpty ? '' : strings.clubDirectorResumeEta(station.resumeEta)}',
        sub: station.fallbackPlanCode.isEmpty ? strings.clubDirectorNoFallbackPlan
            : strings.clubDirectorFallbackPlan(station.fallbackPlanCode),
      );
    }
    final submission = projection.submissions.where((submission) => submission.submissionId == value.submissionId).firstOrNull;
    if (submission == null) return (text: value.text, sub: value.sub);
    final name = submission.nodeName.isEmpty ? strings.clubDirectorUnnamedStop : submission.nodeName;
    final team = submission.teamId == null ? '' : '${strings.clubDirectorTeamNumber(submission.teamId!)} · ';
    return (
      text: '$team$name ${value.kind == ClubDirectorIncidentKind.rejected ? strings.clubDirectorRejectedResubmit : strings.clubDirectorSubmissionPending}',
      sub: value.sub,
    );
  }
}
