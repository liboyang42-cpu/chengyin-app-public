/// 创作端「高级玩法配置」数据层 —— 节点模板编辑器(`temp/index.js`)写进
/// `advancedConfigJson` 那一份的 Dart 端口。
///
/// ★ 结构 1:1 真源:`chengyinhub-xcx/utils/publish/advanced-game-config.js`
///   的 `defaultConfig / normalize / validateNormalized / serialize / parse`。
///   这份配置由后端 `AdvancedGamePublicProjection` 投影给玩家端,玩家端
///   `playkit_projection.dart` 读的就是这里的**段名 + 原始段对象**,所以
///   这里刻意用 `Map<String, Object?>` 逐段承载,和播放侧同形 —— 创作端配出来
///   的 payload 能被渲染器直接消费,不需要中间再翻译一层。
///
/// 判定口径逐字对齐真源,错误文案也照抄(那句是给商家看的人话)。
library;

import 'dart:convert';

const int kAdvancedConfigSchemaVersion = 1;

/// 找东西的判定半径:系统定,商家不填。服务端只收 0.03–0.15,取中间值。
const double kHotspotRadius = 0.08;

final RegExp _clockPattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
final RegExp _keyPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _outcomeCodePattern = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

/// 与 validationMethod 正交的通用机制,任何玩法都能叠加。
const List<String> kAdvancedCoreSections = <String>[
  'timer',
  'random',
  'branch',
  'leaderboard',
  'multiplayer',
];
/// Figma 组件库 v5.1 新玩法。名单必须与服务端 AdvancedGameConfigValidator 一一对应。
const List<String> kAdvancedKitSections = <String>[
  'timeWindow',
  'blindTaste',
  'silentOrder',
  'diyName',
  'musicCorner',
  'steps',
  'dailySign',
];
/// 自由探索玩法(estimate/pricePair/hiddenObject 各决定节点怎么算通关;predict/scan 纯附加)。
const List<String> kAdvancedPlaySections = <String>[
  'estimate',
  'pricePair',
  'hiddenObject',
  'predict',
  'qa',
  'scan',
];
/// 决定类与挑战类七个 —— 秘密不在配置里,由服务端运行时现生成,整段可下发。
const List<String> kAdvancedDecideSections = <String>[
  'coinFlip',
  'diceRoll',
  'reaction',
  'ballShake',
  'quietHold',
  'countdown',
  'stopwatch',
];
const List<String> kAdvancedSections = <String>[
  ...kAdvancedCoreSections,
  ...kAdvancedKitSections,
  ...kAdvancedPlaySections,
  ...kAdvancedDecideSections,
];

String advText(Object? value) => value == null ? '' : value.toString().trim();

/// JS `Number(v)`:解析不出数字返回 null(等价 NaN)。
double? advNumber(Object? value) {
  if (value is num) return value.toDouble();
  final String s = value == null ? '' : value.toString().trim();
  if (s.isEmpty) return 0; // JS Number('')===0
  return double.tryParse(s);
}

/// JS `Number(v) || 0`(NaN/0/''/null 一律归 0)。
double advNumOr0(Object? value) => advNumber(value) ?? 0;

/// JS `Number.isInteger(Number(v))`。
bool advIsInteger(Object? value) {
  final double? n = advNumber(value);
  return n != null && n == n.roundToDouble();
}

Map<String, Object?> advClone(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

/// 默认配置:每段都带、全部 `enabled:false`。逐字对齐真源 `defaultConfig()`。
Map<String, Object?> defaultAdvancedConfig() => <String, Object?>{
  'schemaVersion': kAdvancedConfigSchemaVersion,
  'timer': <String, Object?>{
    'enabled': false,
    'durationSeconds': 300,
    'timeoutResult': 'FAILED',
  },
  'random': <String, Object?>{
    'enabled': false,
    'drawCount': 1,
    'items': <Object?>[
      <String, Object?>{'id': 'item_1', 'label': '线索卡', 'weight': 1, 'content': ''},
    ],
  },
  'branch': <String, Object?>{
    'enabled': false,
    'startStepId': 'start',
    'steps': <Object?>[
      <String, Object?>{
        'id': 'start',
        'title': '起点',
        'body': '',
        'terminal': true,
        'outcomeCode': 'COMPLETED',
        'outcomeLabel': '完成节点',
        'options': <Object?>[],
      },
    ],
  },
  'leaderboard': <String, Object?>{
    'enabled': false,
    'metric': 'ELAPSED_TIME',
    'scope': 'ACTIVITY',
    'limit': 50,
  },
  'multiplayer': <String, Object?>{
    'enabled': false,
    'mode': 'SEQUENTIAL',
    'minPlayers': 2,
    'maxPlayers': 4,
    'assignment': 'AUTO',
    'requiredTurns': 1,
    'unitScore': 0,
    'roles': <Object?>[
      <String, Object?>{'id': 'player', 'label': '队员', 'min': 1, 'max': 4},
    ],
    'turnOrder': <Object?>['player'],
  },
  // ===== v5.1 新玩法 =====
  'timeWindow': <String, Object?>{
    'enabled': false,
    'eyebrow': '',
    'title': '',
    'openFrom': '20:00',
    'openTo': '23:00',
    'subscribeTmplId': '',
  },
  'blindTaste': <String, Object?>{
    'enabled': false,
    'title': '',
    'steps': '',
    'hint': '',
    'xp': 0,
    'answerKey': 'A',
    'options': <Object?>[
      <String, Object?>{'key': 'A', 'label': ''},
      <String, Object?>{'key': 'B', 'label': ''},
    ],
  },
  'silentOrder': <String, Object?>{
    'enabled': false,
    'title': '',
    'rule': '',
    'limitSeconds': 0,
  },
  'diyName': <String, Object?>{
    'enabled': false,
    'title': '',
    'maxLength': 16,
    'suggestions': <Object?>[],
  },
  'musicCorner': <String, Object?>{
    'enabled': false,
    'title': '',
    'trackName': '',
    'audioUrl': '',
    'durationSeconds': 0,
  },
  'steps': <String, Object?>{
    'enabled': false,
    'eyebrow': '',
    'goal': 6000,
    'xp': 0,
  },
  'dailySign': <String, Object?>{
    'enabled': false,
    'signer': '',
    'sealText': '',
    'poems': <Object?>[],
  },
  // ===== 自由探索玩法 =====
  'estimate': <String, Object?>{
    'enabled': false,
    'title': '',
    'unit': '',
    'reveal': '',
    'min': 0,
    'max': 1000,
    'answer': 500,
    'tolerance': 50,
    'xp': 0,
  },
  'pricePair': <String, Object?>{
    'enabled': false,
    'title': '',
    'xp': 0,
    'maxTries': 0,
    'items': <Object?>[
      <String, Object?>{'id': 'pic_1', 'name': '', 'imageUrl': '', 'correct': true},
      <String, Object?>{'id': 'pic_2', 'name': '', 'imageUrl': '', 'correct': false},
      <String, Object?>{'id': 'pic_3', 'name': '', 'imageUrl': '', 'correct': false},
    ],
  },
  'qa': <String, Object?>{
    'enabled': false,
    'mode': 'TYPE',
    'title': '',
    'lead': '',
    'imageUrl': '',
    'audioUrl': '',
    'answerText': '',
    'reveal': false,
    'maxTries': 0,
    'xp': 0,
    'options': <Object?>[
      <String, Object?>{'id': 'opt_1', 'label': '', 'fb': '', 'correct': true},
      <String, Object?>{'id': 'opt_2', 'label': '', 'fb': '', 'correct': false},
    ],
  },
  'scan': <String, Object?>{
    'enabled': false,
    'kind': 'TEXT',
    'reply': '',
    'audioUrl': '',
    'imageUrl': '',
    'xp': 0,
  },
  'hiddenObject': <String, Object?>{
    'enabled': false,
    'title': '',
    'hint': '',
    'imageUrl': '',
    'xp': 0,
    'hotspots': <Object?>[
      <String, Object?>{'id': 'spot_1', 'label': '', 'x': 0.25, 'y': 0.3, 'r': kHotspotRadius},
      <String, Object?>{'id': 'spot_2', 'label': '', 'x': 0.7, 'y': 0.45, 'r': kHotspotRadius},
      <String, Object?>{'id': 'spot_3', 'label': '', 'x': 0.45, 'y': 0.75, 'r': kHotspotRadius},
    ],
  },
  'predict': <String, Object?>{
    'enabled': false,
    'question': '',
    'hint': '',
    'closeAtHour': 20,
    'xp': 0,
    'options': <Object?>[
      <String, Object?>{'key': 'A', 'label': ''},
      <String, Object?>{'key': 'B', 'label': ''},
    ],
  },
  // ===== 决定类与挑战类 =====
  'coinFlip': <String, Object?>{
    'enabled': false,
    'kicker': '',
    'xp': 0,
    'heads': <String, Object?>{'label': '正面', 'action': ''},
    'tails': <String, Object?>{'label': '反面', 'action': ''},
  },
  'diceRoll': <String, Object?>{
    'enabled': false,
    'kicker': '',
    'diceCount': 1,
    'xp': 0,
    'faces': <Object?>['', '', '', '', '', ''],
  },
  'reaction': <String, Object?>{
    'enabled': false,
    'kicker': '',
    'rounds': 3,
    'goalMs': 320,
    'xp': 0,
  },
  'ballShake': <String, Object?>{
    'enabled': false,
    'kicker': '',
    'goal': 30,
    'timed': false,
    'seconds': 12,
    'xp': 0,
  },
  'quietHold': <String, Object?>{
    'enabled': false,
    'kicker': '',
    'sub': '',
    'seconds': 15,
    'xp': 0,
  },
  'countdown': <String, Object?>{
    'enabled': false,
    'kicker': '',
    'seconds': 90,
    'doneText': '',
    'xp': 0,
  },
  'stopwatch': <String, Object?>{
    'enabled': false,
    'kicker': '',
    'targetSeconds': 10,
    'toleranceMs': 300,
    'tries': 3,
    'xp': 0,
  },
};

/// 本模块不认识的顶层段(将来服务端新加的机制)。读进来原样留着,存回去原样带上。
List<String> advExtraKeys(Map<String, Object?>? model) {
  if (model == null) return const <String>[];
  return model.keys
      .where((k) => k != 'schemaVersion' && !kAdvancedSections.contains(k))
      .toList();
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map) {
    final m = <String, Object?>{};
    value.forEach((k, v) => m['$k'] = v);
    return m;
  }
  return null;
}

