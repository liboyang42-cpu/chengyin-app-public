/// 专业发布编辑器的纯逻辑层(对齐小程序 utils/publish/pro-editor-policy.js /
/// pro-editor-story.js / publish-ticket-schedule.js / publish-datetime.js)。
///
/// ★ 全部为纯函数:无 Flutter、无网络、无副作用,可直接单测。
///   页面只消费返回值做 UI 决策,不复制这里的判据。
///
/// ⚠️ 与后端硬约束对齐(读 CmsTopicServiceImpl 确认):
///   自由探索(productType=2)**必须**有 recruitDeadline,否则 create/update 直接抛
///   「自由探索主题必须设置招募截止时间」—— 这条是必填,不是「开了商家开关才必填」。
library;

import '../../data/models/publish_draft.dart';

/// 历史脏值:旧版会给空剧情写「暂无描述」凑完成态,按值排除。
const List<String> _fakeStoryValues = <String>['暂无描述', '暂无', '无'];

String textOf(Object? v) => (v ?? '').toString().trim();

/// 「没有值」与「值是 0/空串」的分界:
/// 坐标 '0' 是后端/POI 返回的常见空值,不能当有效坐标。
bool hasUsableCoords(PublishNode node) {
  final lng = textOf(node.longitude);
  final lat = textOf(node.latitude);
  if (lng.isEmpty || lat.isEmpty || lng == '0' || lat == '0') return false;
  final lngNumber = double.tryParse(lng);
  final latNumber = double.tryParse(lat);
  if (lngNumber == null || latNumber == null) return false;
  return lngNumber != 0 &&
      latNumber != 0 &&
      lngNumber >= -180 &&
      lngNumber <= 180 &&
      latNumber >= -90 &&
      latNumber <= 90;
}

/// 剧情是否真的写了(空白与占位文案都不算)。
/// 有 blocks(城市定向)时只投影第一个节点块之前的文字块;否则读 description。
bool hasRealStory(PublishChapter chapter) {
  String story;
  final blocks = chapter.blocks;
  if (blocks != null) {
    final projected = <String>[];
    for (final block in blocks) {
      if (block.type == 'node') break;
      if (block.type == 'text') projected.add(block.content);
    }
    story = textOf(projected.join('\n'));
  } else {
    story = textOf(chapter.description);
  }
  if (story.isEmpty) return false;
  return !_fakeStoryValues.contains(story);
}

/// 创建正式节点的即时剧情闸:城市定向没写剧情不许建节点(领域依赖,
/// 必须在点「创建节点」当场执行,不能拖到发布才告知)。null = 放行。
String? formalNodeCreationIssue(PublishDraft draft, int chapterIndex) {
  if (chapterIndex < 0 || chapterIndex >= draft.chapters.length) {
    return '未找到目标章节';
  }
  final chapter = draft.chapters[chapterIndex];
  if (draft.productType == kProductCity && !hasRealStory(chapter)) {
    return '城市定向需先完成本章剧情';
  }
  return null;
}

bool hasGameplay(PublishNode node) {
  if ((node.templateId ?? 0) > 0) return true;
  final t = node.templateInfo['title'];
  return t != null && t.toString().trim().isNotEmpty;
}

/// 默认创作起点。俱乐部入口优先 —— 从俱乐部发起的团手上先有的是地点。
String defaultAnchorFor(int productType, int? clubId) {
  if (clubId != null) return 'place';
  return productType == kProductCity ? 'story' : 'node';
}

StarterAction starterActionFor(String anchor) {
  switch (anchor) {
    case 'story':
      return const StarterAction(key: 'createChapter', label: '写第一章');
    case 'place':
      return const StarterAction(key: 'pickFirstPlace', label: '添加第一个地点');
    default:
      return const StarterAction(key: 'createNode', label: '添加第一个探索节点');
  }
}

class StarterAction {
  const StarterAction({required this.key, required this.label});
  final String key;
  final String label;
}

class ChapterState {
  const ChapterState({
    required this.index,
    required this.name,
    required this.storyDone,
    required this.storyRequired,
    required this.nodeCount,
    required this.nodesMissingCoords,
    required this.gameplayConfigured,
    required this.gameplayPending,
    required this.canAddNode,
  });

  final int index;
  final String name;
  final bool storyDone;
  final bool storyRequired;
  final int nodeCount;
  final int nodesMissingCoords;
  final int gameplayConfigured;

  /// 标签只在「还没配齐」时出现;配齐了就是噪音。
  final bool gameplayPending;

  /// 城市定向的领域依赖:没剧情不许建节点。
  final bool canAddNode;
}

List<ChapterState> chapterStatesOf(PublishDraft draft) {
  final isCity = draft.productType == kProductCity;
  return draft.chapters.map((chapter) {
    final index = draft.chapters.indexOf(chapter);
    final nodes = chapter.nodes;
    final storyDone = hasRealStory(chapter);
    final missingCoords = nodes.where((n) => !hasUsableCoords(n)).length;
    final gameplayConfigured = nodes.where(hasGameplay).length;
    return ChapterState(
      index: index,
      name: textOf(chapter.name).isEmpty
          ? '第${index + 1}章'
          : textOf(chapter.name),
      storyDone: storyDone,
      storyRequired: isCity,
      nodeCount: nodes.length,
      nodesMissingCoords: missingCoords,
      gameplayConfigured: gameplayConfigured,
      gameplayPending: nodes.isNotEmpty && gameplayConfigured < nodes.length,
      canAddNode: !isCity || storyDone,
    );
  }).toList();
}

