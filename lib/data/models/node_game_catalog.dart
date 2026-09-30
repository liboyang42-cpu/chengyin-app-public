/// 节点玩法目录 —— 创作端「选择玩法」那张单子。
///
/// ★ 结构 1:1 真源:`chengyinhub-xcx/utils/publish/node-game-catalog.js`。
///   一个节点**只选一个玩法,不叠加**(施工文档 §1.1):选中 = 打开它那一段
///   `enabled`、把其余玩法段一律关掉;`section` 必须是 [advanced_play_config.dart]
///   里的段名,`validationMethod` 决定节点怎么算通关(老链路仍在用)。
///   高级玩法卡里剩下的叠加型修饰段(计时/排行/多人/时段限定/盲品/沉默点单/
///   作品命名/音乐角/城市签)不在这张单子里,选玩法不碰它们。
library;

import 'advanced_play_config.dart';

class NodeGameItem {
  const NodeGameItem({
    required this.key,
    required this.label,
    required this.sub,
    required this.section,
    required this.validationMethod,
    this.mode = '',
    this.badge = '',
  });

  final String key;
  final String label;
  final String sub;

  /// 对应 [advanced_play_config.dart] 的段名;空串 = 该玩法不落在节点段(bingo 主题级)。
  final String section;

  /// qa 一段三种模式靠它区分(TYPE / PICK / SHOT)。
  final String mode;

  /// 选中这个玩法后写回 formData 的老链路通关判定。
  final int validationMethod;

  /// 角标(如「主题级」)。
  final String badge;
}

class NodeGameGroup {
  const NodeGameGroup({required this.title, required this.items});
  final String title;
  final List<NodeGameItem> items;
}

const List<NodeGameGroup> kNodeGameGroups = <NodeGameGroup>[
  NodeGameGroup(
    title: '问答类',
    items: <NodeGameItem>[
      NodeGameItem(
        key: 'qaText',
        label: '文字问答',
        sub: '出一道题，玩家打字作答',
        section: 'qa',
        mode: 'TYPE',
        validationMethod: 1,
      ),
      NodeGameItem(
        key: 'qaPick',
        label: '选项问答',
        sub: '2-4 个选项里选一个 · 闭眼盲品也是这套',
        section: 'qa',
        mode: 'PICK',
        validationMethod: 3,
      ),
      NodeGameItem(
        key: 'qaShot',
        label: '拍照打卡',
        sub: '给一句提示词，玩家拍一张交上来',
        section: 'qa',
        mode: 'SHOT',
        validationMethod: 2,
      ),
      NodeGameItem(
        key: 'branch',
        label: '分支剧情',
        sub: '界面和问答一样，只是选项决定下一段',
        section: 'branch',
        validationMethod: 0,
      ),
    ],
  ),
  NodeGameGroup(
    title: '互动类',
    items: <NodeGameItem>[
      NodeGameItem(
        key: 'estimate',
        label: '猜数字',
        sub: '猜一个数，按接近程度分档给分',
        section: 'estimate',
        validationMethod: 8,
      ),
      NodeGameItem(
        key: 'pricePair',
        label: '猜图',
        sub: '几张图里挑出正确的那张',
        section: 'pricePair',
        validationMethod: 9,
      ),
      NodeGameItem(
        key: 'hidden',
        label: '找东西',
        sub: '在你上传的图上点中藏起来的目标',
        section: 'hiddenObject',
        validationMethod: 10,
      ),
      NodeGameItem(
        key: 'predict',
        label: '竞猜',
        sub: '今天押一个，到期商家给答案',
        section: 'predict',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'random',
        label: '抽卡',
        sub: '一副卡池抽一张，翻开就是这一关的任务',
        section: 'random',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'bingo',
        label: '九宫格',
        sub: '走到一处点亮一格，连成线就换奖',
        section: '',
        validationMethod: 0,
        badge: '主题级',
      ),
    ],
  ),
  NodeGameGroup(
    title: '挑战类',
    items: <NodeGameItem>[
      NodeGameItem(
        key: 'steps',
        label: '计步挑战',
        sub: '只认服务端解密的微信运动步数',
        section: 'steps',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'react',
        label: '变色就点',
        sub: '屏幕一变色就点，比谁快',
        section: 'reaction',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'shake',
        label: '弹球',
        sub: '倾斜手机，让球撞够手机边缘的次数',
        section: 'ballShake',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'quiet',
        label: '安静挑战',
        sub: '一直安静到时间到，响一下从头再来',
        section: 'quietHold',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'countdown',
        label: '倒计时',
        sub: '一钟油，时间走它就退',
        section: 'countdown',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'stopwatch',
        label: '精准停表',
        sub: '盲停在目标秒数上，差多少算多少',
        section: 'stopwatch',
        validationMethod: 0,
      ),
    ],
  ),
  NodeGameGroup(
    title: '决定类',
    items: <NodeGameItem>[
      NodeGameItem(
        key: 'coin',
        label: '抛硬币',
        sub: '正反面各配一句，抛完照做',
        section: 'coinFlip',
        validationMethod: 0,
      ),
      NodeGameItem(
        key: 'dice',
        label: '掷骰子',
        sub: '掷到几就做第几件事',
        section: 'diceRoll',
        validationMethod: 0,
      ),
    ],
  ),
  NodeGameGroup(
    title: '营销类',
    items: <NodeGameItem>[
      NodeGameItem(
        key: 'scan',
        label: '扫码参与',
        sub: '扫完立刻回一条 —— 文字 / 语音 / 图片',
        section: 'scan',
        validationMethod: 4,
      ),
    ],
  ),
];

