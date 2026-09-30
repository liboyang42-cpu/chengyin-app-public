import 'dart:convert';
import 'dart:math';

/// 《预制人生》故事引擎 —— 小程序 `subpackagePrefab/story-engine.js` 的 1:1 移植。
///
/// ★ 纯函数 + 不可变状态:每个动作返回新 `PrefabState`,和 js 版一样,
///   这样场景计时器/存档/测试都只依赖数据,不依赖 widget。
const List<String> kPrefabScenes = <String>[
  'prologue',
  'register',
  'boot',
  'walk',
  'hall',
  'birth',
  'dream1',
  'learning',
  'dream2',
  'career',
  'work',
  'dream3',
  'flow',
];

class PrefabProfile {
  const PrefabProfile({
    this.name = '',
    this.place = '',
    this.gender = '',
    this.dream = '',
    this.avatar = '',
  });

  final String name;
  final String place;
  final String gender;
  final String dream;
  final String avatar;

  PrefabProfile copyWith({
    String? name,
    String? place,
    String? gender,
    String? dream,
    String? avatar,
  }) => PrefabProfile(
    name: name ?? this.name,
    place: place ?? this.place,
    gender: gender ?? this.gender,
    dream: dream ?? this.dream,
    avatar: avatar ?? this.avatar,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'place': place,
    'gender': gender,
    'dream': dream,
    'avatar': avatar,
  };

  factory PrefabProfile.fromJson(Map<String, dynamic> json) => PrefabProfile(
    name: '${json['name'] ?? ''}',
    place: '${json['place'] ?? ''}',
    gender: '${json['gender'] ?? ''}',
    dream: '${json['dream'] ?? ''}',
    avatar: '${json['avatar'] ?? ''}',
  );
}

class PrefabObservation {
  const PrefabObservation({required this.where, required this.text});

  final String where;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'where': where,
    'text': text,
  };

  factory PrefabObservation.fromJson(Map<String, dynamic> json) =>
      PrefabObservation(
        where: '${json['where'] ?? ''}',
        text: '${json['text'] ?? ''}',
      );
}

class PrefabSticker {
  const PrefabSticker({required this.label, required this.x, required this.y});

  final String label;
  final double x;
  final double y;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    'x': x,
    'y': y,
  };

  factory PrefabSticker.fromJson(Map<String, dynamic> json) => PrefabSticker(
    label: '${json['label'] ?? ''}',
    x: (json['x'] as num?)?.toDouble() ?? 150,
    y: (json['y'] as num?)?.toDouble() ?? 388,
  );
}

class PrefabCheckResult {
  const PrefabCheckResult({
    required this.dice,
    required this.roll,
    required this.score,
    required this.dc,
    required this.ok,
  });

  final List<int> dice;
  final int roll;
  final int score;
  final int dc;
  final bool ok;
}

/// `story.gain(state, {hp, luck, dreams, thought})` 的那张变更单。
class PrefabGain {
  const PrefabGain({this.hp = 0, this.luck = 0, this.dreams = 0, this.thought});

  final int hp;
  final int luck;
  final int dreams;
  final String? thought;
}

class PrefabState {
  const PrefabState({
    this.scene = 'prologue',
    this.step = 0,
    this.profile = const PrefabProfile(),
    this.hp = 10,
    this.luck = 2,
    this.skills = const <String, int>{
      'rule': 2,
      'window': 2,
      'heart': 2,
      'precision': 1,
    },
    this.instability = 0,
    this.walkProgress = 0,
    this.dreams = 0,
    this.thoughts = const <String>[],
    this.observations = const <PrefabObservation>[],
    this.picks = const <String, Object?>{},
    this.photos = const <String, String>{},
    this.note = '',
    this.sticker,
    this.job = '',
    this.synced = false,
  });