bool isBlankDraft(PublishDraft draft) {
  final hasChapterContent = draft.chapters.any((c) {
    if (hasRealStory(c)) return true;
    return c.nodes.isNotEmpty;
  });
  return !hasChapterContent;
}

class BlockingIssue {
  const BlockingIssue({
    required this.key,
    required this.message,
    this.chapterIndex,
    this.nodeIndex,
  });

  final String key;
  final String message;
  final int? chapterIndex;
  final int? nodeIndex;
}

/// 发布阻断项。每条都定位到具体对象,让 UI 能把用户送到那一行。
List<BlockingIssue> blockingIssuesOf(
  PublishDraft draft,
  List<ChapterState> states,
) {
  final issues = <BlockingIssue>[];
  final isFree = draft.productType == kProductFreeExplore;

  if (textOf(draft.name).isEmpty) {
    issues.add(const BlockingIssue(key: 'name', message: '请填写主题名称'));
  }
  if (textOf(draft.subtitle).isEmpty) {
    issues.add(const BlockingIssue(key: 'subtitle', message: '请填写一句话介绍'));
  }
  if (textOf(draft.description).isEmpty) {
    issues.add(const BlockingIssue(key: 'description', message: '请填写完整介绍'));
  }
  if (textOf(draft.imgUrl).isEmpty) {
    issues.add(const BlockingIssue(key: 'imgUrl', message: '请上传竖版封面'));
  }
  if (isFree && textOf(draft.recruitDeadline).isEmpty) {
    issues.add(
      const BlockingIssue(key: 'recruitDeadline', message: '自由探索必须设置招募截止时间'),
    );
  }
  if (states.isEmpty) {
    issues.add(const BlockingIssue(key: 'chapters', message: '至少需要一个章节'));
  }
  for (final state in states) {
    if (state.storyRequired && !state.storyDone) {
      issues.add(
        BlockingIssue(
          key: 'chapter${state.index}',
          chapterIndex: state.index,
          message: '${state.name}缺少剧情',
        ),
      );
    }
    if (state.nodeCount == 0) {
      issues.add(
        BlockingIssue(
          key: 'chapter${state.index}',
          chapterIndex: state.index,
          message: '${state.name}还没有节点',
        ),
      );
    }
  }
  for (final chapter in draft.chapters) {
    final ci = draft.chapters.indexOf(chapter);
    for (final node in chapter.nodes) {
      final ni = chapter.nodes.indexOf(node);
      final label = textOf(node.name).isEmpty
          ? '第${ni + 1}个节点'
          : textOf(node.name);
      if (textOf(node.name).isEmpty) {
        issues.add(
          BlockingIssue(
            key: 'node',
            chapterIndex: ci,
            nodeIndex: ni,
            message: '$label缺少名称',
          ),
        );
      }
      if (!hasUsableCoords(node)) {
        issues.add(
          BlockingIssue(
            key: 'node',
            chapterIndex: ci,
            nodeIndex: ni,
            message: '节点「$label」缺少地点',
          ),
        );
      }
    }
  }
  return issues;
}

class DraftPolicy {
  const DraftPolicy({
    required this.defaultAnchor,
    required this.starterAction,
    required this.chapterStates,
    required this.blockingIssues,
    required this.creativeComplete,
    required this.merchantRequired,
  });

  final String defaultAnchor;

  /// 只在空草稿时给引导;有内容之后靠章节卡状态标记。
  final StarterAction? starterAction;
  final List<ChapterState> chapterStates;
  final List<BlockingIssue> blockingIssues;
  final bool creativeComplete;

  /// UI 层的意图开关。真正决定是否走招商链路的是后端看 recruitDeadline。
  final bool merchantRequired;
}

/// 唯一主入口。页面只消费返回值,不复制里面的条件。
DraftPolicy evaluateProfessionalDraft(PublishDraft draft, {int? clubId}) {
  final chapterStates = chapterStatesOf(draft);
  final defaultAnchor = defaultAnchorFor(draft.productType, clubId);
  final blockingIssues = blockingIssuesOf(draft, chapterStates);
  return DraftPolicy(
    defaultAnchor: defaultAnchor,
    starterAction: isBlankDraft(draft) ? starterActionFor(defaultAnchor) : null,
    chapterStates: chapterStates,
    blockingIssues: blockingIssues,
    creativeComplete: blockingIssues.isEmpty,
    merchantRequired: draft.openMerchantPool,
  );
}

// ---------------------------------------------------------------- 票务

class ScheduleIssue {
  const ScheduleIssue({required this.field, required this.message});
  final String field;
  final String message;
}

