class MarketingConsent {
  const MarketingConsent({
    required this.merchantRowId,
    required this.merchantOwnerMemberId,
    required this.merchantName,
    required this.inAppOptedIn,
    required this.couponOptedIn,
  });

  final int merchantRowId;
  final int merchantOwnerMemberId;
  final String merchantName;
  final bool inAppOptedIn;
  final bool couponOptedIn;

  factory MarketingConsent.fromJson(Map<String, dynamic> json) {
    final int? merchantRowId = _positiveId(json['merchantRowId']);
    final int? merchantOwnerMemberId = _positiveId(
      json['merchantOwnerMemberId'],
    );
    if (merchantRowId == null || merchantOwnerMemberId == null) {
      throw const FormatException('营销同意记录缺少商家身份');
    }
    final String name = '${json['merchantName'] ?? ''}'.trim();
    return MarketingConsent(
      merchantRowId: merchantRowId,
      merchantOwnerMemberId: merchantOwnerMemberId,
      merchantName: name.isEmpty ? '商家' : name,
      inAppOptedIn: json['inAppOptedIn'] == true,
      couponOptedIn: json['couponOptedIn'] == true,
    );
  }

  bool valueFor(String channel) => switch (channel) {
    'IN_APP' => inAppOptedIn,
    'COUPON' => couponOptedIn,
    _ => false,
  };

  static int? _positiveId(dynamic value) {
    final int? id = value is num ? value.toInt() : int.tryParse('$value');
    return id != null && id > 0 ? id : null;
  }
}