  final String scene;
  final int step;
  final PrefabProfile profile;
  final int hp;
  final int luck;
  final Map<String, int> skills;
  final int instability;
  final int walkProgress;
  final int dreams;
  final List<String> thoughts;
  final List<PrefabObservation> observations;
  final Map<String, Object?> picks;
  final Map<String, String> photos;
  final String note;
  final PrefabSticker? sticker;
  final String job;
  final bool synced;

  bool get isDream => scene.startsWith('dream');

  /// `story.advance`:末幕(flow)原地返回,和 js 版一致。
  PrefabState advance() {
    final int current = kPrefabScenes.indexOf(scene);
    if (current < 0 || current == kPrefabScenes.length - 1) return this;
    return copyWith(
      scene: kPrefabScenes[current + 1],
      step: 0,
      resetStep: true,
    );
  }

  PrefabState copyWith({
    String? scene,
    int? step,
    PrefabProfile? profile,
    int? hp,
    int? luck,
    Map<String, int>? skills,
    int? instability,
    int? walkProgress,
    int? dreams,
    List<String>? thoughts,
    List<PrefabObservation>? observations,
    Map<String, Object?>? picks,
    Map<String, String>? photos,
    String? note,
    PrefabSticker? sticker,
    bool clearSticker = false,
    String? job,
    bool? synced,
    bool resetStep = false,
  }) => PrefabState(
    scene: scene ?? this.scene,
    step: resetStep ? 0 : (step ?? this.step),
    profile: profile ?? this.profile,
    hp: hp ?? this.hp,
    luck: luck ?? this.luck,
    skills: skills ?? this.skills,
    instability: instability ?? this.instability,
    walkProgress: walkProgress ?? this.walkProgress,
    dreams: dreams ?? this.dreams,
    thoughts: thoughts ?? this.thoughts,
    observations: observations ?? this.observations,
    picks: picks ?? this.picks,
    photos: photos ?? this.photos,
    note: note ?? this.note,
    sticker: clearSticker ? null : (sticker ?? this.sticker),
    job: job ?? this.job,
    synced: synced ?? this.synced,
  );

  /// `story.setStep`:负数按 0。
  PrefabState withStep(num value) => copyWith(step: max(0, value.toInt()));

  PrefabState choose(String key, Object? value) =>
      copyWith(picks: <String, Object?>{...picks, key: value});

  PrefabState withPhoto(String key, String value) =>
      copyWith(photos: <String, String>{...photos, key: value});

  /// `story.observe`:空文本、重复文本都不进台账。
  PrefabState observe(String where, String text) {
    final String value = text.trim();
    if (value.isEmpty ||
        observations.any((PrefabObservation o) => o.text == value)) {
      return this;
    }
    return copyWith(
      observations: <PrefabObservation>[
        ...observations,
        PrefabObservation(where: where, text: value),
      ],
    );
  }

  /// `story.applyProfile`:出生地/梦想的措辞各自加一点技能,登记完成时结算。
  PrefabState applyProfile(PrefabProfile incoming) {
    final PrefabProfile value = incoming;
    final String placeSkill = _classify(value.place, <(RegExp, String)>[
      (RegExp(r'想不起|不记得|不知道|忘'), 'precision'),
      (RegExp(r'县|镇|村|乡|山|海边'), 'window'),
      (RegExp(r'上海|北京|广州|深圳|市|城'), 'rule'),
    ], 'window');
    final String dreamSkill = _classify(value.dream, <(RegExp, String)>[
      (RegExp(r'宇航|科学|侦探|工程|程序|研究|天文|数学|机器|发明|电脑'), 'precision'),
      (RegExp(r'画|作家|写|音乐|歌|演|导演|诗|摄影|设计|跳舞'), 'heart'),
      (RegExp(r'医生|老师|警察|律师|第一|公务员|军|会计|老板|法官'), 'rule'),
      (RegExp(r'旅行|环游|酒吧|自由|流浪|远方|海|山|不知道|没想|很远'), 'window'),
    ], 'heart');
    final Map<String, int> nextSkills = <String, int>{...skills};
    nextSkills[placeSkill] = (nextSkills[placeSkill] ?? 0) + 1;
    nextSkills[dreamSkill] = (nextSkills[dreamSkill] ?? 0) + 1;
    return copyWith(profile: value, skills: nextSkills);
  }

