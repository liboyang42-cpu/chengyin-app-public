/// 《预制人生》四段(profile · photoCheck · note · typeIn)的数据层。
///
/// 真源 = 小程序(2026-09-17 契约 §2,§2.3 的新 check 段已作废 —— R14 检定
/// 走 journey 路,App 侧早已由 `journey_check_stage.dart` 接上):
/// - `pages/play/utils/playkit-view.js` 的 `buildProfile` / `buildPhotoCheck` /
///   `buildNote` / `buildTypeIn`(服务端视图 → 组件 props)与
///   `segmentComplete` / `ACTION_OF` / `serverPayload`(动作名与字段名);
/// - `pages/play/components/playkit-{profile,photocheck,note,typein}/index.js`
///   的 observers(判定行 / 次数行这些屏上的字在这一层算出来)。
///
/// ## 三条口径(与问答族同族,不是本层自创)
/// 1. **结果一律由服务端定**:建档提交即锁档、拍照按视觉模型判、
///    留言只算长度与预设两道、打字的相等与限时都在后端复核 ——
///    这里不判对错、不改状态,只把服务端给的那个结论演出来。
/// 2. **两步链**:photoCheck 与 qa 拍照同理,先上传拿地址再连地址提交
///    ([kPhotoCheckShootAction] 只抛临时路径);profile 的头像更是**只传不提**,
///    地址写回组件,提交时随 [kProfileSubmitAction] 一起走(真源页面
///    `_submitKitPhoto` 的 `cfg.avatar` 分支同一条)。
/// 3. **fail-forward 不判死不假过**:photoCheck 的降级态(模型不可用/超时)
///    屏上只许说「这次没能审」,不许出现「通过 / 不通过」这类假结论 ——
///    这一段照抄真源组件 observer 的分支顺序。
library;

import 'package:flutter/foundation.dart';

/// 动作名 —— 逐字照真源 `ACTION_OF`(「少一条不会报错,只是玩家做完那一下
/// 什么也没发生」)。photoCheck 的提交名不在 `ACTION_OF` 里(那张表是
/// 「组件事件 → 动作名」,它的提交发生在页面上传完之后),
/// 但它是服务端 `AdvancedGameRuntimeServiceImpl` 认识的动作。
const String kProfileSubmitAction = 'SUBMIT_PROFILE';
const String kNoteSubmitAction = 'SUBMIT_NOTE';
const String kTypeInStartAction = 'START_CHALLENGE';
const String kTypeInSubmitAction = 'SUBMIT_TYPE_IN';
const String kPhotoCheckSubmitAction = 'SUBMIT_PHOTO_CHECK';

/// 拍照审核**不在一步直发路径里**:与 [kQaShootAction] 同理,先上传拿地址、
/// 再连地址提交。组件只抛这一条与临时路径,宿主拦成两步链
/// (真源 `pages/play/index.js` 的 `photocheck` 分支同一条)。
const String kPhotoCheckShootAction = 'photocheck:shoot';

/// 建档头像也是上传,但**不发动作、也不经过 onAction**:组件直接走
/// [PlayKitFullscreenContext.onUploadPhoto] 拿地址,提交时随
/// [kProfileSubmitAction] 一起报(真源 `_submitKitPhoto` 的 `cfg.avatar` 分支:
/// 「为真时不发动作,只把地址写回 kit」)。

/// `profile` 一屏里的一道题(text 输入 / pick 点选)。
@immutable
class PlayKitProfileQuestion {
  const PlayKitProfileQuestion({
    required this.key,
    required this.label,
    required this.isPick,
    required this.maxLength,
    required this.required,
    required this.options,
  });

  /// 服务端给的 key:答案按它归组,标签在它那边没有意义。
  final String key;
  final String label;

  /// `kind === 'pick'` 走点选,其余(含缺失)都是输入 —— 真源 wxml 的
  /// `item.kind !== 'pick'` 同一条。
  final bool isPick;
  final int maxLength;
  final bool required;
  final List<PlayKitQuizChoice> options;

