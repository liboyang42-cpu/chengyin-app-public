import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/category.dart';
import '../models/publish_draft.dart';

/// 发布接口:简易版 + 专业版(对齐小程序 pages/publish/fabu)。
///
/// 专业版端点(全部真实存在于后端,逐个 grep 核实过):
/// - `POST /api/topic/create` / `POST /api/topic/update`(`@RequestBody TopicCreateDTO`,JSON)
/// - `POST /api/topic/edit-detail`(表单参数 id → 全量回填)
/// - `POST /api/template/homeData` / `POST /api/template/my-list`(节点玩法模板)
/// - `POST /api/ai/safety/precheck`(发布前 AI 安全预检,JSON body)
/// - `POST /api/common/uploadOSS`(multipart 单文件,字段名 'file')
class PublishApi {
  PublishApi(this._client);
  final DioClient _client;

  /// 发布一个主题/路线。成功返回 true,失败抛异常(携带后端 msg)。
  Future<bool> createTopic({
    required String name,
    required String description,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/create',
      data: <String, dynamic>{
        'name': name,
        'description': description,
        // 标记来源为建议版,后端据此走简易发布分支
        'publishMode': 'simple',
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    final code = body['code'];
    if (code != 200) {
      throw Exception((body['msg'] as String?) ?? '发布失败');
    }
    return true;
  }

  // ------------------------------------------------------------ 专业版

  /// 专业版发布:提交完整草稿,返回新主题 id。
  Future<int> createTopicPro(Map<String, dynamic> payload) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/create',
      data: payload,
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body, '主题发布失败');
    return _asInt(body['data']);
  }

