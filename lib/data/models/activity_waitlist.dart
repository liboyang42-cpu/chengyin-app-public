enum ActivityWaitlistState {
  none,
  waiting,
  offered,
  claimed,
  converted,
  cancelled,
  expired,
}

enum ActivityWaitlistEligibility {
  noSeries,
  waitlistClosed,
  notMember,
  alreadyRegistered,
  eligible,
  blocked,
}

/// 当前用户在一个活动票种上的服务端候补真状态。
class ActivityWaitlistStatus {
  const ActivityWaitlistStatus({
    required this.activityId,
    required this.ticketId,
    required this.state,
    required this.eligibility,
    required this.joinAllowed,
    this.id,
    this.memberId,
    this.offerToken,
    this.offerExpiresAt,
    this.registrationId,
  });

  final int? id;
  final int activityId;
  final int ticketId;
  final int? memberId;
  final ActivityWaitlistState state;
  final ActivityWaitlistEligibility eligibility;
  final bool joinAllowed;
  final String? offerToken;
  final DateTime? offerExpiresAt;
  final int? registrationId;

  int? get offerId => state == ActivityWaitlistState.offered ? id : null;

  bool get hasActiveOffer =>
      state == ActivityWaitlistState.offered &&
      id != null &&
      offerToken != null &&
      offerExpiresAt != null;

  bool get canJoin =>
      eligibility == ActivityWaitlistEligibility.eligible &&
      joinAllowed &&
      const <ActivityWaitlistState>{
        ActivityWaitlistState.none,
        ActivityWaitlistState.cancelled,
        ActivityWaitlistState.expired,
      }.contains(state);

  bool get canCancel =>
      state == ActivityWaitlistState.waiting ||
      state == ActivityWaitlistState.offered;

  bool get isQueueActive =>
      state == ActivityWaitlistState.waiting ||
      state == ActivityWaitlistState.offered;

  String get paymentText {
    final String? eligibilityText = switch (eligibility) {
      ActivityWaitlistEligibility.noSeries => '本活动未配置候补',
      ActivityWaitlistEligibility.waitlistClosed => '本场候补已关闭',
      ActivityWaitlistEligibility.notMember => '仅俱乐部成员可候补',
      ActivityWaitlistEligibility.alreadyRegistered => '你已有该票种报名',
      ActivityWaitlistEligibility.blocked => '当前无法参与候补',
      ActivityWaitlistEligibility.eligible => null,
    };
    if (eligibilityText != null) return eligibilityText;
    return switch (state) {
      ActivityWaitlistState.waiting => '候补排队中',
      ActivityWaitlistState.claimed => '已生成报名订单',
      ActivityWaitlistState.converted => '报名已确认',
      ActivityWaitlistState.cancelled => '已退出候补',
      ActivityWaitlistState.expired => '候补名额已过期',
      ActivityWaitlistState.none || ActivityWaitlistState.offered => '等待候补名额',
    };
  }

  factory ActivityWaitlistStatus.fromJson(
    Map<String, dynamic> json, {
    required int expectedActivityId,
    required int expectedTicketId,
    required DateTime now,
  }) {
    final int? activityId = _positiveInt(json['activityId']);
    final int? ticketId = _positiveInt(json['ticketId']);
    final ActivityWaitlistState? state = _state(json['state']);
    final ActivityWaitlistEligibility? eligibility = _eligibility(
      json['eligibilityState'],
    );
    final Object? rawJoinAllowed = json['waitlistJoinAllowed'];
    if (activityId != expectedActivityId ||
        ticketId != expectedTicketId ||
        state == null ||
        eligibility == null ||
        rawJoinAllowed is! bool ||
        rawJoinAllowed !=
            (eligibility == ActivityWaitlistEligibility.eligible)) {
      throw const FormatException('候补状态回执不完整');
    }

    final int? id = _optionalPositiveInt(json['id']);
    final int? memberId = _optionalPositiveInt(json['memberId']);
    final int? registrationId = _optionalPositiveInt(json['registrationId']);
    if ((state != ActivityWaitlistState.none && id == null) ||
        (const <ActivityWaitlistState>{
              ActivityWaitlistState.claimed,
              ActivityWaitlistState.converted,
            }.contains(state) &&
            registrationId == null)) {
      throw const FormatException('候补状态回执不完整');
    }

    String? offerToken;
    DateTime? offerExpiresAt;
    ActivityWaitlistState normalizedState = state;
    if (state == ActivityWaitlistState.offered) {
      offerToken = _nonEmptyText(json['offerToken']);
      offerExpiresAt = _dateTime(json['offerExpiresAt']);
      if (offerToken == null || offerExpiresAt == null) {
        throw const FormatException('候补状态回执不完整');
      }
      final Duration remaining = offerExpiresAt.difference(now);
      if (remaining <= Duration.zero ||
          remaining > const Duration(minutes: 121)) {
        normalizedState = ActivityWaitlistState.expired;
        offerToken = null;
        offerExpiresAt = null;
      }
    }

    return ActivityWaitlistStatus(
      id: id,
      activityId: expectedActivityId,
      ticketId: expectedTicketId,
      memberId: memberId,
      state: normalizedState,
      eligibility: eligibility,
      joinAllowed: rawJoinAllowed,
      offerToken: offerToken,
      offerExpiresAt: offerExpiresAt,
      registrationId: registrationId,
    );
  }
}

ActivityWaitlistState? _state(Object? value) => switch (value) {
  'NONE' => ActivityWaitlistState.none,
  'WAITING' => ActivityWaitlistState.waiting,
  'OFFERED' => ActivityWaitlistState.offered,
  'CLAIMED' => ActivityWaitlistState.claimed,
  'CONVERTED' => ActivityWaitlistState.converted,
  'CANCELLED' => ActivityWaitlistState.cancelled,
  'EXPIRED' => ActivityWaitlistState.expired,
  _ => null,
};

ActivityWaitlistEligibility? _eligibility(Object? value) => switch (value) {
  'NO_SERIES' => ActivityWaitlistEligibility.noSeries,
  'WAITLIST_CLOSED' => ActivityWaitlistEligibility.waitlistClosed,
  'NOT_MEMBER' => ActivityWaitlistEligibility.notMember,
  'ALREADY_REGISTERED' => ActivityWaitlistEligibility.alreadyRegistered,
  'ELIGIBLE' => ActivityWaitlistEligibility.eligible,
  'BLOCKED' => ActivityWaitlistEligibility.blocked,
  _ => null,
};

int? _positiveInt(Object? value) {
  if (value is! num || !value.isFinite || value != value.toInt()) return null;
  final int parsed = value.toInt();
  return parsed > 0 ? parsed : null;
}

int? _optionalPositiveInt(Object? value) =>
    value == null ? null : _positiveInt(value);

String? _nonEmptyText(Object? value) {
  if (value is! String) return null;
  final String text = value.trim();
  return text.isEmpty ? null : text;
}

DateTime? _dateTime(Object? value) {
  final String? text = _nonEmptyText(value);
  return text == null ? null : DateTime.tryParse(text.replaceAll('/', '-'));
}