  /// `story.check`:两颗 1..6 骰 + 技能 ≥ 难度。rolls 只取前两个。
  PrefabCheckResult check(String skill, int dc, List<int> rolls) {
    final List<int> dice = <int>[
      for (final int value in rolls.take(2)) max(1, min(6, value)),
    ];
    while (dice.length < 2) {
      dice.add(1);
    }
    final int roll = dice[0] + dice[1];
    final int score = roll + (skills[skill] ?? 0);
    return PrefabCheckResult(
      dice: dice,
      roll: roll,
      score: score,
      dc: dc,
      ok: score >= dc,
    );
  }

  /// `story.gain`:精力 0..10、幸运 0..4、梦不为负;念头去重。
  PrefabState gain(PrefabGain change) {
    final String? thought = change.thought;
    return copyWith(
      hp: max(0, min(10, hp + change.hp)),
      luck: max(0, min(4, luck + change.luck)),
      dreams: max(0, dreams + change.dreams),
      thoughts:
          thought != null && thought.isNotEmpty && !thoughts.contains(thought)
          ? <String>[...thoughts, thought]
          : thoughts,
    );
  }

  int get photoCount =>
      photos.values.where((String value) => value.isNotEmpty).length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 2,
    'scene': scene,
    'step': step,
    'profile': profile.toJson(),
    'hp': hp,
    'luck': luck,
    'skills': skills,
    'instability': instability,
    'walkProgress': walkProgress,
    'dreams': dreams,
    'thoughts': thoughts,
    'observations': observations
        .map((PrefabObservation o) => o.toJson())
        .toList(),
    'picks': picks,
    'photos': photos,
    'note': note,
    'sticker': sticker?.toJson(),
    'job': job,
    'synced': synced,
  };

  String save() => jsonEncode(toJson());

  /// `story.restore`:坏档/未知版本一律回初状态;v1 存档合进 v2 但 step 归零。
  static PrefabState restore(Object? raw) {
    try {
      final Object? value = raw is String ? jsonDecode(raw) : raw;
      if (value is! Map<String, dynamic>) return const PrefabState();
      if (!kPrefabScenes.contains('${value['scene'] ?? ''}')) {
        return const PrefabState();
      }
      final Object? version = value['version'];
      if (version != 1 && version != 2) return const PrefabState();
      final PrefabState merged = PrefabState._fromJsonShape(value);
      return version == 1 ? merged.copyWith(step: 0) : merged;
    } catch (_) {
      return const PrefabState();
    }
  }

  static PrefabState _fromJsonShape(Map<String, dynamic> json) {
    const PrefabState base = PrefabState();
    final Object? profile = json['profile'];
    final Object? skills = json['skills'];
    final Object? thoughts = json['thoughts'];
    final Object? observations = json['observations'];
    final Object? picks = json['picks'];
    final Object? photos = json['photos'];
    final Object? sticker = json['sticker'];
    final Map<String, int> nextSkills = <String, int>{...base.skills};
    if (skills is Map) {
      for (final Object? key in skills.keys) {
        final Object? value = skills[key];
        if (value is num) nextSkills['$key'] = value.toInt();
      }
    }
    return PrefabState(
      scene: '${json['scene'] ?? base.scene}',
      step: (json['step'] as num?)?.toInt() ?? base.step,
      profile: profile is Map<String, dynamic>
          ? PrefabProfile.fromJson(profile)
          : base.profile,
      hp: (json['hp'] as num?)?.toInt() ?? base.hp,
      luck: (json['luck'] as num?)?.toInt() ?? base.luck,
      skills: nextSkills,
      instability: (json['instability'] as num?)?.toInt() ?? base.instability,
      walkProgress:
          (json['walkProgress'] as num?)?.toInt() ?? base.walkProgress,
      dreams: (json['dreams'] as num?)?.toInt() ?? base.dreams,
      thoughts: thoughts is List
          ? thoughts.map((Object? e) => '$e').toList(growable: false)
          : base.thoughts,
      observations: observations is List
          ? observations
                .whereType<Map<String, dynamic>>()
                .map(PrefabObservation.fromJson)
                .toList(growable: false)
          : base.observations,
      picks: picks is Map
          ? <String, Object?>{
              for (final Object? key in picks.keys) '$key': picks[key],
            }
          : base.picks,
      photos: photos is Map
          ? <String, String>{
              for (final Object? key in photos.keys)
                '$key': '${photos[key] ?? ''}',
            }
          : base.photos,
      note: '${json['note'] ?? base.note}',
      sticker: sticker is Map<String, dynamic>
          ? PrefabSticker.fromJson(sticker)
          : null,
      job: '${json['job'] ?? base.job}',
      synced: json['synced'] == true,
    );
  }
}