  static PlayKitProfileQuestion? from(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> map = raw;
    final String key = '${map['key'] ?? ''}'.trim();
    if (key.isEmpty) return null;
    return PlayKitProfileQuestion(
      key: key,
      label: '${map['label'] ?? ''}'.trim(),
      isPick: '${map['kind'] ?? ''}'.trim() == 'pick',
      maxLength: _int(map['maxLength']),
      required: map['required'] == true,
      options:
          (map['options'] is List ? map['options']! as List : const <Object?>[])
              .map(PlayKitQuizChoice.from)
              .whereType<PlayKitQuizChoice>()
              .toList(growable: false),
    );
  }
}

/// 点选题的一个选项(建档用,形状与问答族的 {id, label} 同构)。
@immutable
class PlayKitQuizChoice {
  const PlayKitQuizChoice({required this.id, required this.label});

  static PlayKitQuizChoice? from(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> map = raw;
    final String id = '${map['key'] ?? ''}'.trim();
    final String label = '${map['label'] ?? ''}'.trim();
    if (id.isEmpty && label.isEmpty) return null;
    return PlayKitQuizChoice(id: id, label: label.isEmpty ? id : label);
  }

  final String id;
  final String label;
}

/// `profile` 一屏(契约 §2.1)。
///
/// ★ `options[].effects` 服务端根本不下发(数值加成是暗的)—— 这里也没有
///   那个字段可解析:组件只收「玩家填了什么」,加成由服务端落到它自己的
///   state 变量上。
@immutable
class PlayKitProfileData {
  const PlayKitProfileData({
    required this.title,
    required this.lead,
    required this.avatarEnabled,
    required this.avatarRequired,
    required this.questions,
    required this.answers,
    required this.avatarUrl,
    required this.done,
  });

  final String title;
  final String lead;
  final bool avatarEnabled;
  final bool avatarRequired;
  final List<PlayKitProfileQuestion> questions;
  final Map<String, String> answers;
  final String avatarUrl;
  final bool done;

  factory PlayKitProfileData.fromKit(Map<String, Object?> kit) {
    final Object? avatar = kit['avatar'];
    final Map<String, Object?> avatarMap = avatar is Map
        ? avatar.map<String, Object?>(
            (Object? k, Object? v) => MapEntry('$k', v),
          )
        : const <String, Object?>{};
    final Object? rawAnswers = kit['answers'];
    return PlayKitProfileData(
      title: _text(kit['title'], '出生登记'),
      lead: _text(kit['lead']),
      avatarEnabled: avatarMap['enabled'] == true,
      avatarRequired: avatarMap['required'] == true,
      questions:
          (kit['questions'] is List
                  ? kit['questions']! as List
                  : const <Object?>[])
              .map(PlayKitProfileQuestion.from)
              .whereType<PlayKitProfileQuestion>()
              .toList(growable: false),
      answers: rawAnswers is Map
          ? rawAnswers.map(
              (Object? k, Object? v) => MapEntry('$k', v == null ? '' : '$v'),
            )
          : const <String, String>{},
      avatarUrl: _text(kit['avatarUrl']),
      done: kit['done'] == true,
    );
  }

  /// 必填项都填了才放开提交(`required` 是作者的显式声明,不替它猜默认值);
  /// done 后服务端拒绝改档,按钮锁成「已登记」。
  bool ctaEnabled(Map<String, String> form) {
    if (done) return false;
    return !questions.any(
      (PlayKitProfileQuestion q) =>
          q.required && (form[q.key] ?? '').trim().isEmpty,
    );
  }

  /// 载荷逐字对齐真源 `serverPayload` 的 `profile:submit`:
  /// `{ answers, avatarUrl }` —— 只报原始输入,加成与落档都在服务端。
  Map<String, Object?> submitPayload(
    Map<String, String> answers,
    String avatarUrl,
  ) => <String, Object?>{
    'answers': <String, Object?>{...answers},
    'avatarUrl': avatarUrl,
  };
}