List<Object?> _asList(Object? value) =>
    value is List ? value : const <Object?>[];

/// 真源 `parse`:读回一份原始 JSON,缺段用默认补齐,未知段透传,采用场景的
/// 秘密字段(blindTaste.answerKey / branch 终点)按真源规则处理。
({Map<String, Object?> value, String error}) parseAdvancedConfig(Object? raw) {
  final Map<String, Object?> fallback = defaultAdvancedConfig();
  if (raw == null || (raw is String && raw.isEmpty)) {
    return (value: fallback, error: '');
  }
  try {
    final Object? decoded = raw is String ? jsonDecode(raw) : raw;
    final Map<String, Object?>? source = _asMap(decoded);
    if (source == null) throw StateError('shape');
    final Map<String, Object?> value = defaultAdvancedConfig();
    for (final String key in kAdvancedSections) {
      final Map<String, Object?>? incoming = _asMap(source[key]);
      if (incoming != null) {
        value[key] = <String, Object?>{
          ..._asMap(value[key])!,
          ...advClone(incoming),
        };
      }
    }
    for (final String key in advExtraKeys(source)) {
      value[key] = advClone(_asMap(source[key])!);
    }
    // 采用别人的模板时服务端剥掉了 blindTaste.answerKey —— 不许拿默认 'A' 顶上。
    final Map<String, Object?>? srcBlind = _asMap(source['blindTaste']);
    if (srcBlind != null && !srcBlind.containsKey('answerKey')) {
      _asMap(value['blindTaste'])!['answerKey'] = '';
    }
    final Map<String, Object?> branch = _asMap(value['branch'])!;
    branch['steps'] = _asList(branch['steps']).map<Object?>((step) {
      final Map<String, Object?> normalized =
          Map<String, Object?>.from(_asMap(step)!);
      if (normalized['terminal'] == true) {
        if (advText(normalized['outcomeCode']).isEmpty) {
          normalized['outcomeCode'] = 'COMPLETED';
        }
        if (advText(normalized['outcomeLabel']).isEmpty) {
          normalized['outcomeLabel'] = advText(normalized['title']).isEmpty
              ? '完成节点'
              : advText(normalized['title']);
        }
      }
      return normalized;
    }).toList();
    value['schemaVersion'] = advNumber(source['schemaVersion']) ?? kAdvancedConfigSchemaVersion;
    return (
      value: value,
      error: value['schemaVersion'] == kAdvancedConfigSchemaVersion
          ? ''
          : '配置版本不受支持，请重新保存',
    );
  } catch (_) {
    return (value: fallback, error: '高级玩法配置无法读取，请检查后重新保存');
  }
}

List<String> advEnabledSections(Map<String, Object?> model) => kAdvancedSections
    .where((k) => _asMap(model[k])?['enabled'] == true)
    .toList();