/// 城市定向的集合时间校验(对齐 publish-ticket-schedule.js)。
List<ScheduleIssue> cityOrientationScheduleIssues(PublishTicket ticket) {
  if (ticket.mode != kProductCity) return const <ScheduleIssue>[];
  final startTime = textOf(ticket.startTime);
  final endTime = textOf(ticket.endTime);
  final issues = <ScheduleIssue>[];
  if (startTime.isEmpty) {
    issues.add(const ScheduleIssue(field: 'startTime', message: '请选择集合开始时间'));
  }
  if (endTime.isEmpty) {
    issues.add(const ScheduleIssue(field: 'endTime', message: '请选择集合结束时间'));
  }
  if (startTime.isNotEmpty &&
      endTime.isNotEmpty &&
      endTime.compareTo(startTime) <= 0) {
    issues.add(
      const ScheduleIssue(field: 'endTime', message: '集合结束时间必须晚于开始时间'),
    );
  }
  return issues;
}

/// 票种编辑器「保存」可用性:名称非空 + 集合时间合法 + 城市定向必须选集合地点。
bool canSaveTicket(PublishTicket ticket) {
  final nameOk = textOf(ticket.name).isNotEmpty;
  final scheduleOk = cityOrientationScheduleIssues(ticket).isEmpty;
  final meetingOk =
      ticket.mode != kProductCity || textOf(ticket.meetingPoint).isNotEmpty;
  return nameOk && scheduleOk && meetingOk;
}

// ---------------------------------------------------------------- 日期

/// 归一化日期时间:纯日期补 defaultTime;带时分则规整为
/// "YYYY-MM-DD HH:mm:ss";解析不出返 null(对齐 publish-datetime.js)。
String? normalizeDateTime(String? v, String defaultTime) {
  if (v == null || v.isEmpty) return null;
  final s = textOf(v);
  final dateOnly = RegExp(r'^(\d{4}-\d{2}-\d{2})$').firstMatch(s);
  if (dateOnly != null) return '${dateOnly.group(1)} $defaultTime';
  final withTime = RegExp(
    r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})(?::(\d{2}))?',
  ).firstMatch(s);
  if (withTime != null) {
    return '${withTime.group(1)} ${withTime.group(2)}:${withTime.group(3) ?? '00'}';
  }
  return null;
}

// ---------------------------------------------------------------- 故事流

const int _maxBlocksPerChapter = 200;

/// 打开故事流编辑器前调用:把「描述 + 节点」物化成 blocks 结构。
/// 已有 blocks 时做投影同步;没有时按 description 建首块 + 每节点一块。
/// ★ 节点没有 localId 的(编辑回填的数据)先补上,否则故事块无从引用。
void materializeChapter(PublishChapter chapter, String Function() makeKey) {
  chapter.nodes = List<PublishNode>.of(chapter.nodes);
  for (final node in chapter.nodes) {
    if (node.localId.isEmpty) node.localId = makeKey();
  }
  if (chapter.blocks == null) {
    chapter.nodes.sort((a, b) => (a.sortID).compareTo(b.sortID));
    final blocks = <StoryBlock>[
      StoryBlock.text(makeKey(), chapter.description),
    ];
    for (final node in chapter.nodes) {
      blocks.add(StoryBlock.node(makeKey(), node.localId));
    }
    chapter.blocks = blocks;
  } else {
    chapter.blocks = chapter.blocks!
        .map((StoryBlock source) {
          final String key = source.key.isEmpty ? makeKey() : source.key;
          switch (source.type) {
            case 'text':
              return StoryBlock.text(key, source.content);
            case 'node':
              final PublishNode? node = _nodeForBlock(chapter, source);
              if (node == null || node.localId.isEmpty) {
                throw StateError('节点块引用已失效');
              }
              return StoryBlock.node(key, node.localId);
            case 'image':
              final String url = source.url.trim();
              if (url.isEmpty) throw StateError('媒体块缺少地址');
              return StoryBlock.image(key, url);
            case 'audio':
              final String url = source.url.trim();
              if (url.isEmpty) throw StateError('媒体块缺少地址');
              return StoryBlock.audio(key, url);
            default:
              throw StateError('不支持的故事流块类型');
          }
        })
        .toList(growable: true);
  }
  _synchronizeChapter(chapter);
}

PublishNode? _nodeForBlock(PublishChapter chapter, StoryBlock block) {
  if (block.nodeKey.isEmpty) return null;
  for (final node in chapter.nodes) {
    if (node.localId == block.nodeKey) return node;
  }
  return null;
}

/// blocks → 节点顺序的真源。城市定向的节点顺序由故事流决定。
List<PublishNode> _orderedNodes(PublishChapter chapter) {
  final nodes = List<PublishNode>.of(chapter.nodes);
  final ordered = <PublishNode>[];
  final seen = <String>{};
  final blocks = chapter.blocks ?? const <StoryBlock>[];
  for (final block in blocks) {
    if (block.type != 'node') continue;
    final node = _nodeForBlock(chapter, block);
    if (node == null || node.localId.isEmpty) {
      throw StateError('节点块引用已失效');
    }
    if (seen.contains(node.localId)) {
      throw StateError('同一节点不能重复出现在故事流中');
    }
    seen.add(node.localId);
    ordered.add(node);
  }
  if (ordered.length != nodes.length) {
    throw StateError('存在未编排进故事流的正式节点');
  }
  return ordered;
}