/// `photoCheck` 一屏(契约 §2.2,2026-09-17 改版:接真视觉模型)。
///
/// 原先「本地算亮区/边缘/清晰度 → 随图上报 score」那套在真源已整段删除 ——
/// 客户端报的分可伪造,也判不了「有没有拍到『新』字招牌」这种语义要求。
/// 这一层同样只报图片地址,不读像素。
@immutable
class PlayKitPhotoCheckData {
  const PlayKitPhotoCheckData({
    required this.title,
    required this.shotNote,
    required this.maxTries,
    required this.fallback,
    required this.tries,
    required this.passed,
    required this.flagged,
    required this.degraded,
    required this.lastReason,
    required this.lastUrl,
  });

  final String title;
  final String shotNote;
  final int maxTries;

  /// 次数用尽的兜底口径(服务端给):'pass' = 先算过,其余 = 就是没过。
  final String fallback;

  /// 已经拍了几次(服务端权威读数,本地不扣)。
  final int tries;
  final bool passed;
  final bool flagged;

  /// 模型不可用 / 超时 / 解析失败:这次**没有结论** —— 不判死也不假装通过。
  final bool degraded;
  final String lastReason;
  final String lastUrl;

  factory PlayKitPhotoCheckData.fromKit(Map<String, Object?> kit) =>
      PlayKitPhotoCheckData(
        title: _text(kit['title'], '拍一张'),
        shotNote: _text(kit['shotNote']),
        maxTries: _int(kit['maxTries']),
        fallback: _text(kit['fallback'], 'retake'),
        tries: _int(kit['tries']),
        passed: kit['passed'] == true,
        flagged: kit['flagged'] == true,
        degraded: kit['degraded'] == true,
        lastReason: _text(kit['lastReason']),
        lastUrl: _text(kit['lastUrl']),
      );

  /// 判定行 —— 分支顺序照抄真源组件 observer
  /// (`playkit-photocheck/index.js` 的 'show, tries, …' 一节):
  /// 降级在最前,**假结论不许出现**;没结论时也不卡死(fail-forward)。
  String get verdict {
    if (degraded) return '这次没能审，先往下走';
    if (passed) return '这张过了';
    if (flagged) return fallback == 'pass' ? '机会用完了，这张先算过' : '机会用完了';
    if (tries > 0) return '还差一点，再拍一张';
    return '';
  }

  /// 判定行的颜色档位:ok / no / 无(降级不给颜色 —— 它不是结论)。
  String get verdictKind {
    if (degraded) return '';
    if (passed) return 'ok';
    if (flagged) return fallback == 'pass' ? 'ok' : 'no';
    if (tries > 0) return 'no';
    return '';
  }

  /// 没过时的真实理由(服务端给的)。有就摆给玩家看,别只丢一句「再拍一张」;
  /// 降级那行不配理由 —— 它压根没审。
  String get reason =>
      (!degraded && !passed && !flagged && tries > 0) ? lastReason : '';

  String get triesLabel => maxTries > 0
      ? '还能重拍 ${maxTries - tries < 0 ? 0 : maxTries - tries} 次'
      : '';

  /// 这一张定没定:定了就锁拍摄钮(判定在服务端,这里只是不再让点)。
  bool get locked => passed || flagged;

  /// 提交载荷:两步链的末一步,只带服务端算出来的图片地址(不带本地路径)。
  Map<String, Object?> submitPayload(String imageUrl) => <String, Object?>{
    'imageUrl': imageUrl,
  };
}

/// `note` 的一条留言(前面的人写的)。
@immutable
class PlayKitNoteEntry {
  const PlayKitNoteEntry({required this.text, required this.at});

  final String text;