/// 存盘前清洗:只动**已启用**的段;未启用的段原样保留。逐段对齐真源 `normalize`。
Map<String, Object?> normalizeAdvancedConfig(Map<String, Object?>? model) {
  final Map<String, Object?> out = advClone(model ?? <String, Object?>{});
  out['schemaVersion'] = kAdvancedConfigSchemaVersion;

  // 关键:必须拿到 `out` 里那份**活的**段对象来就地清洗。_asMap 会复制一份,
  // 改了副本 = 什么都没改。advClone 之后每个段都是 Map,直接强转取引用。
  Map? live(String key) => out[key] is Map ? out[key] as Map : null;

  void dropIfBlank(Map section, List<String> fields) {
    for (final String field in fields) {
      final String value = advText(section[field]);
      if (value.isNotEmpty) {
        section[field] = value;
      } else {
        section.remove(field);
      }
    }
  }

  void keepNum(Map obj, String field) {
    final double? parsed = advNumber(obj[field]);
    if (parsed != null) {
      obj[field] = parsed;
    } else {
      obj.remove(field);
    }
  }

  final Map? tw = live('timeWindow');
  if (tw != null && tw['enabled'] == true) {
    tw['openFrom'] = advText(tw['openFrom']);
    tw['openTo'] = advText(tw['openTo']);
    dropIfBlank(tw, <String>['eyebrow', 'title', 'subscribeTmplId']);
  }

  final Map? bt = live('blindTaste');
  if (bt != null && bt['enabled'] == true) {
    bt['title'] = advText(bt['title']);
    bt['answerKey'] = advText(bt['answerKey']);
    bt['xp'] = advNumOr0(bt['xp']);
    dropIfBlank(bt, <String>['steps', 'hint']);
    bt['options'] = _asList(bt['options']).map<Object?>((o) {
      final Map<String, Object?> m = _asMap(o) ?? <String, Object?>{};
      return <String, Object?>{
        'key': advText(m['key']),
        'label': advText(m['label']),
      };
    }).where((o) {
      final Map<String, Object?> m = _asMap(o)!;
      return advText(m['key']).isNotEmpty || advText(m['label']).isNotEmpty;
    }).toList();
  }

  final Map? so = live('silentOrder');
  if (so != null && so['enabled'] == true) {
    so['title'] = advText(so['title']);
    so['limitSeconds'] = advNumOr0(so['limitSeconds']);
    dropIfBlank(so, <String>['rule']);
  }

  final Map? dn = live('diyName');
  if (dn != null && dn['enabled'] == true) {
    dn['title'] = advText(dn['title']);
    dn['maxLength'] = advNumOr0(dn['maxLength']);
    final List<String> suggestions = _asList(dn['suggestions'])
        .map(advText)
        .where((s) => s.isNotEmpty)
        .toList();
    if (suggestions.isNotEmpty) {
      dn['suggestions'] = suggestions;
    } else {
      dn.remove('suggestions');
    }
  }

  final Map? mc = live('musicCorner');
  if (mc != null && mc['enabled'] == true) {
    mc['title'] = advText(mc['title']);
    mc['durationSeconds'] = advNumOr0(mc['durationSeconds']);
    dropIfBlank(mc, <String>['trackName', 'audioUrl']);
  }

  final Map? st = live('steps');
  if (st != null && st['enabled'] == true) {
    st['goal'] = advNumOr0(st['goal']);
    st['xp'] = advNumOr0(st['xp']);
    dropIfBlank(st, <String>['eyebrow']);
  }

  final Map? ds = live('dailySign');
  if (ds != null && ds['enabled'] == true) {
    ds['poems'] = _asList(ds['poems']).map<Object?>((poem) {
      final List<Object?> lines = _asList(poem);
      return lines
          .map(advText)
          .where((l) => l.isNotEmpty)
          .toList();
    }).where((poem) => (_asList(poem)).isNotEmpty).toList();
    dropIfBlank(ds, <String>['signer', 'sealText']);
  }

  final Map? es = live('estimate');
  if (es != null && es['enabled'] == true) {
    es['title'] = advText(es['title']);
    es['min'] = advNumber(es['min']) ?? 0;
    es['max'] = advNumber(es['max']) ?? 0;
    keepNum(es, 'answer');
    keepNum(es, 'tolerance');
    es['xp'] = advNumber(es['xp']) ?? 0;
    dropIfBlank(es, <String>['unit', 'reveal']);
  }

  final Map? cf = live('coinFlip');
  if (cf != null && cf['enabled'] == true) {
    cf['kicker'] = advText(cf['kicker']);
    cf['xp'] = advNumber(cf['xp']) ?? 0;
    for (final String side in <String>['heads', 'tails']) {
      final Map<String, Object?> f = _asMap(cf[side]) ?? <String, Object?>{};
      f['label'] = advText(f['label']);
      f['action'] = advText(f['action']);
      cf[side] = f;
    }
  }

  final Map? dr = live('diceRoll');
  if (dr != null && dr['enabled'] == true) {
    dr['kicker'] = advText(dr['kicker']);
    dr['xp'] = advNumber(dr['xp']) ?? 0;
    dr['diceCount'] = advNumber(dr['diceCount']) == 2 ? 2 : 1;
    final List<Object?> faces = _asList(dr['faces']);
    dr['faces'] = List<Object?>.generate(
        6, (i) => i < faces.length ? advText(faces[i]) : '');
  }

  final Map? rc = live('reaction');
  if (rc != null && rc['enabled'] == true) {
    rc['kicker'] = advText(rc['kicker']);
    rc['rounds'] = advNumber(rc['rounds']) ?? 0;
    rc['goalMs'] = advNumber(rc['goalMs']) ?? 0;
    rc['xp'] = advNumber(rc['xp']) ?? 0;
  }

  final Map? bs = live('ballShake');
  if (bs != null && bs['enabled'] == true) {
    bs['kicker'] = advText(bs['kicker']);
    bs['goal'] = advNumber(bs['goal']) ?? 0;
    bs['timed'] = bs['timed'] == true;
    bs['xp'] = advNumber(bs['xp']) ?? 0;
    if (bs['timed'] == true) {
      bs['seconds'] = advNumber(bs['seconds']) ?? 0;
    } else {
      bs.remove('seconds');
    }
  }

  final Map? qh = live('quietHold');
  if (qh != null && qh['enabled'] == true) {
    qh['kicker'] = advText(qh['kicker']);
    qh['seconds'] = advNumber(qh['seconds']) ?? 0;
    qh['xp'] = advNumber(qh['xp']) ?? 0;
    dropIfBlank(qh, <String>['sub']);
  }

  final Map? cd = live('countdown');
  if (cd != null && cd['enabled'] == true) {
    cd['kicker'] = advText(cd['kicker']);
    cd['doneText'] = advText(cd['doneText']);
    cd['seconds'] = advNumber(cd['seconds']) ?? 0;
    cd['xp'] = advNumber(cd['xp']) ?? 0;
  }

  final Map? sw = live('stopwatch');
  if (sw != null && sw['enabled'] == true) {
    sw['kicker'] = advText(sw['kicker']);
    sw['targetSeconds'] = advNumber(sw['targetSeconds']) ?? 0;
    sw['toleranceMs'] = advNumber(sw['toleranceMs']) ?? 0;
    sw['tries'] = advNumber(sw['tries']) ?? 0;
    sw['xp'] = advNumber(sw['xp']) ?? 0;
  }

  final Map? qa = live('qa');
  if (qa != null && qa['enabled'] == true) {
    qa['mode'] = <String>['TYPE', 'PICK', 'SHOT'].contains(qa['mode']) ? qa['mode'] : 'TYPE';
    qa['title'] = advText(qa['title']);
    qa['lead'] = advText(qa['lead']);
    qa['answerText'] = advText(qa['answerText']);
    qa['reveal'] = qa['reveal'] == true;
    qa['maxTries'] = advNumber(qa['maxTries']) ?? 0;
    qa['xp'] = advNumber(qa['xp']) ?? 0;
    qa['options'] = _asList(qa['options']).map<Object?>((item) {
      final Map<String, Object?> m = _asMap(item) ?? <String, Object?>{};
      return <String, Object?>{
        'id': advText(m['id']),
        'label': advText(m['label']),
        'fb': advText(m['fb']),
        'correct': m['correct'] == true,
      };
    }).toList();
  }

  final Map? sc = live('scan');
  if (sc != null && sc['enabled'] == true) {
    sc['kind'] = <String>['TEXT', 'VOICE', 'IMAGE'].contains(sc['kind']) ? sc['kind'] : 'TEXT';
    sc['reply'] = advText(sc['reply']);
    sc['xp'] = advNumber(sc['xp']) ?? 0;
  }

  final Map? pp = live('pricePair');
  if (pp != null && pp['enabled'] == true) {
    pp['title'] = advText(pp['title']);
    pp['xp'] = advNumber(pp['xp']) ?? 0;
    pp['maxTries'] = advNumber(pp['maxTries']) ?? 0;
    pp['items'] = _asList(pp['items']).map<Object?>((item) {
      final Map<String, Object?> m = _asMap(item) ?? <String, Object?>{};
      final Map<String, Object?> row = <String, Object?>{
        'id': advText(m['id']),
        'name': advText(m['name']),
        'correct': m['correct'] == true,
      };
      final String imageUrl = advText(m['imageUrl']);
      if (imageUrl.isNotEmpty) row['imageUrl'] = imageUrl;
      return row;
    }).toList();
  }

  final Map? ho = live('hiddenObject');
  if (ho != null && ho['enabled'] == true) {
    ho['title'] = advText(ho['title']);
    ho['imageUrl'] = advText(ho['imageUrl']);
    ho['xp'] = advNumber(ho['xp']) ?? 0;
    dropIfBlank(ho, <String>['hint']);
    ho['hotspots'] = _asList(ho['hotspots']).map<Object?>((spot) {
      final Map<String, Object?> m = _asMap(spot) ?? <String, Object?>{};
      final Map<String, Object?> row = <String, Object?>{
        'id': advText(m['id']),
        'label': advText(m['label']),
        'r': kHotspotRadius,
      };
      for (final String field in <String>['x', 'y']) {
        final double? parsed = advNumber(m[field]);
        if (parsed != null) row[field] = parsed;
      }
      return row;
    }).toList();
  }

  final Map? pd = live('predict');
  if (pd != null && pd['enabled'] == true) {
    pd['question'] = advText(pd['question']);
    pd['closeAtHour'] = advNumber(pd['closeAtHour']) ?? -1;
    pd['xp'] = advNumber(pd['xp']) ?? 0;
    dropIfBlank(pd, <String>['hint']);
    pd['options'] = _asList(pd['options']).map<Object?>((o) {
      final Map<String, Object?> m = _asMap(o) ?? <String, Object?>{};
      return <String, Object?>{
        'key': advText(m['key']),
        'label': advText(m['label']),
      };
    }).where((o) {
      final Map<String, Object?> m = _asMap(o)!;
      return advText(m['key']).isNotEmpty || advText(m['label']).isNotEmpty;
    }).toList();
  }

  return out;
}