void _synchronizeChapter(PublishChapter chapter) {
  chapter.nodes = _orderedNodes(chapter);
  for (var i = 0; i < chapter.nodes.length; i++) {
    chapter.nodes[i].sortID = i + 1;
  }
  chapter.description = _projectedDescription(
    chapter.blocks ?? const <StoryBlock>[],
  );
  chapter.schemaVersion = 1;
  chapter.required = 1;
}

String _projectedDescription(List<StoryBlock> blocks) {
  final textBlocks = <String>[];
  for (final block in blocks) {
    if (block.type == 'node') break;
    if (block.type == 'text') textBlocks.add(block.content);
  }
  return textBlocks.join('\n');
}

sealed class StoryCommand {
  const StoryCommand();
}

class InsertTextAtCommand extends StoryCommand {
  const InsertTextAtCommand({required this.index, required this.blockKey});
  final int index;
  final String blockKey;
}

class InsertNodeAtCommand extends StoryCommand {
  const InsertNodeAtCommand({
    required this.index,
    required this.node,
    required this.blockKey,
  });
  final int index;
  final PublishNode node;
  final String blockKey;
}

enum StoryMediaType { image, audio }

class InsertMediaAtCommand extends StoryCommand {
  const InsertMediaAtCommand({
    required this.index,
    required this.blockKey,
    required this.mediaType,
    required this.url,
  });

  final int index;
  final String blockKey;
  final StoryMediaType mediaType;
  final String url;
}

class EditTextCommand extends StoryCommand {
  const EditTextCommand({required this.blockKey, required this.content});
  final String blockKey;
  final String content;
}

class RemoveNodeCommand extends StoryCommand {
  const RemoveNodeCommand({required this.blockKey});
  final String blockKey;
}

class RemoveTextCommand extends StoryCommand {
  const RemoveTextCommand({required this.blockKey});
  final String blockKey;
}

class RemoveMediaCommand extends StoryCommand {
  const RemoveMediaCommand({required this.blockKey});
  final String blockKey;
}

class StoryCommandResult {
  const StoryCommandResult({
    required this.chapter,
    this.insertedBlockKey,
    this.removed,
  });

  final PublishChapter chapter;
  final String? insertedBlockKey;
  final RemovedStoryNode? removed;
}

class RemovedStoryNode {
  const RemovedStoryNode({
    required this.blockIndex,
    required this.block,
    required this.node,
  });
  final int blockIndex;
  final StoryBlock block;
  final PublishNode node;
}

/// 故事流唯一状态变更入口(对齐 pro-editor-story.applyStoryCommand)。
/// 传入的 chapter 会被深拷贝,返回值里是新实例,原实例不动。
StoryCommandResult applyStoryCommand(
  PublishChapter source,
  StoryCommand command,
) {
  final chapter = source.copy();
  chapter.blocks ??= <StoryBlock>[];
  final blocks = chapter.blocks!;

  int insertionIndex(int rawIndex) {
    if (rawIndex < 0 || rawIndex > blocks.length) {
      throw StateError('插入点已失效，请重新选择');
    }
    return rawIndex;
  }

  switch (command) {
    case InsertTextAtCommand():
      if (blocks.length >= _maxBlocksPerChapter) {
        throw StateError('每章最多 $_maxBlocksPerChapter 个内容块');
      }
      blocks.insert(
        insertionIndex(command.index),
        StoryBlock.text(command.blockKey, ''),
      );
      _synchronizeChapter(chapter);
      return StoryCommandResult(
        chapter: chapter,
        insertedBlockKey: command.blockKey,
      );
    case InsertNodeAtCommand():
      if (blocks.length >= _maxBlocksPerChapter) {
        throw StateError('每章最多 $_maxBlocksPerChapter 个内容块');
      }
      final node = command.node.copy();
      if (node.localId.isEmpty) throw StateError('节点缺少本地标识');
      if (blocks.any((b) => b.type == 'node' && b.nodeKey == node.localId)) {
        throw StateError('节点已经在故事流中');
      }
      blocks.insert(
        insertionIndex(command.index),
        StoryBlock.node(command.blockKey, node.localId),
      );
      chapter.nodes.removeWhere((n) => n.localId == node.localId);
      chapter.nodes.add(node);
      _synchronizeChapter(chapter);
      return StoryCommandResult(
        chapter: chapter,
        insertedBlockKey: command.blockKey,
      );
    case InsertMediaAtCommand():
      if (blocks.length >= _maxBlocksPerChapter) {
        throw StateError('每章最多 $_maxBlocksPerChapter 个内容块');
      }
      final String url = command.url.trim();
      if (url.isEmpty) throw StateError('媒体块缺少地址');
      final StoryBlock block = switch (command.mediaType) {
        StoryMediaType.image => StoryBlock.image(command.blockKey, url),
        StoryMediaType.audio => StoryBlock.audio(command.blockKey, url),
      };
      blocks.insert(insertionIndex(command.index), block);
      _synchronizeChapter(chapter);
      return StoryCommandResult(
        chapter: chapter,
        insertedBlockKey: command.blockKey,
      );
    case EditTextCommand():
      final idx = blocks.indexWhere(
        (b) => b.key == command.blockKey && b.type == 'text',
      );
      if (idx < 0) throw StateError('未找到要编辑的文字块');
      blocks[idx].content = command.content;
      _synchronizeChapter(chapter);
      return StoryCommandResult(chapter: chapter);
    case RemoveNodeCommand():
      final blockIndex = blocks.indexWhere(
        (b) => b.key == command.blockKey && b.type == 'node',
      );
      if (blockIndex < 0) throw StateError('未找到要删除的节点块');
      final block = blocks[blockIndex];
      final nodeIndex = chapter.nodes.indexWhere(
        (n) => n.localId == block.nodeKey,
      );
      if (nodeIndex < 0) throw StateError('节点块引用已失效');
      final node = chapter.nodes[nodeIndex];
      blocks.removeAt(blockIndex);
      chapter.nodes.removeAt(nodeIndex);
      _synchronizeChapter(chapter);
      return StoryCommandResult(
        chapter: chapter,
        removed: RemovedStoryNode(
          blockIndex: blockIndex,
          block: block,
          node: node,
        ),
      );
    case RemoveTextCommand():
      final idx = blocks.indexWhere(
        (b) => b.key == command.blockKey && b.type == 'text',
      );
      if (idx < 0) throw StateError('未找到要删除的文字块');
      blocks.removeAt(idx);
      _synchronizeChapter(chapter);
      return StoryCommandResult(chapter: chapter);
    case RemoveMediaCommand():
      final int idx = blocks.indexWhere(
        (StoryBlock block) =>
            block.key == command.blockKey &&
            (block.type == 'image' || block.type == 'audio'),
      );
      if (idx < 0) throw StateError('未找到要删除的媒体块');
      blocks.removeAt(idx);
      _synchronizeChapter(chapter);
      return StoryCommandResult(chapter: chapter);
  }
}

