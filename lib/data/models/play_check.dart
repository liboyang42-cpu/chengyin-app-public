/// R14 旅程检定(《预制人生》)的视图模型。
///
/// ★ 同源:小程序 `utils/playkit-view.js` 的 `pickJourneyCheck` /
/// `checkReceiptView` 与 `pages/play/components/playkit-journey-check/index.js`
/// 的 `canReroll` / `TIER_LABEL`。这一层只搬服务端给的东西:
/// 题面(encounter.data.check)不含任何成败文案,successText/failText/effects
/// 一律不下发 —— 文案要等 /settle 的回执,不在这层猜。
library;

int? _numOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

int _num(Object? raw, [int fallback = 0]) => _numOrNull(raw) ?? fallback;

bool _bool(Object? raw) => raw == true || raw == 'true';

/// 题面条件修正:`{label, value, held}`。held = 这条在本局状态下达不达成。
class JourneyCheckMod {
  const JourneyCheckMod({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;

  /// 修正值,可负;0 也要原样展示(真源 `{{item.value > 0 ? '+' : ''}}{{item.value}}`)。
  final int value;

  /// 题面里是 held、回执里是 applied,UI 文案同为「生效 / 未生效」,收成一个字段。
  final bool active;

  static List<JourneyCheckMod> listFrom(Object? raw) {
    if (raw is! List) return const <JourneyCheckMod>[];
    return raw.whereType<Map<String, dynamic>>().map((Map<String, dynamic> m) {
      return JourneyCheckMod(
        label: (m['label'] ?? '').toString(),
        value: _num(m['value']),
        active: _bool(m['held']) || _bool(m['applied']),
      );
    }).toList();
  }
}

/// encounter.data.check 题面(pickJourneyCheck 的产物)。
class JourneyCheckProblem {
  const JourneyCheckProblem({
    required this.checkId,
    required this.skill,
    required this.tier,
    required this.mods,
    required this.advantage,
    required this.disadvantage,
  });

  final String checkId;
  final String skill;
  final String tier;
  final List<JourneyCheckMod> mods;
  final bool advantage;
  final bool disadvantage;

  /// 只认 encounter.allowedActions 里那条 `'check'` 入口 —— 拿不到 checkId
  /// 就算这个节点没有检定(真源口径,不弹任何东西)。
  static JourneyCheckProblem? fromEncounter(Map<String, dynamic>? encounter) {
    final List<Object?> actions = encounter?['allowedActions'] is List
        ? encounter!['allowedActions'] as List
        : const <Object?>[];
    final Object? raw = encounter?['check'];
    final Map<String, dynamic>? check = raw is Map
        ? raw.cast<String, dynamic>()
        : null;
    final String checkId = (check?['checkId'] ?? '').toString().trim();
    if (!actions.contains('check') || checkId.isEmpty) return null;
    return JourneyCheckProblem(
      checkId: checkId,
      skill: (check!['skill'] ?? '').toString(),
      tier: (check['tier'] ?? '').toString(),
      mods: JourneyCheckMod.listFrom(check['mods']),
      advantage: _bool(check['advantage']),
      disadvantage: _bool(check['disadvantage']),
    );
  }
}

/// /api/play/check/{roll,reroll,settle} 的回执(PlayCheckReceipt)。
///
/// ★ 结算前(settled=false)服务端**不给** [text]/[failCostLabel],别猜。
class JourneyCheckReceipt {
  const JourneyCheckReceipt({
    required this.tier,
    required this.dc,
    required this.dice,
    required this.kept,
    required this.total,
    required this.success,
    required this.nat,
    required this.rerolled,
    required this.settled,
    required this.text,
    required this.failCostLabel,
    required this.hp,
    required this.luck,
    required this.exhausted,
    required this.mods,
  });

  final String tier;
  final int dc;
  final List<int> dice;
  final int? kept;
  final int total;
  final bool success;
  final String nat;
  final bool rerolled;
  final bool settled;
  final String text;
  final String failCostLabel;

  /// 生命/幸运读数:回执缺省(null)就不画,不拿 0 冒充「扣光了」。
  final int? hp;
  final int? luck;
  final bool exhausted;
  final List<JourneyCheckMod> mods;

  static JourneyCheckReceipt fromJson(Map<String, dynamic> json) {
    final Object? rawDice = json['dice'];
    return JourneyCheckReceipt(
      tier: (json['tier'] ?? '').toString(),
      dc: _num(json['dc']),
      dice: rawDice is List
          ? rawDice.map((Object? d) => _num(d)).toList()
          : const <int>[],
      kept: _numOrNull(json['kept']),
      total: _num(json['total']),
      success: _bool(json['success']),
      nat: (json['nat'] ?? '').toString(),
      rerolled: _bool(json['rerolled']),
      settled: _bool(json['settled']),
      text: (json['text'] ?? '').toString(),
      failCostLabel: (json['failCostLabel'] ?? '').toString(),
      hp: _numOrNull(json['hp']),
      luck: _numOrNull(json['luck']),
      exhausted: _bool(json['exhausted']),
      mods: JourneyCheckMod.listFrom(json['mods']),
    );
  }
}

/// 难度档码 → 中文。服务端只给 easy/medium/hard(禁止任意 DC 数字);
/// 未知档原样透出,空档兜「标准」(真源 `tierLabel || '标准'`)。
const Map<String, String> kJourneyCheckTierLabels = <String, String>{
  'easy': '简单',
  'medium': '标准',
  'hard': '困难',
};

String journeyCheckTierLabel(String tier) {
  final String label = kJourneyCheckTierLabels[tier.toLowerCase()] ?? tier;
  return label.isEmpty ? '标准' : label;
}

/// 重掷条件:掷过、没结算、没重掷过,且幸运还有剩。回执 luck 缺省时不猜。
bool journeyCheckCanReroll(JourneyCheckReceipt? receipt) {
  if (receipt == null || receipt.settled || receipt.rerolled) return false;
  return (receipt.luck ?? 0) > 0;
}