/// opts.adoptedFromLibrary:采用公共库模板时,被服务端剥掉的秘密字段允许暂空。
class AdvancedValidateOpts {
  const AdvancedValidateOpts({this.adoptedFromLibrary = false});
  final bool adoptedFromLibrary;
}

String _blankIf(Object? v) => advText(v);

String validateAdvancedConfig(
  Map<String, Object?>? model, {
  AdvancedValidateOpts opts = const AdvancedValidateOpts(),
}) {
  if (model == null ||
      advNumber(model['schemaVersion']) != kAdvancedConfigSchemaVersion) {
    return '高级玩法配置版本不受支持';
  }
  final Map<String, Object?> m = model;
  final bool adopted = opts.adoptedFromLibrary;

  bool en(String key) => _asMap(m[key])?['enabled'] == true;
  Map<String, Object?> sec(String key) => _asMap(m[key]) ?? <String, Object?>{};

  if (en('timer')) {
    final double? seconds = advNumber(sec('timer')['durationSeconds']);
    if (seconds == null ||
        seconds != seconds.roundToDouble() ||
        seconds < 10 ||
        seconds > 86400) {
      return '计时时长须为 10 秒至 24 小时';
    }
  }

  if (en('random')) {
    final List<Object?> items = _asList(sec('random')['items']);
    if (items.isEmpty) return '盲盒至少配置 1 个物品';
    final Set<String> ids = <String>{};
    for (final Object? item in items) {
      final Map<String, Object?> o = _asMap(item) ?? <String, Object?>{};
      if (advText(o['id']).isEmpty ||
          advText(o['label']).isEmpty ||
          (advNumber(o['weight']) ?? 0) < 1) {
        return '盲盒物品的 ID、名称和权重不能为空';
      }
      if (ids.contains(o['id'])) return '盲盒物品 ID 不能重复';
      ids.add(advText(o['id']));
    }
    final double? draws = advNumber(sec('random')['drawCount']);
    if (draws == null ||
        draws != draws.roundToDouble() ||
        draws < 1 ||
        draws > items.length) {
      return '盲盒抽取数量须在物品数量范围内';
    }
  }

  if (en('branch')) {
    final Map<String, Object?> b = sec('branch');
    final List<Object?> steps = _asList(b['steps']);
    final Set<String> ids = steps
        .map((s) => advText(_asMap(s)?['id']))
        .toSet();
    if (steps.isEmpty || !ids.contains(advText(b['startStepId']))) {
      return '分支剧情必须配置有效起点';
    }
    final Set<String> outcomeCodes = <String>{};
    for (final Object? rawStep in steps) {
      final Map<String, Object?> step = _asMap(rawStep) ?? <String, Object?>{};
      final List<Object?> options = _asList(step['options']);
      if (advText(step['id']).isEmpty ||
          (step['terminal'] != true && options.isEmpty)) {
        return '分支剧情的非终点必须配置选项';
      }
      if (step['terminal'] == true) {
        final String code = advText(step['outcomeCode']);
        if (!_outcomeCodePattern.hasMatch(code)) {
          return '分支终点 outcomeCode 只能使用大写字母、数字和下划线';
        }
        if (outcomeCodes.contains(code)) return '分支终点 outcomeCode 不能重复';
        outcomeCodes.add(code);
      }
      for (final Object? rawOpt in options) {
        final Map<String, Object?> option = _asMap(rawOpt) ?? <String, Object?>{};
        if (advText(option['id']).isEmpty ||
            advText(option['label']).isEmpty ||
            !ids.contains(advText(option['nextStepId']))) {
          return '分支选项必须指向有效步骤';
        }
      }
    }
  }

  if (en('leaderboard')) {
    final double? limit = advNumber(sec('leaderboard')['limit']);
    if (limit == null ||
        limit != limit.roundToDouble() ||
        limit < 1 ||
        limit > 100) {
      return '排行榜人数须为 1 至 100';
    }
  }

  if (en('multiplayer')) {
    final Map<String, Object?> mp = sec('multiplayer');
    final double? min = advNumber(mp['minPlayers']);
    final double? max = advNumber(mp['maxPlayers']);
    if (min == null ||
        max == null ||
        min != min.roundToDouble() ||
        max != max.roundToDouble() ||
        min < 2 ||
        max > 20 ||
        min > max) {
      return '多人玩法人数须为 2 至 20 人';
    }
    final List<Object?> roles = _asList(mp['roles']);
    if (roles.isEmpty) return '多人玩法至少配置 1 个角色';
    final Set<String> roleIds = <String>{};
    double totalRoleMin = 0;
    double totalRoleMax = 0;
    for (final Object? rawRole in roles) {
      final Map<String, Object?> role = _asMap(rawRole) ?? <String, Object?>{};
      final double? roleMin = advNumber(role['min']);
      final double? roleMax = advNumber(role['max']);
      if (advText(role['id']).isEmpty ||
          advText(role['label']).isEmpty ||
          roleIds.contains(advText(role['id']))) {
        return '多人角色 ID 和名称不能为空，且 ID 不能重复';
      }
      if (roleMin == null ||
          roleMax == null ||
          roleMin != roleMin.roundToDouble() ||
          roleMax != roleMax.roundToDouble() ||
          roleMin < 0 ||
          roleMax < 1 ||
          roleMin > roleMax ||
          roleMax > max) {
        return '多人角色人数范围不正确';
      }
      roleIds.add(advText(role['id']));
      totalRoleMin += roleMin;
      totalRoleMax += roleMax;
    }
    if (totalRoleMin > min || totalRoleMax < max) return '角色人数范围无法覆盖玩法人数';
    final List<Object?> turnOrder = _asList(mp['turnOrder']);
    if (turnOrder.isEmpty) return '多人玩法必须配置轮次顺序';
    if (turnOrder.any((id) => !roleIds.contains(advText(id)))) {
      return '轮次顺序引用了不存在的角色';
    }
    final double? requiredTurns = advNumber(mp['requiredTurns']);
    final double? unitScore = advNumber(mp['unitScore']);
    if (requiredTurns == null ||
        requiredTurns != requiredTurns.roundToDouble() ||
        requiredTurns < 1 ||
        requiredTurns > 1000) {
      return '多人玩法完成轮数须为 1 至 1000';
    }
    if (unitScore == null ||
        unitScore != unitScore.roundToDouble() ||
        unitScore < 0 ||
        unitScore > 100000) {
      return '多人玩法单轮得分须为 0 至 100000';
    }
    if (advText(mp['assignment']) == 'AUTO') {
      for (int playerCount = min.toInt(); playerCount <= max.toInt(); playerCount += 1) {
        final Map<String, int> assigned = <String, int>{};
        for (int i = 0; i < playerCount; i += 1) {
          final String id = advText(turnOrder[i % turnOrder.length]);
          assigned[id] = (assigned[id] ?? 0) + 1;
        }
        bool bad = false;
        for (final Object? rawRole in roles) {
          final Map<String, Object?> role = _asMap(rawRole) ?? <String, Object?>{};
          final int a = assigned[advText(role['id'])] ?? 0;
          if (a < (advNumber(role['min']) ?? 0) || a > (advNumber(role['max']) ?? 0)) {
            bad = true;
          }
        }
        if (bad) return '自动分配顺序无法覆盖全部允许人数';
      }
    }
  }

  final Map<String, Object?> timeWindow = sec('timeWindow');
  if (timeWindow['enabled'] == true) {
    if (!_clockPattern.hasMatch(_blankIf(timeWindow['openFrom'])) ||
        !_clockPattern.hasMatch(_blankIf(timeWindow['openTo']))) {
      return '开放时段须为 HH:mm 的 24 小时制';
    }
    if (_blankIf(timeWindow['openFrom']) == _blankIf(timeWindow['openTo'])) {
      return '开放时段的起止不能相同';
    }
    if (_blankIf(timeWindow['eyebrow']).length > 32) return '时段限定眉标不能超过 32 字';
    if (_blankIf(timeWindow['title']).length > 32) return '时段限定标题不能超过 32 字';
    if (_blankIf(timeWindow['subscribeTmplId']).length > 64) return '订阅消息模板 id 不能超过 64 字';
  }

  final Map<String, Object?> blindTaste = sec('blindTaste');
  if (blindTaste['enabled'] == true) {
    final String title = _blankIf(blindTaste['title']);
    if (title.isEmpty) return '盲品标题不能为空';
    if (title.length > 64) return '盲品标题不能超过 64 字';
    if (_blankIf(blindTaste['steps']).length > 120) return '盲品步骤说明不能超过 120 字';
    if (_blankIf(blindTaste['hint']).length > 60) return '盲品旁白不能超过 60 字';
    final List<Object?> options = _asList(blindTaste['options']);
    if (options.length < 2 || options.length > 6) return '盲品选项须为 2 至 6 项';
    final Set<String> keys = <String>{};
    for (final Object? rawOpt in options) {
      final Map<String, Object?> option = _asMap(rawOpt) ?? <String, Object?>{};
      final String key = _blankIf(option['key']);
      final String label = _blankIf(option['label']);
      if (!_keyPattern.hasMatch(key)) {
        return '盲品选项 key 只能使用 1 至 64 位字母、数字、下划线或短横线';
      }
      if (keys.contains(key)) return '盲品选项 key 不能重复';
      keys.add(key);
      if (label.isEmpty) return '盲品选项文案不能为空';
      if (label.length > 32) return '盲品选项文案不能超过 32 字';
    }
    final String answerKey = _blankIf(blindTaste['answerKey']);
    if (!(adopted && answerKey.isEmpty) && !keys.contains(answerKey)) {
      return '盲品正确答案必须是其中一个选项';
    }
    final double? xp = advNumber(blindTaste['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 1000) {
      return '盲品奖励分须为 0 至 1000';
    }
  }

  final Map<String, Object?> silentOrder = sec('silentOrder');
  if (silentOrder['enabled'] == true) {
    final String title = _blankIf(silentOrder['title']);
    if (title.isEmpty) return '沉默点单标题不能为空';
    if (title.length > 64) return '沉默点单标题不能超过 64 字';
    if (_blankIf(silentOrder['rule']).length > 200) return '沉默点单规则说明不能超过 200 字';
    final double? limit = advNumber(silentOrder['limitSeconds']);
    if (limit == null ||
        limit != limit.roundToDouble() ||
        (limit != 0 && (limit < 60 || limit > 3600))) {
      return '沉默点单时限须为 60 秒至 1 小时，或 0 表示不限时';
    }
  }

  final Map<String, Object?> diyName = sec('diyName');
  if (diyName['enabled'] == true) {
    final String title = _blankIf(diyName['title']);
    if (title.isEmpty) return '作品命名标题不能为空';
    if (title.length > 64) return '作品命名标题不能超过 64 字';
    final double? maxLength = advNumber(diyName['maxLength']);
    if (maxLength == null ||
        maxLength != maxLength.roundToDouble() ||
        maxLength < 2 ||
        maxLength > 40) {
      return '作品名长度上限须为 2 至 40 字';
    }
    final List<Object?> suggestions = _asList(diyName['suggestions']);
    if (suggestions.length > 6) return '作品名备选最多 6 个';
    for (final Object? item in suggestions) {
      final String value = _blankIf(item);
      if (value.isEmpty || value.length > maxLength) {
        return '作品名备选不能为空且不能超过名称长度上限';
      }
    }
  }

  final Map<String, Object?> musicCorner = sec('musicCorner');
  if (musicCorner['enabled'] == true) {
    final String title = _blankIf(musicCorner['title']);
    if (title.isEmpty) return '音乐角标题不能为空';
    if (title.length > 64) return '音乐角标题不能超过 64 字';
    if (_blankIf(musicCorner['trackName']).length > 40) return '曲目名不能超过 40 字';
    final String audioUrl = _blankIf(musicCorner['audioUrl']);
    if (audioUrl.isNotEmpty) {
      if (audioUrl.length > 512) return '曲目地址不能超过 512 字';
      final bool localPath = audioUrl.startsWith('/') &&
          !audioUrl.startsWith('//') &&
          !audioUrl.contains('\\');
      if (!localPath && !audioUrl.startsWith('https://')) {
        return '曲目地址必须是 https 链接或站内路径';
      }
    }
    final double? duration = advNumber(musicCorner['durationSeconds']);
    if (duration == null ||
        duration != duration.roundToDouble() ||
        (duration != 0 && (duration < 10 || duration > 3600))) {
      return '曲目时长须为 10 秒至 1 小时';
    }
  }

  final Map<String, Object?> steps = sec('steps');
  if (steps['enabled'] == true) {
    final double? goal = advNumber(steps['goal']);
    if (goal == null || goal != goal.roundToDouble() || goal < 100 || goal > 100000) {
      return '计步目标须为 100 至 100000 步';
    }
    if (_blankIf(steps['eyebrow']).length > 32) return '计步眉标不能超过 32 字';
    final double? xp = advNumber(steps['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 1000) {
      return '计步奖励分须为 0 至 1000';
    }
  }

  final Map<String, Object?> dailySign = sec('dailySign');
  if (dailySign['enabled'] == true) {
    final List<Object?> poems = _asList(dailySign['poems']);
    if (!(adopted && poems.isEmpty) && (poems.isEmpty || poems.length > 60)) {
      return '城市签签文须为 1 至 60 条';
    }
    for (final Object? rawPoem in poems) {
      final List<Object?> lines = rawPoem is List ? rawPoem : <Object?>[];
      if (lines.isEmpty || lines.length > 4) return '每条签文须为 1 至 4 行';
      for (final Object? line in lines) {
        final String value = _blankIf(line);
        if (value.isEmpty || value.length > 24) {
          return '签文每行不能为空且不能超过 24 字';
        }
      }
    }
    if (_blankIf(dailySign['signer']).length > 16) return '签文落款不能超过 16 字';
    if (_blankIf(dailySign['sealText']).length > 8) return '印文不能超过 8 字';
  }

  final Map<String, Object?> coin = sec('coinFlip');
  if (coin['enabled'] == true) {
    if (_blankIf(coin['kicker']).length > 32) return '抛硬币标题不能超过 32 字';
    for (final (String k, String cn) in <(String, String)>[
      ('heads', '正面'),
      ('tails', '反面'),
    ]) {
      final Map<String, Object?> f = _asMap(coin[k]) ?? <String, Object?>{};
      if (_blankIf(f['label']).length > 16) return '$cn名称不能超过 16 字';
      final String act = _blankIf(f['action']);
      if (act.isEmpty) return '$cn要做什么不能为空';
      if (act.length > 60) return '$cn要做什么不能超过 60 字';
    }
  }

  final Map<String, Object?> dice = sec('diceRoll');
  if (dice['enabled'] == true) {
    if (_blankIf(dice['kicker']).length > 32) return '掷骰子标题不能超过 32 字';
    final List<Object?> faces = _asList(dice['faces']);
    for (int i = 0; i < 6; i++) {
      final String v = i < faces.length ? _blankIf(faces[i]) : '';
      if (v.isEmpty) return '掷骰子第 ${i + 1} 面不能为空';
      if (v.length > 60) return '掷骰子第 ${i + 1} 面不能超过 60 字';
    }
  }

  final Map<String, Object?> react = sec('reaction');
  if (react['enabled'] == true) {
    if (_blankIf(react['kicker']).length > 32) return '变色就点标题不能超过 32 字';
    final double? rounds = advNumber(react['rounds']);
    if (rounds == null || rounds < 1 || rounds > 10) return '变色就点轮数须为 1 至 10';
    final double? goalMs = advNumber(react['goalMs']);
    if (goalMs == null || goalMs < 120 || goalMs > 2000) return '达标毫秒须为 120 至 2000';
  }

  final Map<String, Object?> ball = sec('ballShake');
  if (ball['enabled'] == true) {
    if (_blankIf(ball['kicker']).length > 32) return '弹球标题不能超过 32 字';
    final double? goal = advNumber(ball['goal']);
    if (goal == null || goal < 1 || goal > 200) return '弹球撞击次数须为 1 至 200';
    if (ball['timed'] == true) {
      final double? sec = advNumber(ball['seconds']);
      if (sec == null || sec < 3 || sec > 300) return '弹球限时须为 3 至 300 秒';
    }
  }

  final Map<String, Object?> quiet = sec('quietHold');
  if (quiet['enabled'] == true) {
    if (_blankIf(quiet['kicker']).length > 32) return '安静挑战标题不能超过 32 字';
    final double? sec = advNumber(quiet['seconds']);
    if (sec == null || sec < 5 || sec > 300) return '安静挑战时长须为 5 至 300 秒';
  }

  final Map<String, Object?> cdn = sec('countdown');
  if (cdn['enabled'] == true) {
    if (_blankIf(cdn['kicker']).length > 32) return '倒计时标题不能超过 32 字';
    final double? sec = advNumber(cdn['seconds']);
    if (sec == null || sec < 5 || sec > 3600) return '倒计时时长须为 5 至 3600 秒';
    final String done = _blankIf(cdn['doneText']);
    if (done.isEmpty) return '到点时说什么不能为空';
    if (done.length > 60) return '到点时说什么不能超过 60 字';
  }

  final Map<String, Object?> stop = sec('stopwatch');
  if (stop['enabled'] == true) {
    if (_blankIf(stop['kicker']).length > 32) return '精准停表标题不能超过 32 字';
    final double? target = advNumber(stop['targetSeconds']);
    if (target == null || target < 3 || target > 120) return '精准停表目标须为 3 至 120 秒';
    final double? tol = advNumber(stop['toleranceMs']);
    if (tol == null || tol < 50 || tol > 5000) return '精准停表容差须为 50 至 5000 毫秒';
    final double? tries = advNumber(stop['tries']);
    if (tries == null || tries < 0 || tries > 10) return '精准停表次数须为 0 至 10,0 表示不限';
  }

  final Map<String, Object?> estimate = sec('estimate');
  if (estimate['enabled'] == true) {
    final String title = _blankIf(estimate['title']);
    if (title.isEmpty) return '估数题干不能为空';
    if (title.length > 64) return '估数题干不能超过 64 字';
    if (_blankIf(estimate['unit']).length > 8) return '估数单位不能超过 8 字';
    if (_blankIf(estimate['reveal']).length > 200) return '估数揭示文案不能超过 200 字';
    final double? min = advNumber(estimate['min']);
    final double? max = advNumber(estimate['max']);
    final double? answer = advNumber(estimate['answer']);
    final double? tolerance = advNumber(estimate['tolerance']);
    final bool secretsStripped = adopted && answer == 0 && tolerance == 0;
    if (min == null || max == null) {
      return '估数的量程、答案与容差都必须是数字';
    }
    if (min >= max) return '估数量程的下限必须小于上限';
    if (max - min > 1000000) return '估数量程跨度不能超过 1000000';
    if (!secretsStripped) {
      if (answer == null || tolerance == null) {
        return '估数的量程、答案与容差都必须是数字';
      }
      if (answer < min || answer > max) return '估数答案必须落在量程之内';
      if (tolerance <= 0) return '估数容差必须大于 0';
      if (tolerance > (max - min) / 2) return '估数容差不能超过量程的一半';
    }
    final double? xp = advNumber(estimate['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 1000) {
      return '估数奖励分须为 0 至 1000';
    }
  }

  final Map<String, Object?> pricePair = sec('pricePair');
  if (pricePair['enabled'] == true) {
    final String title = _blankIf(pricePair['title']);
    if (title.isEmpty) return '猜图题目不能为空';
    if (title.length > 64) return '猜图题目不能超过 64 字';
    final List<Object?> items = _asList(pricePair['items']);
    if (items.length < 3 || items.length > 8) return '猜图的图片须为 3 至 8 张';
    final Set<String> ids = <String>{};
    int correct = 0;
    for (final Object? rawItem in items) {
      final Map<String, Object?> item = _asMap(rawItem) ?? <String, Object?>{};
      final String id = _blankIf(item['id']);
      if (!_keyPattern.hasMatch(id)) {
        return '猜图图片 id 只能使用 1 至 64 位字母、数字、下划线或短横线';
      }
      if (ids.contains(id)) return '猜图图片 id 不能重复';
      ids.add(id);
      final String name = _blankIf(item['name']);
      if (name.isEmpty) return '猜图图片说明不能为空';
      if (name.length > 32) return '猜图图片说明不能超过 32 字';
      final String imageUrl = _blankIf(item['imageUrl']);
      if (imageUrl.isNotEmpty) {
        if (imageUrl.length > 512) return '猜图图片地址不能超过 512 字';
        final bool localPath = imageUrl.startsWith('/') &&
            !imageUrl.startsWith('//') &&
            !imageUrl.contains('\\');
        if (!localPath && !imageUrl.startsWith('https://')) {
          return '猜图图片地址必须是 https 链接或站内路径';
        }
      }
      if (item['correct'] == true) correct += 1;
    }
    if (!adopted && correct != 1) return '猜图必须指定且只指定一张正确答案';
    final double? xp = advNumber(pricePair['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 200) {
      return '猜图答对的奖励分须为 0 至 200';
    }
    final double? maxTries = advNumber(pricePair['maxTries']);
    if (maxTries == null ||
        maxTries != maxTries.roundToDouble() ||
        maxTries < 0 ||
        maxTries > 10) {
      return '猜图可以猜几次须为 0 至 10,0 表示不限';
    }
  }

  final Map<String, Object?> qa = sec('qa');
  if (qa['enabled'] == true) {
    if (!<String>['TYPE', 'PICK', 'SHOT'].contains(qa['mode'])) {
      return '问答模式只能是打字、选项或拍照';
    }
    final String title = _blankIf(qa['title']);
    if (title.isEmpty) return '问答题干不能为空';
    if (title.length > 120) return '问答题干不能超过 120 字';
    if (_blankIf(qa['lead']).length > 60) return '问答前置说明不能超过 60 字';
    if (qa['mode'] == 'SHOT' && _blankIf(qa['lead']).isEmpty) {
      return '拍照打卡要写一句提示词,告诉玩家拍什么';
    }
    if (qa['mode'] == 'TYPE') {
      final String answer = _blankIf(qa['answerText']);
      if (!adopted && answer.isEmpty) return '打字问答必须填正确答案';
      if (answer.length > 200) return '问答答案不能超过 200 字';
    }
    if (qa['mode'] == 'PICK') {
      final List<Object?> options = _asList(qa['options']);
      if (options.length < 2 || options.length > 4) return '选项问答须为 2 至 4 个选项';
      final Set<String> ids = <String>{};
      int correct = 0;
      for (final Object? rawOpt in options) {
        final Map<String, Object?> option = _asMap(rawOpt) ?? <String, Object?>{};
        final String id = _blankIf(option['id']);
        if (!_keyPattern.hasMatch(id)) {
          return '问答选项 id 只能使用 1 至 64 位字母、数字、下划线或短横线';
        }
        if (ids.contains(id)) return '问答选项 id 不能重复';
        ids.add(id);
        final String label = _blankIf(option['label']);
        if (label.isEmpty) return '问答选项文案不能为空';
        if (label.length > 32) return '问答选项文案不能超过 32 字';
        if (_blankIf(option['fb']).length > 120) return '问答选项反馈不能超过 120 字';
        if (option['correct'] == true) correct += 1;
      }
      if (!adopted && correct != 1) return '选项问答必须指定且只指定一个正确答案';
    }
    final double? maxTries = advNumber(qa['maxTries']);
    if (maxTries == null ||
        maxTries != maxTries.roundToDouble() ||
        maxTries < 0 ||
        maxTries > 10) {
      return '问答可以答几次须为 0 至 10,0 表示不限';
    }
    final double? xp = advNumber(qa['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 200) {
      return '问答的奖励分须为 0 至 200';
    }
  }

  final Map<String, Object?> scan = sec('scan');
  if (scan['enabled'] == true) {
    if (!<String>['TEXT', 'VOICE', 'IMAGE'].contains(scan['kind'])) {
      return '扫码回复只能是文字、语音或图片';
    }
    final String reply = _blankIf(scan['reply']);
    if (reply.length > 200) return '扫码回复不能超过 200 字';
    if (scan['kind'] == 'TEXT' && reply.isEmpty) return '扫码回文字就得写一句话';
    if (scan['kind'] == 'VOICE' && _blankIf(scan['audioUrl']).isEmpty) {
      return '扫码回语音就得配一段语音';
    }
    if (scan['kind'] == 'IMAGE' && _blankIf(scan['imageUrl']).isEmpty) {
      return '扫码回图片就得配一张图';
    }
    final double? xp = advNumber(scan['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 200) {
      return '扫码的奖励分须为 0 至 200';
    }
  }

  final Map<String, Object?> hiddenObject = sec('hiddenObject');
  if (hiddenObject['enabled'] == true) {
    final String title = _blankIf(hiddenObject['title']);
    if (title.isEmpty) return '找东西标题不能为空';
    if (title.length > 64) return '找东西标题不能超过 64 字';
    if (_blankIf(hiddenObject['hint']).length > 60) return '找东西提示不能超过 60 字';
    final String imageUrl = _blankIf(hiddenObject['imageUrl']);
    if (imageUrl.isEmpty) return '找东西必须有一张图';
    if (imageUrl.length > 512) return '找东西图片地址不能超过 512 字';
    final bool localPath = imageUrl.startsWith('/') &&
        !imageUrl.startsWith('//') &&
        !imageUrl.contains('\\');
    if (!localPath && !imageUrl.startsWith('https://')) {
      return '找东西图片地址必须是 https 链接或站内路径';
    }
    final List<Object?> spots = _asList(hiddenObject['hotspots']);
    if (spots.length < 3 || spots.length > 5) return '找东西要标 3 至 5 个目标';
    final Set<String> ids = <String>{};
    final List<List<double>> placed = <List<double>>[];
    for (final Object? rawSpot in spots) {
      final Map<String, Object?> spot = _asMap(rawSpot) ?? <String, Object?>{};
      final String id = _blankIf(spot['id']);
      if (!_keyPattern.hasMatch(id)) {
        return '找东西目标 id 只能使用 1 至 64 位字母、数字、下划线或短横线';
      }
      if (ids.contains(id)) return '找东西目标 id 不能重复';
      ids.add(id);
      final String label = _blankIf(spot['label']);
      if (label.isEmpty) return '找东西目标名不能为空';
      if (label.length > 24) return '找东西目标名不能超过 24 字';
      final double? x = advNumber(spot['x']);
      final double? y = advNumber(spot['y']);
      final double? r = advNumber(spot['r']);
      if (adopted && x == null && y == null) continue;
      if (x == null || y == null || r == null) return '找东西目标的坐标与半径必须是数字';
      if (x < 0 || x > 1 || y < 0 || y > 1) return '找东西目标的坐标须为 0 到 1 之间的比例值';
      if (r < 0.03 || r > 0.15) return '找东西目标的半径须为 0.03 到 0.15 之间';
      for (final List<double> other in placed) {
        final double dx = x - other[0];
        final double dy = y - other[1];
        if (_sqrt(dx * dx + dy * dy) < r + other[2]) {
          return '找东西的两个目标挨得太近,请把它们分开一些';
        }
      }
      placed.add(<double>[x, y, r]);
    }
    final double? xp = advNumber(hiddenObject['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 1000) {
      return '找东西奖励分须为 0 至 1000';
    }
  }

  final Map<String, Object?> predict = sec('predict');
  if (predict['enabled'] == true) {
    final String question = _blankIf(predict['question']);
    if (question.isEmpty) return '竞猜问题不能为空';
    if (question.length > 120) return '竞猜问题不能超过 120 字';
    if (_blankIf(predict['hint']).length > 60) return '竞猜说明不能超过 60 字';
    final List<Object?> options = _asList(predict['options']);
    if (options.length < 2 || options.length > 4) return '竞猜选项须为 2 至 4 个';
    final Set<String> keys = <String>{};
    for (final Object? rawOpt in options) {
      final Map<String, Object?> option = _asMap(rawOpt) ?? <String, Object?>{};
      final String key = _blankIf(option['key']);
      if (!_keyPattern.hasMatch(key)) {
        return '竞猜选项 key 只能使用 1 至 64 位字母、数字、下划线或短横线';
      }
      if (keys.contains(key)) return '竞猜选项 key 不能重复';
      keys.add(key);
      final String label = _blankIf(option['label']);
      if (label.isEmpty) return '竞猜选项文案不能为空';
      if (label.length > 32) return '竞猜选项文案不能超过 32 字';
    }
    final double? closeAtHour = advNumber(predict['closeAtHour']);
    if (closeAtHour == null ||
        closeAtHour != closeAtHour.roundToDouble() ||
        closeAtHour < 0 ||
        closeAtHour > 23) {
      return '竞猜截止时间须为 0 到 23 点之间的整点';
    }
    final double? xp = advNumber(predict['xp']);
    if (xp == null || xp != xp.roundToDouble() || xp < 0 || xp > 1000) {
      return '竞猜奖励分须为 0 至 1000';
    }
  }

  return '';
}

double _sqrt(double v) {
  if (v <= 0) return 0;
  double x = v;
  double y = (x + 1) / 2;
  while ((y - x).abs() > 1e-12) {
    x = y;
    y = (x + v / x) / 2;
  }
  return x;
}

({Map<String, Object?> value, String error}) _normalizeAndCheck(
  Map<String, Object?>? model,
  AdvancedValidateOpts opts,
) {
  final Map<String, Object?> normalized = normalizeAdvancedConfig(model);
  final String error = validateAdvancedConfig(normalized, opts: opts);
  return (value: normalized, error: error);
}

/// 真源 `validate`:先 normalize 再校验,返回错误文案(空串 = 通过)。
String validateAdvancedConfigInput(
  Map<String, Object?>? model, {
  AdvancedValidateOpts opts = const AdvancedValidateOpts(),
}) {
  if (model == null) return '高级玩法配置版本不受支持';
  return _normalizeAndCheck(model, opts).error;
}

/// 真源 `serialize`:校验不过抛错;一段都没启用且无未知段返回空串,否则返回
/// 归一化后的 JSON(未启用的段也原样带上)。
String serializeAdvancedConfig(
  Map<String, Object?>? model, {
  AdvancedValidateOpts opts = const AdvancedValidateOpts(),
}) {
  final (value: normalized, error: error) = _normalizeAndCheck(model, opts);
  if (error.isNotEmpty) throw StateError(error);
  if (advEnabledSections(normalized).isEmpty &&
      advExtraKeys(normalized).isEmpty) {
    return '';
  }
  return jsonEncode(normalized);
}