/// 提交用章节 map:blocks 文字转 content、媒体转 url、节点转 nodeIndex。
/// 章节上送里**不由编辑器结构决定**的那部分:封面、章节音频、配色、商家承接配置。
///
/// ⚠️ 这些字段编辑器大多没有界面,但编辑既有主题时会被**读回来**
///   (`publish_api` 的章节解析),而后端更新章节是「整章删掉重建 +
///   `BeanUtils.copyProperties`」—— 载荷里少一个字段,那一列就被写成 NULL。
///   所以「读回来了就必须原样送回去」不是可选项,而是这条链路的前提。
///
/// ★ 2026-09-09 实测到的两种后果(都只砸在俱乐部主理人身上,因为只有他配得了章节招商):
///   ① 招商开着(`recruitEnabled=1`)却不带 `categoryId` ⇒ 后端 `assertChapterShape`
///      当场拒整次保存:「开放商家承接的章节必须选择适合商家品类」——
///      而 App 里根本没有品类选择器,用户看到一个自己修不了的报错。
///   ② 招商还没开 ⇒ 品类/名额/权益门槛三项被静默清空。
///
/// ★ 两条上送分支(块化的 [toPayloadChapter] 与自由探索的直排分支)**共用这一处**,
///   就是为了不让它们再各自漂一份 —— 上一次漂出来的差集正好就是这个 bug。
Map<String, dynamic> _chapterCarryOver(PublishChapter c) => <String, dynamic>{
  if (c.imgArr.isNotEmpty) 'imgArr': c.imgArr,
  if (textOf(c.audioUrl).isNotEmpty) 'audioUrl': c.audioUrl,
  'atmospherePreset': normalizeAtmosphere(c.atmospherePreset),
  'recruitEnabled': c.recruitEnabled,
  'termsMode': c.termsMode,
  if (c.categoryId != null) 'categoryId': c.categoryId,
  if (c.category.isNotEmpty) 'category': c.category,
  if (c.maxMerchant != null) 'maxMerchant': c.maxMerchant,
  if (textOf(c.perkMinValue).isNotEmpty) 'perkMinValue': c.perkMinValue,
  // 这三个 App 没有编辑界面,纯粹是「读回来了就得送回去」——
  // 玩法边界尤其要紧:它是承接合同的一部分,被清空后商家怎么配都会被拒。
  if (c.allowedValidationMethods.isNotEmpty)
    'allowedValidationMethods': c.allowedValidationMethods,
  if (c.maxNodeXp != null) 'maxNodeXp': c.maxNodeXp,
  if (c.calculatedDistance != null) 'calculatedDistance': c.calculatedDistance,
};

