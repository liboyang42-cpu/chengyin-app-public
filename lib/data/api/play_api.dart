import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/checkin_models.dart';
import '../models/play_check.dart';
import '../models/preference_play.dart';
import '../models/play_ending.dart';
import '../models/completed_play.dart';
import '../models/scan_entry.dart';

/// 后端业务错误(AjaxResult.code != 200),携带后端原文 msg 以便 UI 直接提示
/// (如"无效的打卡码""请先报名并完成支付""请先完成上一站")。
///
/// [code] 是 AjaxResult 顶层的业务码(如 409 表示结构化路线冲突);端上据此做
/// 结构化判定,**不按中文 msg 匹配**。加载类接口的失败不参与冲突恢复,允许为 null。
class PlayException implements Exception {
  PlayException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

/// 首屏回包形状不合法(缺 `data`/`nodes` 或节点不是对象)时的文案。
/// 真源 `pages/play/index.js:2842` 的 `!isRecord(d) || !isRecordList(d.nodes)` 分支。
const String kPlayRouteShapeBrokenTip = '路线没加载出来，请稍后重试';

/// 游玩/打卡接口封装。对应后端 ApiPlayProgressController(已部署):
/// - GET  /api/play/nodes?activityId=   节点列表+进度
/// - POST /api/play/checkin             扫码打卡(activityId+code)
class PlayApi {
  PlayApi(this._client);

  final DioClient _client;
  static const Set<String> _sensorResultTypes = <String>{
    'still',
    'steps',
    'audio_clip',
  };

  /// 解析 AjaxResult 顶层业务码。后端不同出口可能把 `code` 发成 num 或数字
  /// 字符串(如 "409");其余类型解析不出 → 返回 null(fail closed,当作失败),
  /// 既不误判成功,也不因强转抛 TypeError。所有 AjaxResult 出口(含控制器的
  /// DioException body)必须复用本解析器,不得再写 `as num?` 强转。
  static int? businessCodeOf(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static int? _ajaxCode(Map<String, dynamic> body) =>
      businessCodeOf(body['code']);

  /// 完成 transport 共用的业务码校验:仅 code==200 算成功;否则抛
  /// [PlayException],携带可解析的业务码与后端原文 msg(不可吞)。
  static void _ensureAjaxSuccess(Map<String, dynamic> body, String fallback) {
    final int? code = _ajaxCode(body);
    if (code == 200) return;
    throw PlayException((body['msg'] ?? fallback).toString(), code: code);
  }

  /// 拉取某活动的节点列表+进度。
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/play/nodes',
      queryParameters: <String, dynamic>{'activityId': activityId},
    );
    return _nodesResult(resp.data ?? <String, dynamic>{});
  }