  /// epoch 毫秒(服务端原样给)。屏上的显示格式是 iOS 27 原生化的事。
  final int? at;
}

/// `note` 一屏(契约 §2.4)。
@immutable
class PlayKitNoteData {
  const PlayKitNoteData({
    required this.title,
    required this.prompt,
    required this.maxLength,
    required this.presets,
    required this.previous,
    required this.mine,
    required this.done,
  });

  final String title;
  final String prompt;
  final int maxLength;
  final List<String> presets;
  final List<PlayKitNoteEntry> previous;
  final String mine;
  final bool done;

  factory PlayKitNoteData.fromKit(Map<String, Object?> kit) {
    // 服务端 noteView 给的是对象 {text, at};真源 buildNote 是 `seg.mine || ''`
    // (JS 里对象非空串,truthy 直接进 textarea)。App 两种形状都收:
    // 对象取 text,字符串原样 —— 取不到就是没留过。
    final Object? mine = kit['mine'];
    final String mineText = mine is Map ? _text(mine['text']) : _text(mine);
    return PlayKitNoteData(
      title: _text(kit['title'], '留一句'),
      prompt: _text(kit['prompt']),
      // maxLength 缺省 40 —— 与真源 buildNote 的 `Number(...) || 40` 同一条。
      maxLength: _int(kit['maxLength']) > 0 ? _int(kit['maxLength']) : 40,
      presets:
          (kit['presets'] is List ? kit['presets']! as List : const <Object?>[])
              .map((Object? p) => '$p'.trim())
              .where((String p) => p.isNotEmpty)
              .toList(growable: false),
      previous:
          (kit['previous'] is List
                  ? kit['previous']! as List
                  : const <Object?>[])
              .whereType<Map>()
              .map(
                (Map<Object?, Object?> p) => PlayKitNoteEntry(
                  text: _text(p['text']),
                  at: p['at'] is num ? (p['at']! as num).toInt() : null,
                ),
              )
              .where((PlayKitNoteEntry e) => e.text.isNotEmpty)
              .toList(growable: false),
      mine: mineText,
      done: kit['done'] == true,
    );
  }

  /// 载荷逐字对齐真源 `serverPayload` 的 `note:submit`:只要 `{text}`。
  Map<String, Object?> submitPayload(String text) => <String, Object?>{
    'text': text,
  };
}

/// `typeIn` 一屏(契约 §2.5)。目标文本是明牌 —— 这玩法考的是手速不是猜谜。
@immutable
class PlayKitTypeInData {
  const PlayKitTypeInData({
    required this.title,
    required this.target,
    required this.seconds,
    required this.caseSensitive,
    required this.tries,
    required this.attempts,
    required this.passed,
  });

  final String title;
  final String target;
  final int seconds;
  final bool caseSensitive;

  /// 可以打几次(0 = 不限)。服务端权威读数。
  final int tries;
  final int attempts;
  final bool passed;

  factory PlayKitTypeInData.fromKit(Map<String, Object?> kit) =>
      PlayKitTypeInData(
        title: _text(kit['title'], '打出这行字'),
        target: _text(kit['target']),
        seconds: _int(kit['seconds']),
        caseSensitive: kit['caseSensitive'] == true,
        tries: _int(kit['tries']),
        attempts: _int(kit['attempts']),
        passed: kit['passed'] == true,
      );

  /// 「第 N / T 次」—— 不限次就没有这一行。
  String get attemptLabel => tries > 0 ? '第 ${attempts + 1} / $tries 次' : '';

  /// 交卷只报原始输入 + 设备时钟读数(服务端按开表那一刻的服务器时间复核)。
  /// `elapsedMs` 取整对齐真源 `serverPayload` 的 `Math.round`。
  Map<String, Object?> submitPayload(String text, int elapsedMs) =>
      <String, Object?>{'text': text, 'elapsedMs': elapsedMs.round()};
}

String _text(Object? value, [String fallback = '']) {
  final String text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}