Map<String, dynamic> toPayloadChapter(PublishChapter source) {
  final chapter = source.copy();
  chapter.nodes = _orderedNodes(chapter);
  final nodeIndexes = <String, int>{
    for (var i = 0; i < chapter.nodes.length; i++) chapter.nodes[i].localId: i,
  };
  final blocks = <Map<String, dynamic>>[];
  for (final block in chapter.blocks ?? const <StoryBlock>[]) {
    if (block.type == 'text') {
      blocks.add(<String, dynamic>{'type': 'text', 'content': block.content});
    } else if (block.type == 'node' && nodeIndexes.containsKey(block.nodeKey)) {
      blocks.add(<String, dynamic>{
        'type': 'node',
        'nodeIndex': nodeIndexes[block.nodeKey],
      });
    } else if (block.type == 'image' || block.type == 'audio') {
      final String url = block.url.trim();
      // 音频允许先落一个**空块**(点插入缝先插占位,再点它选文件),它只是编辑器
      // 里的占位,没有任何内容可上送 —— 直接跳过,不落库也不报错。
      // 图片没有这一态:一个点不开的空图壳没有用,继续当场拒。
      if (url.isEmpty) {
        if (block.type == 'audio') continue;
        throw StateError('媒体块缺少地址');
      }
      blocks.add(<String, dynamic>{'type': block.type, 'url': url});
    } else {
      throw StateError('节点块引用已失效');
    }
  }
  chapter.description = _projectedDescription(
    chapter.blocks ?? const <StoryBlock>[],
  );
  return <String, dynamic>{
    'name': chapter.name,
    'description': chapter.description,
    'nodes': chapter.nodes
        .map(
          (n) => <String, dynamic>{
            'name': n.name,
            if (textOf(n.description).isNotEmpty) 'description': n.description,
            if (textOf(n.address).isNotEmpty) 'address': n.address,
            if (textOf(n.longitude).isNotEmpty) 'longitude': n.longitude,
            if (textOf(n.latitude).isNotEmpty) 'latitude': n.latitude,
            if (textOf(n.imgUrl).isNotEmpty) 'imgUrl': n.imgUrl,
            if (n.templateId != null && n.templateId! > 0)
              'templateId': n.templateId,
            'sortID': n.sortID,
            'nodeTime': n.nodeTime,
          },
        )
        .toList(),
    if (blocks.isNotEmpty) 'blocks': blocks,
    'schemaVersion': chapter.schemaVersion,
    'required': chapter.required,
    ..._chapterCarryOver(chapter),
  };
}

// ---------------------------------------------------------------- 提交载荷

/// 组装 create/update 上送载荷(对齐 fabu/index.js submitForm 的 apiData)。
/// ★ 字段名与 TopicCreateDTO 逐一对齐;归一化集中在这一处:
///   - 票的 mode 一律覆盖为主题级 productType(混票会被后端拒)
///   - openClubPool 恒 0(「邀请俱乐部带队」已整条下线,界面上没有任何入口)
///   - recruitDeadline 仅自由探索上送(后端硬约束)
///   - scope 恒上送(真源同款:'MERCHANT' 或 '' )——缺了商家发布记个人名下
Map<String, dynamic> buildTopicPayload(PublishDraft d, {String scope = ''}) {
  final productType = d.productType;
  final chapters = <Map<String, dynamic>>[];
  for (final chapter in d.chapters) {
    final source = chapter.copy();
    // 城市定向按故事流投影;自由探索按 nodes 顺序。
    if (productType == kProductCity && source.blocks != null) {
      try {
        chapters.add(toPayloadChapter(source));
        continue;
      } on StateError {
        // 故事流引用失效 → 回退到直排节点,宁可少块化也不让发布当场炸。
      }
    }
    final nodes = List<PublishNode>.of(source.nodes)
      ..sort((a, b) => a.sortID.compareTo(b.sortID));
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].sortID = i + 1;
    }
    chapters.add(<String, dynamic>{
      'name': source.name,
      'description': source.description,
      'nodes': nodes
          .map(
            (n) => <String, dynamic>{
              'name': n.name,
              if (textOf(n.description).isNotEmpty)
                'description': n.description,
              if (textOf(n.address).isNotEmpty) 'address': n.address,
              if (textOf(n.longitude).isNotEmpty) 'longitude': n.longitude,
              if (textOf(n.latitude).isNotEmpty) 'latitude': n.latitude,
              if (textOf(n.imgUrl).isNotEmpty) 'imgUrl': n.imgUrl,
              if (n.templateId != null && n.templateId! > 0)
                'templateId': n.templateId,
              'sortID': n.sortID,
              'nodeTime': n.nodeTime,
            },
          )
          .toList(),
      ..._chapterCarryOver(source),
    });
  }

  final tickets = d.tickets
      .map(
        (t) => <String, dynamic>{
          'name': t.name,
          'price': t.price ?? 0,
          'mode': productType,
          // 归一化:sync 同步来的值可能已带时间/ISO 串,原样追加会拼出非法时间。
          if (t.startTime.isNotEmpty)
            'startTime': normalizeDateTime(t.startTime, '00:00:00'),
          if (t.endTime.isNotEmpty)
            'endTime': normalizeDateTime(t.endTime, '23:59:59'),
          'totalStock': t.totalStock,
          if (t.description.isNotEmpty) 'description': t.description,
          if (t.meetingPoint.isNotEmpty) 'meetingPoint': t.meetingPoint,
          'teamSize': t.teamSize,
          if (t.meetingPointLongitude.isNotEmpty)
            'gatherLng': t.meetingPointLongitude,
          if (t.meetingPointLatitude.isNotEmpty)
            'gatherLat': t.meetingPointLatitude,
          if (t.saleStartTime.isNotEmpty) 'saleStartTime': t.saleStartTime,
          if (t.saleEndTime.isNotEmpty) 'saleEndTime': t.saleEndTime,
        },
      )
      .toList();

  return <String, dynamic>{
    'name': d.name,
    'subtitle': d.subtitle,
    'description': d.description,
    if (d.startDate.isNotEmpty)
      'startDate': normalizeDateTime(d.startDate, '00:00:00'),
    if (d.endDate.isNotEmpty)
      'endDate': normalizeDateTime(d.endDate, '23:59:59'),
    if (d.imgUrl.isNotEmpty) 'imgUrl': d.imgUrl,
    if (d.imgArr.isNotEmpty) 'imgArr': d.imgArr,
    'categoryIds': d.categoryIds.join(','),
    'chapters': chapters,
    'collaboratorIds': d.collaboratorIds,
    'productType': productType,
    'tickets': tickets,
    'openMerchantPool': d.openMerchantPool ? 1 : 0,
    'openClubPool': 0,
    // 自由探索后端硬要求 recruitDeadline;不传则后端直接抛异常。
    if (productType == kProductFreeExplore)
      'recruitDeadline': normalizeDateTime(d.recruitDeadline, '23:59:59'),
    'publishToCreative': d.publishToCreative ? 1 : 0,
    if (d.clubId != null) 'clubId': d.clubId,
    'audioUrl': d.audioUrl,
    'audioDuration': d.audioDuration,
    'selfPlay': d.selfPlay ? 1 : 0,
    'selfPlayPrice': d.selfPlayPrice.isEmpty ? 0 : d.selfPlayPrice,
    'selfPlayQuota': d.selfPlayQuota.isEmpty ? 0 : d.selfPlayQuota,
    if (d.finishMedalName.isNotEmpty) 'finishMedalName': d.finishMedalName,
    if (d.finishMedalImg.isNotEmpty) 'finishMedalImg': d.finishMedalImg,
    'completeRewardCouponId': d.completeRewardCouponId,
    'publishMode': d.publishMode,
    'scope': scope,
  };
}