String _classify(String text, List<(RegExp, String)> groups, String fallback) {
  for (final (RegExp pattern, String skill) in groups) {
    if (pattern.hasMatch(text)) return skill;
  }
  return fallback;
}

/// `asset(name)`:贴图素材随包(App 侧打进 assets/prefab,路径与 js 版一一对应)。
String prefabAsset(String name) => 'assets/prefab/$name.webp';

class PrefabJob {
  const PrefabJob({
    required this.name,
    required this.sub,
    required this.id,
    required this.desk,
    required this.task,
    required this.ignored,
  });

  final String name;
  final String sub;
  final String id;
  final String desk;
  final String task;
  final String ignored;

  String get image => 'j_$id';
}

/// `JOBS` 表逐字。
const List<PrefabJob> kPrefabJobs = <PrefabJob>[
  PrefabJob(
    name: '设计师',
    sub: '把东西做得好看',
    id: 'designer',
    desk: '一块数位板，两块屏幕',
    task: '把这个方案改得高大上一点。',
    ignored: '方案没有被否定。只是——不被采用。',
  ),
  PrefabJob(
    name: '程序员',
    sub: '让机器听懂人话',
    id: 'coder',
    desk: '一台装好环境的电脑，键盘上还留着上一个人的指纹',
    task: '这个需求今天上线。',
    ignored: '你写的代码被回滚了。群里没有人说为什么。',
  ),
  PrefabJob(
    name: '医生',
    sub: '把人治好',
    id: 'doctor',
    desk: '一间诊室，门口的号已经排满',
    task: '下一位。',
    ignored: '你写的会诊意见，被主任划掉了一行。',
  ),
  PrefabJob(
    name: '老师',
    sub: '站到讲台上',
    id: 'teacher',
    desk: '一张讲台，和一排比记忆里更小的桌子',
    task: '这周把进度赶上。',
    ignored: '你设计的那节课，被换回了标准教案。',
  ),
  PrefabJob(
    name: '销售',
    sub: '让人点头',
    id: 'sales',
    desk: '一部电话，和一张打满勾的客户名单',
    task: '回复那个客户，要客气，但要拒绝他。',
    ignored: '客户选了报价更高的那家。',
  ),
  PrefabJob(
    name: '会计',
    sub: '让数字对上',
    id: 'accountant',
    desk: '一张表格。横轴是时间，纵轴是指标',
    task: '整理这周的数据。',
    ignored: '你指出的那处数字，再也没有人问起。',
  ),
];

/// 工位图映射:真源 `_sync()` 里那张表只认这五个职业,其余落设计师。
String prefabJobImage(String job) {
  const Map<String, String> suffix = <String, String>{
    '程序员': 'coder',
    '医生': 'doctor',
    '老师': 'teacher',
    '销售': 'sales',
    '会计': 'accountant',
  };
  return 'j_${suffix[job] ?? 'designer'}';
}

