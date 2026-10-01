import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();
  final cases = <(String Function(int), String, String)>[
    (en.roamLiveTripsCount, 'trip', 'trips'),
    (en.roamLiveStampsCount, 'stamp', 'stamps'),
    (en.roamLiveRunnerCount, 'person walking nearby', 'people walking nearby'),
    (en.roamLiveRunnersArea, 'person in this area', 'people in this area'),
    (en.roamLiveHangoutMembers, 'person in the group', 'people in the group'),
    (en.mapLandingNodeCount, 'nearby node', 'nearby nodes'),
    (en.objectCardsPile, 'object.', 'objects.'),
    (en.officialOperatorReachCount, 'person', 'people'),
    (en.officialPlayerParticipants, 'participant', 'participants'),
    (en.officialPlayerDays, 'day', 'days'),
    (en.officialPlayerHours, 'hour', 'hours'),
    (en.officialPlayerCountdownDays, 'day', 'days'),
    (en.officialPlayerCountdownHours, 'hour', 'hours'),
    (en.officialPlayerCountdownMinutes, 'minute', 'minutes'),
  ];
  for (final entry in cases) {
    test('counter ${entry.$2} handles zero, one and two', () {
      for (final n in [0, 1, 2]) {
        expect(entry.$1(n), contains('$n ${n == 1 ? entry.$2 : entry.$3}'));
      }
    });
  }
  test('club cancellation counts preserve the reason at zero, one and two', () {
    for (final count in [0, 1, 2]) {
      expect(en.clubTopicFailedSessions(count, '原始原因'), '$count ${count == 1 ? 'session' : 'sessions'} could not be cancelled: 原始原因');
    }
  });
  test('independent counters do not reuse another counter’s plural branch', () {
    for (final first in [0, 1, 2]) {
      for (final second in [0, 1, 2]) {
        final post = en.profilePostCounts(first, second);
        expect(post, '$first ${first == 1 ? 'like' : 'likes'} · $second ${second == 1 ? 'comment' : 'comments'}');
        final progress = en.roamLiveProgress(17, first, second);
        expect(progress, '17 m · $first new ${first == 1 ? 'tile' : 'tiles'} · $second ${second == 1 ? 'visit' : 'visits'}');
      }
      expect(en.roamLiveRunnerStats('03:20', 42, first),
        '03:20 · 42% explored · $first ${first == 1 ? 'shop' : 'shops'} revealed');
    }
  });
  test('fog, destinations, organizer and badges retain intended meaning', () {
    for (final text in [en.roamLiveLocationPurpose, en.roamLiveRuleExploreBody, en.roamLiveFreeRoamBody]) {
      expect(text.toLowerCase(), contains('clear the fog'));
      expect(text.toLowerCase(), isNot(contains('reveal fog')));
    }
    expect(en.registrationOrdersFreeTicketHint, contains('Tickets'));
    expect(en.registrationOrdersPaidTicketHint, contains('Tickets'));
    expect(en.profileBecomeLeader, 'Become a club organizer');
    expect(en.profileBadges.toLowerCase(), contains('badge'));
    expect(en.profileBadgesDetail.toLowerCase(), isNot(contains('medal')));
    expect(en.registrationOrdersMinutes('1'), '1 min');
    expect(en.registrationOrdersPlayerCount('1–4'), 'Players: 1–4');
  });
}