List<NodeGameItem> get kNodeGameAll =>
    kNodeGameGroups.expand((g) => g.items).toList(growable: false);

/// 会真的执行「限时」的玩法(施工文档 §1.4)。计步/竞猜/抽卡/硬币/骰子/扫码/九宫格
/// 没有可限的东西。
const List<String> kTimedGames = <String>[
  'qaText',
  'qaPick',
  'qaShot',
  'branch',
  'estimate',
  'pricePair',
  'hidden',
  'react',
  'shake',
  'quiet',
  'countdown',
  'stopwatch',
];

/// 这个玩法支不支持限时。没选玩法时返回 true(旧模板那条老链路照旧)。
bool advSupportsTimer(String? key) {
  if (key == null || key.isEmpty) return true;
  return kTimedGames.contains(key);
}

/// 所有被这十九个玩法占用的段名(去重)。选一个玩法 = 关掉其余这些段。
final List<String> kGameSections = kNodeGameAll
    .map((i) => i.section)
    .where((s) => s.isNotEmpty)
    .toSet()
    .toList(growable: false);

NodeGameItem? advFindGame(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final item in kNodeGameAll) {
    if (item.key == key) return item;
  }
  return null;
}

/// 从已有的 advanced 配置反推当前选中的玩法。编辑一份旧模板时靠它把槽位填回去。
String advDetectGame(Map<String, Object?>? advanced) {
  if (advanced == null) return '';
  for (final item in kNodeGameAll) {
    if (item.section.isEmpty) continue;
    final Object? raw = advanced[item.section];
    if (raw is! Map) continue;
    if (raw['enabled'] != true) continue;
    if (item.mode.isNotEmpty && '${raw['mode'] ?? ''}' != item.mode) continue;
    return item.key;
  }
  return '';
}

/// 返回「假如选了它」的那份配置(新对象):打开选中玩法那段、关掉其余玩法段、
/// 需要时写入 mode。不改传进来的配置。
///
/// ⚠️ 真选中时**不铺样例**(demo=false)—— 那会把样例当成商家填的存进去。
Map<String, Object?>? advApplyToConfig(Map<String, Object?>? advanced, String? key) {
  final NodeGameItem? game = advFindGame(key);
  if (game == null || advanced == null) return null;
  final Map<String, Object?> next = advClone(advanced);
  for (final String name in kGameSections) {
    final Object? raw = next[name];
    if (raw is! Map) continue;
    raw['enabled'] = game.section.isNotEmpty && name == game.section;
  }
  if (game.mode.isNotEmpty && next[game.section] is Map) {
    (next[game.section] as Map)['mode'] = game.mode;
  }
  return next;
}