/// WHITELIST 档(已开卖主题)只许上送文案与图 —— 日期/章节/票后端一律拒收,
/// 前端主动剔除,否则整包上送会当场被拒(方案 §6 口径)。
Map<String, dynamic> whitelistPayload(Map<String, dynamic> full) {
  return <String, dynamic>{
    for (final key in const <String>[
      'name',
      'subtitle',
      'description',
      'imgUrl',
      'imgArr',
      'categoryIds',
      'scope',
    ])
      if (full[key] != null) key: full[key],
  };
}

// ---------------------------------------------------------------- 校验袋/// 校验积累原语(对齐 publish-validator.js):errors 映射 + order 顺序。
class PublishValidationBag {
  final Map<String, String> errors = <String, String>{};
  final List<String> order = <String>[];
  final List<String> messages = <String>[];

  void add(String key, String message, [String? toastMessage]) {
    errors[key] = message;
    order.add(key);
    messages.add(toastMessage ?? message);
  }

  void require(bool cond, String key, String message, [String? toast]) {
    if (!cond) add(key, message, toast);
  }

  String? firstMessage() => messages.isEmpty ? null : messages.first;

  bool isValid() => order.isEmpty;
}

/// 发布校验全集(对齐 fabu/index.js _buildValidationBag,规则逐条同源)。
/// 页面用 bag.isValid() 决定「检查并发布」能不能点。
PublishValidationBag buildPublishValidationBag(PublishDraft draft) {
  final bag = PublishValidationBag();

  bag.require(textOf(draft.name).isNotEmpty, 'name', '请填写路线名称');
  bag.require(textOf(draft.description).isNotEmpty, 'description', '请填写路线描述');
  bag.require(textOf(draft.startDate).isNotEmpty, 'startDate', '请选择开始时间');
  bag.require(textOf(draft.endDate).isNotEmpty, 'endDate', '请选择结束时间');
  bag.require(textOf(draft.imgUrl).isNotEmpty, 'imgUrl', '请上传路线封面');
  bag.require(draft.categoryIds.isNotEmpty, 'categoryIds', '请选择至少一个路线类别');

  final freeExplore = draft.productType == kProductFreeExplore;
  if (freeExplore) {
    bag.require(
      textOf(draft.recruitDeadline).isNotEmpty,
      'recruitDeadline',
      '请选择招商截止日期',
    );
  }

  final policy = evaluateProfessionalDraft(draft);
  for (final issue in policy.blockingIssues) {
    if (issue.chapterIndex != null && issue.message.contains('缺少剧情')) {
      bag.add('chapterStory${issue.chapterIndex}', issue.message);
    }
  }

  // 票务:价格/集合地点/票单时间为页面专有规则,逐票交错保持原样。
  for (var index = 0; index < draft.tickets.length; index++) {
    final ticket = draft.tickets[index];
    bag.require(
      textOf(ticket.name).isNotEmpty,
      'ticketName$index',
      '请填写票单名称',
      '第${index + 1}个票务：请填写票单名称',
    );
    // ★ 「票价没填」与「票价是 0(免费)」必须分开:null = 没填 → 拦;
    // 0 = 明确的免费票 → 合法。
    if (ticket.price == null) {
      bag.add('ticketPrice$index', '请填写票价', '第${index + 1}个票务：请填写票价');
    } else if (ticket.price! < 0) {
      bag.add('ticketPrice$index', '价格不能为负数', '第${index + 1}个票务：价格不能为负数');
    }
    if (ticket.mode == kProductCity) {
      for (final issue in cityOrientationScheduleIssues(ticket)) {
        final field = issue.field == 'startTime' ? 'Start' : 'End';
        bag.add(
          'ticket$field$index',
          issue.message,
          '第${index + 1}个票务：${issue.message}',
        );
      }
      bag.require(
        textOf(ticket.meetingPoint).isNotEmpty,
        'ticketMeeting$index',
        '请填写集合地点',
        '第${index + 1}个票务：请填写集合地点',
      );
    } else {
      bag.require(
        textOf(ticket.startTime).isNotEmpty,
        'ticketStart$index',
        '请填写票单开始日期',
        '第${index + 1}个票务：请填写票单开始日期',
      );
      bag.require(
        textOf(ticket.endTime).isNotEmpty,
        'ticketEnd$index',
        '请填写票单结束日期',
        '第${index + 1}个票务：请填写票单结束日期',
      );
    }
  }

  // 章节与节点。
  if (draft.chapters.isEmpty) {
    bag.add('chapters', '请至少添加一个章节');
  } else {
    for (var ci = 0; ci < draft.chapters.length; ci++) {
      final chapter = draft.chapters[ci];
      bag.require(
        chapter.nodes.isNotEmpty,
        'chapter$ci',
        '第${ci + 1}章至少需要一个节点',
      );
      for (var ni = 0; ni < chapter.nodes.length; ni++) {
        bag.require(
          hasUsableCoords(chapter.nodes[ni]),
          'chapter$ci',
          '第${ci + 1}章第${ni + 1}个节点还没有选地点',
        );
      }
      if (draft.productType == kProductFreeExplore &&
          chapter.recruitEnabled == 1) {
        bag.require(
          (chapter.categoryId ?? 0) > 0,
          'chapterRecruitCategory$ci',
          '第${ci + 1}章请选择适合商家品类',
        );
        bag.require(
          chapter.termsMode == 'PERK' || chapter.termsMode == 'TRAFFIC',
          'chapterRecruitTerms$ci',
          '第${ci + 1}章请选择合作方式',
        );
        if (chapter.perkMinValue != null) {
          final perkMin = double.tryParse(chapter.perkMinValue!);
          bag.require(
            perkMin != null && perkMin > 0,
            'chapterRecruitPerkMin$ci',
            '第${ci + 1}章权益最低价值须为大于0的金额',
          );
        }
        final maxMerchant = chapter.maxMerchant ?? 0;
        bag.require(
          maxMerchant >= 0 && maxMerchant <= 127,
          'chapterRecruitMax$ci',
          '第${ci + 1}章商家名额请输入0到127之间的整数',
        );
      }
    }
  }

  return bag;
}