  /// 专业版保存(编辑既有主题):返回 true。
  Future<bool> updateTopic(int id, Map<String, dynamic> payload) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/update',
      data: <String, dynamic>{...payload, 'id': id},
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body, '保存失败');
    return true;
  }

  /// 编辑既有主题的编辑器回填(对齐 fabu/index.js loadEditingTopic/applyEditingTopic)。
  /// 返回 (草稿, 编辑档)。字段名落差在这里归一:
  /// merchantStatus→openMerchantPool、totalInventory→totalStock、
  /// chapter.cmsTopicNodeList→nodes。
  Future<(PublishDraft, PublishEditScope)> editDetail(
    int id, {
    String scope = '',
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/edit-detail',
      data: FormData.fromMap(<String, dynamic>{
        'id': id.toString(),
        'scope': scope,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body, '这份主题打不开');
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final topic = data['topic'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final chapters = (data['chapters'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>();
    final tickets = (data['tickets'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>();

    final draft = PublishDraft()
      ..name = (topic['name'] ?? '').toString()
      ..subtitle = (topic['subtitle'] ?? '').toString()
      ..description = (topic['description'] ?? '').toString()
      ..startDate = (topic['startDate'] ?? '').toString()
      ..endDate = (topic['endDate'] ?? '').toString()
      ..imgUrl = (topic['imgUrl'] ?? '').toString()
      ..imgArr = (topic['imgArr'] ?? '').toString()
      ..productType = _productTypeOf(topic)
      ..publishMode = (topic['publishMode'] ?? 'pro').toString()
      ..recruitDeadline = _nullableStr(topic['recruitDeadline'])
      ..finishMedalName = (topic['finishMedalName'] ?? '').toString()
      ..finishMedalImg = (topic['finishMedalImg'] ?? '').toString()
      ..completeRewardCouponId = _asInt(topic['completeRewardCouponId'])
      ..openMerchantPool = _asInt(topic['merchantStatus']) == 1
      ..selfPlay = _asInt(topic['selfPlay']) == 1
      ..selfPlayPrice = (topic['selfPlayPrice'] ?? '').toString()
      ..selfPlayQuota = (topic['selfPlayQuota'] ?? '').toString()
      // 本地草稿冲突检测的版本戳(真源 baseRevision = topic.updateTime||createTime)。
      ..baseRevision = (topic['updateTime'] ?? topic['createTime'] ?? '')
          .toString();

    final categoryIds = (topic['categoryIds'] ?? '').toString();
    draft.categoryIds = categoryIds
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => int.tryParse(s) ?? 0)
        .where((v) => v > 0)
        .toList();

    var chapterIndex = 0;
    for (final chapter in chapters) {
      final chapterServerId = _asIntOrNull(chapter['id']);
      final chapterKey = 'chapter-${chapterServerId ?? chapterIndex + 1}';
      final c = PublishChapter()
        ..name = (chapter['name'] ?? '').toString()
        ..description = (chapter['description'] ?? '').toString()
        ..imgArr = (chapter['imgArr'] ?? '').toString()
        ..recruitEnabled = _asInt(chapter['recruitEnabled'])
        ..termsMode = (chapter['termsMode'] ?? 'PERK').toString()
        ..categoryId = _asIntOrNull(chapter['categoryId'])
        ..maxMerchant = _asIntOrNull(chapter['maxMerchant'])
        ..perkMinValue = _nullableStr(chapter['perkMinValue'])
        ..category = (chapter['category'] ?? '').toString()
        // 下面三个 App 没有编辑界面,读回来只为原样送回去 —— 不读就等于每次保存都清空。
        ..allowedValidationMethods = (chapter['allowedValidationMethods'] ?? '')
            .toString()
        ..maxNodeXp = _asIntOrNull(chapter['maxNodeXp'])
        ..calculatedDistance = chapter['calculatedDistance'] as num?
        ..audioUrl = (chapter['audioUrl'] ?? '').toString()
        // 存量里还存着 NIGHT/ARCHIVE/MOSS/NEON,读出来要能显示 —— 归一表见模型。
        ..atmospherePreset = normalizeAtmosphere(
          chapter['atmospherePreset']?.toString(),
        )
        ..localId = chapterKey;
      final nodeList =
          (chapter['cmsTopicNodeList'] as List<dynamic>? ??
                  chapter['nodes'] as List<dynamic>? ??
                  <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
      c.nodes = <PublishNode>[
        for (var nodeIndex = 0; nodeIndex < nodeList.length; nodeIndex++)
          _nodeFromJson(nodeList[nodeIndex])
            ..localId =
                '$chapterKey-node-'
                '${_asIntOrNull(nodeList[nodeIndex]['id']) ?? nodeIndex + 1}',
      ];
      c.blocks = _blocksFromJson(
        chapter['blocks'],
        nodeList: nodeList,
        nodes: c.nodes,
        chapterKey: chapterKey,
      );
      draft.chapters.add(c);
      chapterIndex += 1;
    }

    for (final ticket in tickets) {
      final t = PublishTicket()
        ..name = (ticket['name'] ?? '').toString()
        ..mode = draft.productType
        ..totalStock = _asInt(ticket['totalInventory'], 100)
        ..meetingPoint = (ticket['meetingPoint'] ?? '').toString()
        ..teamSize = _asInt(ticket['teamSize'])
        ..startTime = (ticket['startTime'] ?? '').toString()
        ..endTime = (ticket['endTime'] ?? '').toString()
        ..saleStartTime = (ticket['saleStartTime'] ?? '').toString()
        ..saleEndTime = (ticket['saleEndTime'] ?? '').toString()
        ..description = (ticket['description'] ?? '').toString()
        ..refundSupported = (ticket['refundSupported'] ?? true) != false;
      final price = ticket['price'];
      t.price = price == null ? null : (price as num).toDouble();
      draft.tickets.add(t);
    }

    final editScope = (data['editScope'] ?? 'FULL').toString();
    return (
      draft,
      editScope == 'WHITELIST'
          ? PublishEditScope.whitelist
          : PublishEditScope.full,
    );
  }

  static String? _nullableStr(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int _productTypeOf(Map<String, dynamic> topic) {
    final pt = _asInt(topic['productType'], 1);
    return pt == 2 ? 2 : 1;
  }

  static PublishNode _nodeFromJson(Map<String, dynamic> json) {
    final templateInfo = json['templateInfo'] is Map<String, dynamic>
        ? json['templateInfo'] as Map<String, dynamic>
        : <String, dynamic>{};
    return PublishNode()
      ..name = (json['name'] ?? '').toString()
      ..description = (json['description'] ?? '').toString()
      ..address = (json['address'] ?? '').toString()
      ..longitude = (json['longitude'] ?? '').toString()
      ..latitude = (json['latitude'] ?? '').toString()
      ..imgUrl = (json['imgUrl'] ?? '').toString()
      ..nodeTime = _asInt(json['nodeTime'], 30)
      ..templateId = _asIntOrNull(json['templateId'])
      ..templateInfo = templateInfo
      ..templateName = (json['templateName'] ?? '').toString()
      ..sortID = _asInt(json['sortID'], 1);
  }

  /// `edit-detail` 读出的节点块使用真实 `nodeId`，而编辑器
  /// 使用本地 `nodeKey`。映射只放在 API 归一层，避免 UI 知道后端 ID。
  static List<StoryBlock>? _blocksFromJson(
    Object? raw, {
    required List<Map<String, dynamic>> nodeList,
    required List<PublishNode> nodes,
    required String chapterKey,
  }) {
    if (raw is! List<dynamic>) return null;
    final nodeKeysById = <int, String>{};
    for (var i = 0; i < nodeList.length; i++) {
      final id = _asIntOrNull(nodeList[i]['id']);
      if (id != null) nodeKeysById[id] = nodes[i].localId;
    }

    final blocks = <StoryBlock>[];
    for (var i = 0; i < raw.length; i++) {
      final value = raw[i];
      if (value is! Map<String, dynamic>) continue;
      final type = (value['type'] ?? '').toString();
      final key = '$chapterKey-block-${i + 1}';
      if (type == 'text') {
        blocks.add(StoryBlock.text(key, (value['content'] ?? '').toString()));
        continue;
      }
      if (type == 'image' || type == 'audio') {
        final url = (value['url'] ?? '').toString();
        if (url.trim().isEmpty) continue;
        blocks.add(
          type == 'image'
              ? StoryBlock.image(key, url)
              : StoryBlock.audio(key, url),
        );
        continue;
      }
      if (type != 'node') continue;

      String? nodeKey;
      final suppliedNodeKey = _nullableStr(value['nodeKey']);
      if (suppliedNodeKey != null &&
          nodes.any((node) => node.localId == suppliedNodeKey)) {
        nodeKey = suppliedNodeKey;
      }
      nodeKey ??= nodeKeysById[_asIntOrNull(value['nodeId'])];
      final nodeIndex = _asIntOrNull(value['nodeIndex']);
      if (nodeKey == null &&
          nodeIndex != null &&
          nodeIndex >= 0 &&
          nodeIndex < nodes.length) {
        nodeKey = nodes[nodeIndex].localId;
      }
      if (nodeKey != null) blocks.add(StoryBlock.node(key, nodeKey));
    }
    return blocks.isEmpty ? null : blocks;
  }

  static int _asInt(Object? v, [int fallback = 0]) =>
      v is num ? v.toInt() : fallback;

  static int? _asIntOrNull(Object? v) => v is num ? v.toInt() : null;

  void _ensureOk(Map<String, dynamic> body, String fallbackMsg) {
    final code = body['code'];
    if (code != 200) {
      throw Exception((body['msg'] as String?) ?? fallbackMsg);
    }
  }

  // ------------------------------------------------------------ 玩法模板

  /// 模板广场首页。后端的 banner / 最新 / 推荐 / 精选 / 热门
  /// 是五个独立产品段，广场渲染必须保留它们的原始语义。
  Future<PublishTemplateHomeData> templateHomeSections() async {
    try {
      final resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/template/homeData',
        data: <String, dynamic>{},
      );
      final body = resp.data ?? <String, dynamic>{};
      _ensureOk(body, '玩法库加载失败');
      final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return PublishTemplateHomeData.fromJson(data);
    } catch (_) {
      return const PublishTemplateHomeData(
        total: 0,
        categories: <Category>[],
        banner: <PublishTemplate>[],
        latest: <PublishTemplate>[],
        recommended: <PublishTemplate>[],
        mustPlay: <PublishTemplate>[],
        hot: <PublishTemplate>[],
      );
    }
  }

  /// 节点编辑器的旧选择器只需一个公共模板集合；广场页不使用此合并结果。
  Future<List<PublishTemplate>> templateHomeData() async =>
      (await templateHomeSections()).merged;

  /// 我的玩法模板(节点配置模板用)。scope 与真源 getTempList 同款,
  /// 商家入口要按商家口径拉列表。
  Future<List<PublishTemplate>> templateMyList({
    String keyword = '',
    String scope = '',
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/my-list',
      data: FormData.fromMap(<String, dynamic>{
        'is_quote': '1',
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        'scope': scope,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body, '我的玩法加载失败');
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final rows = (data['rows'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>();
    return rows.map(PublishTemplate.fromJson).toList();
  }

  // ------------------------------------------------------------ 上传

  /// 上传文件到 OSS:multipart 单文件,字段名固定为 `file`。
  /// 后端允许 jpg/jpeg/png/gif/mp3/m4a/aac；音频也必须走这条真上传链路。
  Future<String> uploadFile(
    String filePath, {
    String? fileType,
    String? fileName,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/uploadOSS',
      data: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath),
        'fileType': ?fileType,
        'fileName': ?fileName,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureOk(body, '上传失败');
    return (body['url'] ?? '').toString();
  }

  Future<String> uploadImage(String filePath) => uploadFile(filePath);

  // ------------------------------------------------------------ AI 预检

  /// 发布前 AI 安全预检:返回问题列表(level=error 且非 parse_error 才阻断)。
  /// 预检不可用(AI 频控/异常)时抛 [AiPrecheckUnavailable],调用方降级放行 ——
  /// AI 是可用性红线上的软闸,不能堵死发布路。
  Future<List<AiPrecheckIssue>> safetyPrecheck(Map<String, dynamic> req) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/ai/safety/precheck',
      data: req,
    );
    final body = resp.data ?? <String, dynamic>{};
    final code = body['code'];
    if (code != 200) {
      throw AiPrecheckUnavailable((body['msg'] ?? '').toString());
    }
    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final issues = (data['issues'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>();
    return issues
        .map(
          (e) => AiPrecheckIssue(
            level: (e['level'] ?? '').toString(),
            type: (e['type'] ?? '').toString(),
            message: (e['message'] ?? '').toString(),
          ),
        )
        .where((i) => i.message.isNotEmpty)
        .toList();
  }
}

/// AI 预检不可用(频控/门禁/AI 异常)。发布走降级路径,不是用户错误。
class AiPrecheckUnavailable implements Exception {
  AiPrecheckUnavailable(this.msg);
  final String msg;

  @override
  String toString() => msg;
}

class AiPrecheckIssue {
  AiPrecheckIssue({
    required this.level,
    required this.type,
    required this.message,
  });
  final String level;
  final String type;
  final String message;
}
