/// 扫码核销的结果。**三态,不是「成功 / 失败」两态。**
///
/// ★ 这是本项目里契约最微妙的一处,后端注释把理由写死了
///   (ApiRegistrationController:1010-1018):
///
///   交集 ≥2 时,后端返回的是 **`error("请选择要核销的章节", data)`** ——
///   `code` 是失败码,但 `data` 里带着 `needChapterChoice: true` + 候选列表。
///   **前端判据必须是 `data.needChapterChoice`,不是 `code`。**
///
///   为什么定成这样:小程序发版不原子、老客户端会长期滞留。一旦这里返 success,
///   任何只判 `code == 200` 的客户端都会弹「验票成功」**放人走**,
///   而 entitlement 从没消费 ⇒ **同一张票可以反复核销**。
///   判据落在载荷上,新老两代客户端才能共存。
///
/// ⚠️ 所以 App 侧**不能**把它当普通失败抛异常 —— 那样候选列表连同 data
///   一起被丢掉,商家看到一句红字「请选择要核销的章节」却**没有可选的东西**,
///   核销变成死胡同(后端注释原话:「却没有任何端点能接收那个选择 ⇒ 核销是个死胡同」)。
library;

enum ScanOutcome {
  /// 真的核销掉了。
  redeemed,

  /// 需要商家从候选里选一个,再调 `scan_qr_code_chapter` / `_station` 提交。
  needsChoice,

  /// 真失败(码无效、无权、已核销…)。
  failed,
}

/// 一个可选项(章节或站点)。
class ScanChoice {
  const ScanChoice({required this.id, this.name});

  final int id;

  /// 名字可能拿不到 —— 后端只保证 `chapterIds`,`chapters`(带名字)是新增的。
  /// 界面拿不到名字时显示「章节 #id」,别显示一个空条目让人不知道选哪个。
  final String? name;

  String get label => (name ?? '').trim().isEmpty ? '#$id' : name!.trim();
}

class ScanResult {
  const ScanResult({
    required this.outcome,
    required this.message,
    this.choices = const <ScanChoice>[],
    this.choiceKind,
  });

  final ScanOutcome outcome;

  /// 后端原话。★ 一律透传 —— 「您在本路线没有生效的权益供给,或该章节已核销」
  /// 这类提示带着商家下一步该做什么,换成「核销失败」就没了。
  final String message;

  final List<ScanChoice> choices;

  /// `chapter` 或 `station` —— 决定第二步调哪个端点。
  final String? choiceKind;

  bool get needsChoice => outcome == ScanOutcome.needsChoice;

  /// 从 `AjaxResult` 整体解析。**必须看 data 而不是只看 code。**
  factory ScanResult.fromBody(Map<String, dynamic> body) {
    final String msg = (body['msg'] as String?) ?? '';
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final bool ok = (body['code'] as num?)?.toInt() == 200;

    if (data['needChapterChoice'] == true) {
      return ScanResult(
        outcome: ScanOutcome.needsChoice,
        message: msg.isEmpty ? '请选择要核销的章节' : msg,
        choiceKind: 'chapter',
        choices: _parseChoices(
          ids: data['chapterIds'],
          described: data['chapters'],
          idKey: 'id',
        ),
      );
    }
    if (data['needStationChoice'] == true) {
      return ScanResult(
        outcome: ScanOutcome.needsChoice,
        message: msg.isEmpty ? '请选择要核销的站点' : msg,
        choiceKind: 'station',
        choices: _parseChoices(
          ids: null,
          described: data['stations'],
          // 站点回传的是「中标记录ID」
          idKey: 'registrationMerchantId',
        ),
      );
    }
    return ScanResult(
      outcome: ok ? ScanOutcome.redeemed : ScanOutcome.failed,
      message: msg.isEmpty ? (ok ? '核销成功' : '核销失败') : msg,
    );
  }

  /// `chapters`(带名字)与 `chapterIds`(纯 id)后端保证**同源同序**。
  /// 优先用带名字的那份;拿不到就退回纯 id,**不要两份都用**——
  /// 后端注释明确说「别让它们能各说各话」。
  static List<ScanChoice> _parseChoices({
    required Object? ids,
    required Object? described,
    required String idKey,
  }) {
    if (described is List && described.isNotEmpty) {
      return described
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) {
            // ⚠️ 先取专用 key,再退回通用 `id`;两个都不是 num 就当拿不到。
            //   原来写成 `(a ?? b ?? 0) is num ? (a ?? b) as num : 0` ——
            //   兜底的 0 让 `is num` 恒真,而 `(a ?? b)` 此时是 null,
            //   `as num` 直接抛。测试当场抓到了。
            final Object? raw = m[idKey] ?? m['id'];
            return ScanChoice(
              id: raw is num ? raw.toInt() : 0,
              name: (m['name'] ?? m['title'])?.toString(),
            );
          })
          .where((ScanChoice c) => c.id > 0)
          .toList();
    }
    if (ids is List) {
      return ids
          .whereType<num>()
          .map((num n) => ScanChoice(id: n.toInt()))
          .where((ScanChoice c) => c.id > 0)
          .toList();
    }
    return const <ScanChoice>[];
  }
}