// ---------------------------------------------------------------- 发布前检查

class PublishCheckItem {
  const PublishCheckItem({required this.label, required this.tab});
  final String label;

  /// 0=路线(创作)页 2=基本信息(主题详情/票务)。
  final int tab;
}

class PublishCheck {
  const PublishCheck({required this.blocking, required this.advisory});
  final List<PublishCheckItem> blocking;
  final List<PublishCheckItem> advisory;
}

/// 发布前检查(M4·A):blocking 硬必填阻断 + advisory 软建议不阻断。
PublishCheck buildPublishCheck(PublishDraft draft) {
  final bag = buildPublishValidationBag(draft);
  int tabOf(String key) {
    if (key.startsWith('chapterRecruit')) return 2;
    if (key.startsWith('chapter') || key == 'chapters') return 0;
    return 2;
  }

  final blocking = <PublishCheckItem>[
    for (final key in bag.order)
      PublishCheckItem(label: bag.errors[key] ?? '', tab: tabOf(key)),
  ];

  // advisory:站点级软项 + 未配玩法的站点。
  final advisory = <PublishCheckItem>[];
  var noGame = 0;
  var missingCoords = 0;
  var missingDesc = 0;
  for (final chapter in draft.chapters) {
    for (final node in chapter.nodes) {
      if (!hasGameplay(node)) noGame++;
      if (!hasUsableCoords(node)) missingCoords++;
      if (textOf(node.description).isEmpty) missingDesc++;
    }
  }
  if (missingCoords > 0) {
    advisory.add(PublishCheckItem(label: '$missingCoords 个站点还没选地点', tab: 0));
  }
  if (missingDesc > 0) {
    advisory.add(PublishCheckItem(label: '部分站点缺描述', tab: 0));
  }
  if (noGame > 0) {
    advisory.add(PublishCheckItem(label: '$noGame 个站点未配置玩法', tab: 0));
  }
  return PublishCheck(blocking: blocking, advisory: advisory);
}