  /// 无活动场次的主题通行证，用 topicId 建立自玩会话。
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/play/nodes',
      queryParameters: <String, dynamic>{'topicId': topicId},
    );
    return _nodesResult(resp.data ?? <String, dynamic>{});
  }

  /// 真源 `pages/play/index.js:2830-2843` 的首屏判定前两拍:业务码非 200 抛
  /// [PlayException] 带码(402 → 空态落 `needPass`),形状坏了单独报
  /// 「路线没加载出来」——顺着解析兜底会把坏回包报成「节点还在配置中」,
  /// 那是把故障说成还没开始。
  static PlayNodesResult _nodesResult(Map<String, dynamic> body) {
    final int? code = _ajaxCode(body);
    if (code != 200) {
      throw PlayException((body['msg'] ?? '加载失败，请稍后重试').toString(), code: code);
    }
    final Object? data = body['data'];
    final Object? nodes = data is Map<String, dynamic> ? data['nodes'] : null;
    if (data is! Map<String, dynamic> ||
        nodes is! List<dynamic> ||
        nodes.any((Object? e) => e is! Map<String, dynamic>)) {
      throw PlayException(kPlayRouteShapeBrokenTip);
    }
    return PlayNodesResult.fromJson(data);
  }

  /// validationMethod=6 偏好题组：题面只从服务端按节点下发。
  Future<PreferenceQuestionnaire> fetchPreference({
    int? activityId,
    int? topicId,
    required int nodeId,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/play/preference/$nodeId',
      queryParameters: _exactSession(activityId: activityId, topicId: topicId),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw PlayException(
        (body['msg'] ?? '偏好题加载失败').toString(),
        code: _ajaxCode(body),
      );
    }
    return PreferenceQuestionnaire.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 整组提交偏好选择。服务端自行求值并在最终回包的
  /// `progress` 中完成节点，App 不发 outcomeCode/targetNodeId。
  Future<PreferenceSubmission> submitPreference({
    int? activityId,
    int? topicId,
    required int nodeId,
    required Map<String, String> choices,
    String? reuseTagCode,
    RouteAdvanceToken? routeAdvance,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/preference/$nodeId/submit',
      data: <String, dynamic>{
        ..._exactSession(activityId: activityId, topicId: topicId),
        'choices': Map<String, String>.from(choices),
        if ((reuseTagCode ?? '').isNotEmpty) 'reuseTagCode': reuseTagCode,
        ..._routeJsonFields(routeAdvance),
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '偏好结果提交失败');
    return PreferenceSubmission.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  Future<PreferenceInheritedTag> confirmPreferenceTag(int tagId) =>
      _preferenceTagWrite('/api/play/tag/$tagId/confirm');

  Future<PreferenceInheritedTag> correctPreferenceTag(
    int tagId,
    String tagValue,
  ) => _preferenceTagWrite(
    '/api/play/tag/$tagId/correct',
    data: <String, dynamic>{'tagValue': tagValue},
  );

  Future<PreferenceInheritedTag> _preferenceTagWrite(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path, data: data);
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '标签没有保存成功');
    final PreferenceInheritedTag? tag = PreferenceInheritedTag.fromJson(
      body['data'],
    );
    if (tag == null) throw PlayException('标签状态不可用');
    return tag;
  }

  /// 幂等只读恢复当前路线状态。会话参数与 `/nodes` 一致且必须二选一。
  Future<PlayRouteState> fetchRouteState({
    int? activityId,
    int? topicId,
  }) async {
    final Map<String, dynamic> query = _exactSession(
      activityId: activityId,
      topicId: topicId,
    );
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/play/route-state',
      queryParameters: query,
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw PlayException(
        (body['msg'] ?? '路线状态加载失败').toString(),
        code: _ajaxCode(body),
      );
    }
    final PlayRouteState? state = PlayRouteState.fromJson(body['data']);
    if (state == null) throw PlayException('路线状态不可用');
    return state;
  }

  /// 节点前往途中 NPC 台词。会话参数与 `/api/play/nodes` 保持一致：
  /// 活动场次只发 activityId，自玩主题只发 topicId；空台词不创建 UI 占位。
  Future<String?> companionLine({int? activityId, int? topicId}) async {
    final Map<String, dynamic> query = <String, dynamic>{
      if ((activityId ?? 0) > 0) 'activityId': activityId,
      if ((activityId ?? 0) <= 0 && (topicId ?? 0) > 0) 'topicId': topicId,
    };
    if (query.isEmpty) throw PlayException('参数有误');
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/play/companionLine',
      queryParameters: query,
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw PlayException(
        (body['msg'] ?? '途中台词加载失败').toString(),
        code: _ajaxCode(body),
      );
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String line = (data['line'] ?? '').toString().trim();
    return line.isEmpty ? null : line;
  }

  /// 途中彩蛋首次触发上报。后端只返回 success，无奖励明细可供客户端发挥。
  Future<void> collectEgg({
    required int? topicId,
    required int eggId,
    required String content,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/egg/collect',
      data: FormData.fromMap(<String, dynamic>{
        if (topicId != null && topicId > 0) 'topicId': topicId.toString(),
        'eggId': eggId.toString(),
        'content': content,
      }),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw PlayException((body['msg'] ?? '彩蛋收集失败').toString());
    }
  }

  /// R14 旅程检定探测:`GET /api/play/encounter`(玩法 Beat 只读解析)。
  ///
  /// 返回 encounter 视图原始 map(含 `allowedActions` 与 `check` 题面);
  /// 成败判定与题面解析在 [JourneyCheckProblem.fromEncounter]。
  /// ⚠️ 检定不是通关闸:真源探测失败一律静默不打断已有路径,
  /// 调用方 catch 后不弹错、不重试(小程序 pages/play/index.js 同口径)。
  Future<Map<String, dynamic>> encounter({
    required int topicId,
    required int nodeId,
  }) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/play/encounter',
      queryParameters: <String, dynamic>{'topicId': topicId, 'nodeId': nodeId},
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '检定信息加载失败');
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  Future<JourneyCheckReceipt> _checkAction(
    String path, {
    required int topicId,
    required int nodeId,
    required String checkId,
    required String fallback,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(<String, dynamic>{
        'topicId': topicId.toString(),
        'nodeId': nodeId.toString(),
        'checkId': checkId,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, fallback);
    return JourneyCheckReceipt.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 掷骰:`POST /api/play/check/roll`(表单 topicId+nodeId+checkId,服务端幂等)。
  /// 失败抛 [PlayException] 携带后端原文 msg(如「这次检定已经结算过了」)。
  Future<JourneyCheckReceipt> rollCheck({
    required int topicId,
    required int nodeId,
    required String checkId,
  }) => _checkAction(
    '/api/play/check/roll',
    topicId: topicId,
    nodeId: nodeId,
    checkId: checkId,
    fallback: '掷骰没成功',
  );

  /// 花幸运重掷:`POST /api/play/check/reroll`(同 roll 的入参与幂等口径)。
  Future<JourneyCheckReceipt> rerollCheck({
    required int topicId,
    required int nodeId,
    required String checkId,
  }) => _checkAction(
    '/api/play/check/reroll',
    topicId: topicId,
    nodeId: nodeId,
    checkId: checkId,
    fallback: '重掷没成功',
  );

  /// 结算:`POST /api/play/check/settle`。结算后回执才带 text/failCostLabel;
  /// settle 幂等 —— 上局已结算时回读同一份回执(真源 `_recoverSettledCheck` 靠它)。
  Future<JourneyCheckReceipt> settleCheck({
    required int topicId,
    required int nodeId,
    required String checkId,
  }) => _checkAction(
    '/api/play/check/settle',
    topicId: topicId,
    nodeId: nodeId,
    checkId: checkId,
    fallback: '结算没成功',
  );

  /// 扫码打卡:后端用 code 反查节点(校验归属/报名/时间闸/线性解锁)→ 发分/通关。
  /// 失败抛 [PlayException](含后端 msg)。
  Future<CheckinReward> submitCheckin({
    required int activityId,
    required String code,
    RouteAdvanceToken? routeAdvance,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/checkin',
      data: FormData.fromMap(<String, dynamic>{
        'activityId': activityId.toString(),
        'code': code,
        ..._routeFormFields(routeAdvance),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '打卡失败');
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CheckinReward.fromJson(data);
  }

  Future<CheckinReward> submitTopicCheckin({
    required int topicId,
    required String code,
    RouteAdvanceToken? routeAdvance,
  }) async {
    return _topicReward('/api/play/checkin', <String, dynamic>{
      'topicId': topicId.toString(),
      'code': code,
      ..._routeFormFields(routeAdvance),
    }, '打卡失败');
  }

  /// 答题打卡:vm1 答案=文字(后端不区分大小写比对);vm3 答案=选项字母 A/B/C/D。
  /// 成功返回 data 同 checkin;失败抛 [PlayException](含后端原文 msg,
  /// 如 feedbackText、"答案不正确"、"该节点未配置答题"、"请先完成上一站")。
  Future<CheckinReward> submitAnswer({
    required int activityId,
    required int nodeId,
    required String answer,
    RouteAdvanceToken? routeAdvance,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/answer',
      data: FormData.fromMap(<String, dynamic>{
        'activityId': activityId.toString(),
        'nodeId': nodeId.toString(),
        'answer': answer.toString(),
        ..._routeFormFields(routeAdvance),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '答题失败');
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CheckinReward.fromJson(data);
  }

  Future<CheckinReward> submitTopicAnswer({
    required int topicId,
    required int nodeId,
    required String answer,
    RouteAdvanceToken? routeAdvance,
  }) async {
    return _topicReward('/api/play/answer', <String, dynamic>{
      'topicId': topicId.toString(),
      'nodeId': nodeId.toString(),
      'answer': answer,
      ..._routeFormFields(routeAdvance),
    }, '答题失败');
  }

  /// GPS 到达打卡:上报当前定位(gcj02 经纬度),后端按 Haversine 50m 围栏判定。
  /// 经纬度必须是已转好的 gcj02 坐标(geolocator 拿到的是 WGS84,调用方先转)。
  /// 成功返回 data 同 checkin;失败抛 [PlayException](含后端原文 msg,
  /// 如"请开启定位""还没到这一站附近""请先完成上一站""定位无效")。
  Future<CheckinReward> submitArrive({
    required int activityId,
    required int nodeId,
    required double longitude,
    required double latitude,
    RouteAdvanceToken? routeAdvance,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/arrive',
      data: FormData.fromMap(<String, dynamic>{
        'activityId': activityId.toString(),
        'nodeId': nodeId.toString(),
        'longitude': longitude.toString(),
        'latitude': latitude.toString(),
        ..._routeFormFields(routeAdvance),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '到达打卡失败');
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CheckinReward.fromJson(data);
  }

  Future<CheckinReward> submitTopicArrive({
    required int topicId,
    required int nodeId,
    required double longitude,
    required double latitude,
    RouteAdvanceToken? routeAdvance,
  }) async {
    return _topicReward('/api/play/arrive', <String, dynamic>{
      'topicId': topicId.toString(),
      'nodeId': nodeId.toString(),
      'longitude': longitude.toString(),
      'latitude': latitude.toString(),
      ..._routeFormFields(routeAdvance),
    }, '到达打卡失败');
  }

  /// 上传图片到 OSS:multipart 单文件,字段名固定为 'file'。
  /// 成功返回 OSS 地址(返回体顶层 body['url']);失败抛 [PlayException]
  /// (含后端原文 msg,如图片安全检查不过)。
  Future<String> uploadImage(String filePath) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/uploadOSS',
      data: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw PlayException(
        (body['msg'] ?? '上传失败').toString(),
        code: _ajaxCode(body),
      );
    }
    return body['url'].toString();
  }

  /// 社区帖文上传额外返回绑定当前用户、URL 与字节数的短期回执；
  /// 后续媒体登记不再信任客户端自报的任意网络地址。
  Future<CommunityMediaUpload> uploadCommunityImage(
    String filePath, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/uploadOSS',
      data: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath),
        'bizType': 'COMMUNITY_POST',
      }),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw PlayException(
        (body['msg'] ?? '上传失败').toString(),
        code: _ajaxCode(body),
      );
    }
    final upload = CommunityMediaUpload(
      url: '${body['url'] ?? ''}'.trim(),
      byteSize: (body['byteSize'] as num?)?.toInt() ?? 0,
      mimeType: '${body['mimeType'] ?? ''}'.trim(),
      receipt: '${body['uploadReceipt'] ?? ''}'.trim(),
    );
    if (!upload.valid) throw PlayException('上传回执缺失，请重新选择图片');
    return upload;
  }

  /// 拍照打卡(validationMethod==2):上报已上传到 OSS 的图片地址 picUrl。
  /// 成功返回 data 同 checkin;失败抛 [PlayException](含后端原文 msg)。
  Future<CheckinReward> submitPhoto({
    required int activityId,
    required int nodeId,
    required String picUrl,
    RouteAdvanceToken? routeAdvance,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/photo',
      data: FormData.fromMap(<String, dynamic>{
        'activityId': activityId.toString(),
        'nodeId': nodeId.toString(),
        'picUrl': picUrl,
        ..._routeFormFields(routeAdvance),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '拍照打卡失败');
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CheckinReward.fromJson(data);
  }

  /// App 传感器挑战(vm=7)完成结果。[activityId] / [topicId] 必须且
  /// 只能提供一个，整个请求体与 [payload] 均为 JSON 对象。
  ///
  Future<CheckinReward> submitSensorResult({
    int? activityId,
    int? topicId,
    required int nodeId,
    required String sensorType,
    required Map<String, dynamic> payload,
    RouteAdvanceToken? routeAdvance,
  }) async {
    if ((activityId == null) == (topicId == null)) {
      throw ArgumentError('activityId 与 topicId 必须且只能提供一个');
    }
    if (!_sensorResultTypes.contains(sensorType)) {
      throw ArgumentError.value(
        sensorType,
        'sensorType',
        '仅支持 still、steps、audio_clip',
      );
    }
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/sensor-result',
      data: <String, dynamic>{
        'activityId': ?activityId,
        'topicId': ?topicId,
        'nodeId': nodeId,
        'sensorType': sensorType,
        'payload': payload,
        ..._routeJsonFields(routeAdvance),
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '挑战结果提交失败');
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return CheckinReward.fromJson(data);
  }

  Future<CheckinReward> submitTopicPhoto({
    required int topicId,
    required int nodeId,
    required String picUrl,
    RouteAdvanceToken? routeAdvance,
  }) async {
    return _topicReward('/api/play/photo', <String, dynamic>{
      'topicId': topicId.toString(),
      'nodeId': nodeId.toString(),
      'picUrl': picUrl,
      ..._routeFormFields(routeAdvance),
    }, '拍照打卡失败');
  }

  Future<CheckinReward> _topicReward(
    String path,
    Map<String, dynamic> data,
    String fallback,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(data),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, fallback);
    return CheckinReward.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 结局:`POST /api/play/ending`(表单 activityId 或 topicId 二选一)。
  ///
  /// ⚠️ 一个节点都没走完时后端返回 `{opener:'', fragments:[]}` 且 **200** ——
  ///   那是「还没有故事」,不是错误。
  Future<PlayEnding> ending({int? activityId, int? topicId}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/ending',
      data: FormData.fromMap(<String, dynamic>{
        'activityId': ?activityId?.toString(),
        'topicId': ?topicId?.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw Exception((body['msg'] ?? '加载失败').toString());
    }
    return PlayEnding.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 解锁节点提示:`POST /api/play/hint/unlock`(表单 nodeId)。
  ///
  /// ★ **扣积分**(ApiPlayProgressController:1631 读 member.getPoint(),
  ///   不足报「积分不足」)。积分规则停用时 cost 为 0,免费直出。
  ///   返回 {hint1, hint2, cost}。
  Future<HintUnlockResult> unlockHint(int nodeId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/hint/unlock',
      data: FormData.fromMap(<String, dynamic>{'nodeId': nodeId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw PlayException(
        (body['msg'] ?? '解锁失败').toString(),
        code: _ajaxCode(body),
      );
    }
    return HintUnlockResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 城市定向谜题逐级提示。服务端先记录提示事实，再返回正文和新的分数上限。
  Future<PuzzleHintResult> requestPuzzleHint({
    int? activityId,
    int? topicId,
    required int nodeId,
    required int level,
  }) async {
    final Map<String, dynamic> session = _exactPlaySession(
      activityId: activityId,
      topicId: topicId,
    );
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/puzzle/hint',
      data: FormData.fromMap(<String, dynamic>{
        ...session,
        'nodeId': nodeId.toString(),
        'level': level.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw PlayException((body['msg'] ?? '提示暂时不可用').toString());
    }
    return PuzzleHintResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 查看城市定向谜题答案并以零解谜分辅助完成。
  Future<PuzzleRevealResult> revealPuzzle({
    int? activityId,
    int? topicId,
    required int nodeId,
    String? routeActionId,
    int? expectedRouteVersion,
  }) async {
    final Map<String, dynamic> session = _exactPlaySession(
      activityId: activityId,
      topicId: topicId,
    );
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/puzzle/reveal',
      data: FormData.fromMap(<String, dynamic>{
        ...session,
        'nodeId': nodeId.toString(),
        if (routeActionId != null && routeActionId.isNotEmpty)
          'routeActionId': routeActionId,
        if (expectedRouteVersion != null)
          'expectedRouteVersion': expectedRouteVersion.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw PlayException((body['msg'] ?? '暂时不能查看答案').toString());
    }
    return PuzzleRevealResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  Map<String, dynamic> _exactPlaySession({int? activityId, int? topicId}) {
    final bool hasActivity = (activityId ?? 0) > 0;
    final bool hasTopic = (topicId ?? 0) > 0;
    if (hasActivity == hasTopic) throw PlayException('参数有误');
    return <String, dynamic>{
      if (hasActivity) 'activityId': activityId.toString(),
      if (hasTopic) 'topicId': topicId.toString(),
    };
  }

  /// 我完成过的局:`POST /api/play/my-completed`。
  Future<List<CompletedPlay>> myCompleted() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/my-completed',
    );
    final body = resp.data ?? <String, dynamic>{};
    if (_ajaxCode(body) != 200) {
      throw Exception((body['msg'] ?? '加载失败').toString());
    }
    final raw = body['data'];
    return (raw is List ? raw : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(CompletedPlay.fromJson)
        .toList();
  }

  /// 门口游戏码落地:`POST /api/play/scan-entry`(表单 code=32 位 hex scene)。
  ///
  /// 真源 pages/index/index.js consumeDoorScene —— 未报名回主题购买页,
  /// 已报名回游玩页;只解析入口,不写打卡进度。失败(含未登录)抛
  /// [PlayException] 带后端原文 msg。
  Future<ScanEntryResult> scanEntry(String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/play/scan-entry',
      data: FormData.fromMap(<String, dynamic>{'code': code}),
    );
    final body = resp.data ?? <String, dynamic>{};
    _ensureAjaxSuccess(body, '这张码暂时打不开');
    return ScanEntryResult.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }

  Map<String, dynamic> _exactSession({int? activityId, int? topicId}) {
    final bool hasActivity = (activityId ?? 0) > 0;
    final bool hasTopic = (topicId ?? 0) > 0;
    if (hasActivity == hasTopic) {
      throw ArgumentError('activityId 与 topicId 必须且只能提供一个');
    }
    return <String, dynamic>{
      if (hasActivity) 'activityId': activityId,
      if (hasTopic) 'topicId': topicId,
    };
  }

  Map<String, String> _routeFormFields(RouteAdvanceToken? token) =>
      token == null
      ? const <String, String>{}
      : <String, String>{
          'routeActionId': token.actionId,
          'expectedRouteVersion': token.expectedRouteVersion.toString(),
        };

  Map<String, dynamic> _routeJsonFields(RouteAdvanceToken? token) =>
      token == null
      ? const <String, dynamic>{}
      : <String, dynamic>{
          'routeActionId': token.actionId,
          'expectedRouteVersion': token.expectedRouteVersion,
        };
}

class CommunityMediaUpload {
  const CommunityMediaUpload({
    required this.url,
    required this.byteSize,
    required this.mimeType,
    required this.receipt,
  });

  final String url;
  final int byteSize;
  final String mimeType;
  final String receipt;

  bool get valid =>
      url.isNotEmpty &&
      byteSize > 0 &&
      mimeType.isNotEmpty &&
      receipt.isNotEmpty;
}