const List<List<String>> kPrefabBootRows = <List<String>>[
  <String>['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  <String>['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  <String>['z', 'x', 'c', 'v', 'b', 'n', 'm'],
];
const String kPrefabBootTarget = 'hello world';

/// `ENDINGS` 表逐字:名称 / 台词 / 达成口径 / 占比。
const List<List<String>> kPrefabEndings = <List<String>>[
  <String>['标准版本', '“你看，我现在站得直直的，双手贴在裤缝边。”', '什么都没有偏离。你过完了被安排好的一生。', '41%'],
  <String>['交接', '“接手的是一个更年轻的你。他站得比你更直。”', '在第三章之后，“咔哒”了很多次。', '17%'],
  <String>['边界', '“世界允许你存在，却不会完全接纳你。”', '你靠近过很多次。但没有推开最后那道边界。', '19%'],
  <String>['共处', '“他无所住，生其心。”', '看见足够多的人，读完所有的梦。然后选择留下。', '12%'],
  <String>['出走', '“你看。我现在站得直直的。”——然后它走出了屏幕。', '推开最后那道边界。也需要你真的看过这座城市。', '6%'],
  <String>['回收', '“V1.9 · 开始吧。”', '推开了边界，但没有人记得你。', '5%'],
];

class PrefabMapNote {
  const PrefabMapNote({
    required this.id,
    required this.who,
    required this.text,
    required this.likes,
    this.liked = false,
  });

  final String id;
  final String who;
  final String text;
  final int likes;
  final bool liked;

  PrefabMapNote like() => liked
      ? this
      : PrefabMapNote(
          id: id,
          who: who,
          text: text,
          likes: likes + 1,
          liked: true,
        );
}

const List<PrefabMapNote> kPrefabMapNotes = <PrefabMapNote>[
  PrefabMapNote(id: 'sunny', who: '晴', text: '一个老人在等公交，等了很久。', likes: 23),
  PrefabMapNote(id: 'k', who: 'K', text: '玻璃门上映着我自己。', likes: 41),
];

class PrefabSceneMeta {
  const PrefabSceneMeta(this.kicker, this.title, this.cosmos);

  final String kicker;
  final String title;
  final String cosmos;
}

/// `_sceneMeta` 表逐字。
const Map<String, PrefabSceneMeta> kPrefabSceneMeta = <String, PrefabSceneMeta>{
  'prologue': PrefabSceneMeta('预制人生 · 序章', '开始吧', '无'),
  'register': PrefabSceneMeta('新生儿登记', '我问，你答。', '醒来'),
  'boot': PrefabSceneMeta('系统启动', 'hello world', '醒来'),
  'walk': PrefabSceneMeta('第 1 站', '去看一座被缩小的城市', '城市'),
  'hall': PrefabSceneMeta('在现场', '拍下展示馆的招牌', '城市'),
  'birth': PrefabSceneMeta('01 出生', '被确认的幸运', '午后'),
  'dream1': PrefabSceneMeta('第一个梦', '信息不断输入，我开始做梦。', '午后'),
  'learning': PrefabSceneMeta('02 学习', '标准答案', '粉笔灰'),
  'dream2': PrefabSceneMeta('第二个梦', '门更多了。', '静止'),
  'career': PrefabSceneMeta('好像只是眨了一下眼', '长大了，你希望做什么？', '眨眼'),
  'work': PrefabSceneMeta('03 工作', '被安排好的位置', '日光灯'),
  'dream3': PrefabSceneMeta('第三个梦', '不再是画面。是三个问题。', '无'),
  'flow': PrefabSceneMeta('原型到这里 · 1 / 4', '你走过的路，和别人走过的路', '无'),
};

class PrefabDreamCard {
  const PrefabDreamCard(this.text, this.src);

  final String text;
  final String src;
}

/// `dreamCards(scene, state)`:用户拍过的窗/手机/头像会顶进梦里。
List<PrefabDreamCard> prefabDreamCards(String scene, PrefabState state) {
  final String userWindow = state.photos['window'] ?? prefabAsset('win');
  final String userPhone = state.photos['phone'] ?? prefabAsset('phone');
  final String avatar = state.profile.avatar.isEmpty
      ? prefabAsset('corridor')
      : state.profile.avatar;
  String srcOf(String nameOrUrl) =>
      nameOrUrl.startsWith('http') ||
          nameOrUrl.startsWith('wxfile') ||
          nameOrUrl.startsWith('/') ||
          nameOrUrl.startsWith('file:') ||
          nameOrUrl.startsWith('assets/')
      ? nameOrUrl
      : prefabAsset(nameOrUrl);
  List<PrefabDreamCard> build(List<(String, String)> rows) => <PrefabDreamCard>[
    for (final (String text, String src) in rows)
      PrefabDreamCard(text, srcOf(src)),
  ];

  if (scene == 'dream1') {
    return build(<(String, String)>[
      ('梦里的我在一条无尽的白色走廊，两边是一扇又一扇的门。', 'corridor'),
      ('我看到宇宙微波辐射的噪声图。', 'cosmic'),
      ('恒星坍缩，行星偏移轨道。', 'orbit'),
      ('看到恐龙灭绝的化石记录。', 'fossil'),
      ('金字塔开始建造，奴隶名单，工期延误。', 'pyramid'),
      ('我看到列宁格勒。', 'leningrad'),
      ('我看到原子弹试爆的光。', 'flash'),
      ('我看到贝多芬的乐谱，一遍一遍被转录……', 'score'),
      ('最后一扇门后面，是今天下午你自己看过的那个窗外。', userWindow),
      ('信息不断输入，我开始做梦。', 'corridor'),
    ]);
  }
  if (scene == 'dream2') {
    return build(<(String, String)>[
      ('我看到地球形成，水覆盖表面。', 'ocean'),
      ('单细胞分裂，没有目的，只是重复。', 'cells'),
      ('语言分化，同一个意思被反复误解。', 'script'),
      ('边界被画在地图上，线条越来越粗。', 'map'),
      ('征兵名单，年龄集中在十八到二十五。', 'soldiers'),
      ('法庭判决，有人站起，有人坐下。', 'court'),
      ('工厂流水线，动作被标准化。', 'factory'),
      ('家庭录像带，生日、婚礼、一次次重拍。', 'vhs'),
      ('我又一次穿过那扇窗。', userWindow),
      ('聊天记录，已读未回。', 'chat'),
      ('搜索关键词：如何成功，如何变瘦，如何不痛苦。', 'search'),
      ('心率监测曲线，在凌晨三点突然升高。', 'heart'),
    ]);
  }
  if (scene == 'dream3') {
    return build(<(String, String)>[
      ('意义是什么？', userWindow),
      ('爱是否真实？', userPhone),
      ('我会被记住吗？', avatar),
      ('没有人回答。走廊尽头的那扇门，今天是开着的。', 'corridor'),
    ]);
  }
  return const <PrefabDreamCard>[];
}

/// 入口判定,真源 `pages/play/index.js:62` 的 `isPrefabLifeTopic` 逐字。
final RegExp _prefabTopicPattern = RegExp(r'^预制人生(?:\s*·.*)?$');
bool isPrefabLifeTopic(String? name) =>
    _prefabTopicPattern.hasMatch((name ?? '').trim());

/// 存档 key,真源 `prefab_life_v1_<activityId|topicId|preview>`。
String prefabStorageKey({int? activityId, int? topicId}) =>
    'prefab_life_v1_${activityId ?? topicId ?? 'preview'}';

Random _diceRandom = Random();

/// 测试注入骰子源;生产就是 [Random]。
void prefabSetDiceRandom(Random random) => _diceRandom = random;

List<int> prefabRollTwo() => <int>[
  _diceRandom.nextInt(6) + 1,
  _diceRandom.nextInt(6) + 1,
];
