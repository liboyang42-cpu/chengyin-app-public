/// 创作端「高级玩法配置器」的状态模型 —— 编辑页里那份可编辑的 advanced map。
///
/// 结构 1:1 真源 `pages/publish/temp/index.js` 的 `this.data.advanced` + `gameKey`:
/// 选玩法走 [advApplyToConfig](只开选中段、关掉其余、写 mode、顶 validationMethod),
/// 修饰段(计时等)是叠加开关。落库时 [serialize] 出 `advancedConfigJson`。
///
/// 本批(a1-creator-configurator · 1/3)接的是决定类 + 挑战类七段(纯标量、无图)
/// 与 timer 修饰段;其余段数据模型已就绪(见 advanced_play_config.dart),面板分批接。
library;

import 'package:flutter/foundation.dart';

import '../../data/models/advanced_play_config.dart';
import '../../data/models/node_game_catalog.dart';

class AdvancedConfigDraft extends ChangeNotifier {
  AdvancedConfigDraft({Map<String, Object?>? advanced, this.adopted = false})
    : _advanced = advanced ?? defaultAdvancedConfig(),
      gameKey = advDetectGame(advanced);

  /// 从已有的 `advancedConfigJson` 反序列化(编辑/套用旧模板时)。
  factory AdvancedConfigDraft.fromJson(String? raw, {bool adopted = false}) {
    final parsed = parseAdvancedConfig(raw);
    return AdvancedConfigDraft(advanced: parsed.value, adopted: adopted);
  }

  final Map<String, Object?> _advanced;
  bool adopted;

  /// 当前选中的玩法目录 key('' = 没选玩法,走老 validationMethod 链路)。
  String gameKey;

  /// 选中玩法后写回老链路的通关判定;null = 未由玩法驱动(保留 draft 原值)。
  int? validationMethod;

  Map<String, Object?> get advanced => _advanced;

  Map<String, Object?> _section(String key) {
    final Object? raw = _advanced[key];
    if (raw is Map) {
      // cast 返回底层同一份 map 的视图:写进去就是写进 _advanced,不会被复制丢掉。
      return raw.cast<String, Object?>();
    }
    final Map<String, Object?> created = <String, Object?>{};
    _advanced[key] = created;
    return created;
  }

  bool isEnabled(String key) => _section(key)['enabled'] == true;

  String text(String key, String field) => advText(_section(key)[field]);

  /// 数字字段:以字符串回显给输入框(整数值不带小数点)。
  String number(String key, String field) {
    final Object? raw = _section(key)[field];
    final double? n = advNumber(raw);
    if (n == null) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : '$n';
  }

  void setEnabled(String key, bool value) {
    _section(key)['enabled'] = value;
    notifyListeners();
  }

  void setText(String key, String field, String value) {
    _section(key)[field] = value;
    notifyListeners();
  }

  void setNumber(String key, String field, String value) {
    _section(key)[field] = value.isEmpty ? '' : value;
    notifyListeners();
  }

  void setBool(String key, String field, bool value) {
    _section(key)[field] = value;
    notifyListeners();
  }

  /// 抛硬币正/反面这类嵌套对象:返回**活的**子 map(缺失时建一个空壳并挂上去)。
  Map<String, Object?> nested(String section, String sub) {
    final Map<String, Object?> parent = _section(section);
    final Object? raw = parent[sub];
    if (raw is Map) return raw.cast<String, Object?>();
    final Map<String, Object?> created = <String, Object?>{};
    parent[sub] = created;
    return created;
  }

  void setNested(String section, String sub, String field, String value) {
    nested(section, sub)[field] = value;
    notifyListeners();
  }

  /// 骰子六面(读回一个长度可变的副本给 UI 渲染)。
  List<Object?> faces() {
    final Object? raw = _section('diceRoll')['faces'];
    return raw is List ? raw : const <Object?>[];
  }

  void setFace(int index, String value) {
    final Map<String, Object?> dr = _section('diceRoll');
    final List<Object?> faces = <Object?>[
      ...?_asFaces(dr['faces']),
    ];
    while (faces.length < 6) {
      faces.add('');
    }
    faces[index] = value;
    dr['faces'] = faces;
    notifyListeners();
  }

  List<Object?>? _asFaces(Object? raw) => raw is List ? raw : null;

  void setDiceCount(int count) => setNumber('diceRoll', 'diceCount', '$count');


  /// 选择玩法:走真源 applyToConfig 语义,并顶回 validationMethod。
  void selectGame(String key) {
    final applied = advApplyToConfig(_advanced, key);
    if (applied == null) return;
    _advanced
      ..clear()
      ..addAll(applied);
    gameKey = key;
    final game = advFindGame(key);
    if (game != null) validationMethod = game.validationMethod;
    notifyListeners();
  }

  /// 取消选玩法:关掉所有玩法段(回到老链路)。
  void clearGame() {
    for (final name in kGameSections) {
      final Object? raw = _advanced[name];
      if (raw is Map) raw['enabled'] = false;
    }
    gameKey = '';
    validationMethod = null;
    notifyListeners();
  }

  /// 校验错误文案(空串 = 通过)。给发布/预览按钮当门槛。
  String get error => validateAdvancedConfigInput(
    _advanced,
    opts: AdvancedValidateOpts(adoptedFromLibrary: adopted),
  );

  /// 落库 JSON:校验不过返回空串(不写脏数据,由 [error] 挡住发布)。
  String serialize() {
    try {
      return serializeAdvancedConfig(
        _advanced,
        opts: AdvancedValidateOpts(adoptedFromLibrary: adopted),
      );
    } catch (_) {
      return '';
    }
  }

  /// 当前选中的玩法条目(用于画已选卡);未选返回 null。
  NodeGameItem? get selectedGame => advFindGame(gameKey);

  /// 本批已接配置面板的玩法段(其余在目录里可见但禁用,避免「选了填不了」)。
  static const Set<String> kImplementedGameKeys = <String>{
    'coin',
    'dice',
    'react',
    'shake',
    'quiet',
    'countdown',
    'stopwatch',
  };
  static const Set<String> kImplementedModifiers = <String>{'timer'};
}
