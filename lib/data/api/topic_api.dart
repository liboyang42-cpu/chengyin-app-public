import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/topic.dart';
import '../models/pricing.dart';
import '../models/infomation.dart';
import '../models/xp_budget.dart';

/// 主题(路线)接口。对齐后端 `ApiTopicController`(/api/topic)。
class TopicApi {
  TopicApi(this._client);
  final DioClient _client;

  /// 玩法资讯列表:`POST /api/common/infomation_list`。
  ///
  /// ★ 只返回 **usable** 的条目 —— 判据见 Infomation.usable
  ///   (标题空 / 正文空 / 纯数字标题且无区分副标)。
  ///   ⚠️ 那**不是「过滤数字」**:`2024 · 年度城市定向回顾` 要保留。
  Future<List<Infomation>> infomations() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/infomation_list',
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final raw = body['data'];
    final rows = raw is List
        ? raw
        : (raw is Map<String, dynamic>
              ? (raw['rows'] as List<dynamic>? ?? const <dynamic>[])
              : const <dynamic>[]);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Infomation.fromJson)
        .where((Infomation x) => x.usable)
        .toList();
  }

  /// 资讯详情:`POST /api/common/infomation_detail`(表单 id)。
  ///
  /// ⚠️ 后端**不做可读性过滤**(那是列表侧 usable 干的事),
  ///   所以详情页拿到空正文时要自己兜底,不能假设一定有内容。
  Future<Infomation> infomationDetail(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/infomation_detail',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '打不开这篇');
    }
    return Infomation.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 我喜欢的主题:`POST /api/topic/like_list`。
  ///
  /// 与小程序 `pages/mylike` 一样走 RuoYi 分页，列表在 `data.rows`；
  /// 不能把第二页误当成裸数组，否则收藏超过一页时用户永远看不到后面的主题。
  Future<List<Topic>> likeList({int pageNum = 1, int pageSize = 10}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/like_list',
      data: FormData.fromMap(<String, dynamic>{
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    final raw = body['data'];
    final rows = raw is Map<String, dynamic>
        ? raw['rows'] as List<dynamic>? ?? const <dynamic>[]
        : (raw is List ? raw : const <dynamic>[]);
    return rows.whereType<Map<String, dynamic>>().map(Topic.fromJson).toList();
  }

  /// 收藏 / 取消收藏(切换):`POST /api/topic/like`(表单 id)。
  ///
  /// ⚠️ 后端是**切换**语义,不是"设为已收藏" —— 重复调会来回翻。
  ///   调用方不要在失败后自动重试,那会把状态翻回去。
  Future<void> toggleLike(int topicId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/like',
      data: FormData.fromMap(<String, dynamic>{'id': topicId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
  }

  /// 主办方取消主题(全额退款给所有已付款玩家):`POST /api/topic/cancel`。
  ///
  /// [C8-05] 停售 + 已付款全额退 + 逐场取消。个人主办传空 scope;
  ///   商家主办传 MERCHANT。俱乐部主题不走这里(走俱乐部「结束主题」)。
  /// ★★ 成功返回的那句话**必须原样显示**给主办方 —— 后端在 msg 里区分了
  ///   退了几笔 / 一笔没退 / 含已核销票要人工跟进(与活动取消同一套文案拼装)。
  /// ⚠️ reason 必填,后端空值直接拒;它会展示给已付款的玩家。
  Future<String> cancel({
    required int topicId,
    required String reason,
    String? scope,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/cancel',
      data: FormData.fromMap(<String, dynamic>{
        'id': topicId.toString(),
        'reason': reason,
        if (scope != null && scope.isNotEmpty) 'scope': scope,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '取消失败');
    }
    return (body['msg'] as String?) ?? '主题已取消';
  }

  /// 取消主题前预览:`POST /api/topic/cancel_preview`(表单 id / scope)。
  ///
  /// 返回将被全额退款的已付款玩家人数(N 由服务端按与取消同一套授权算)。
  /// ⚠️ 确认框必须写明「将给 N 位已付款玩家全额退款」;拿不到就不弹、不发取消。
  Future<int> cancelPreview({required int topicId, String? scope}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/cancel_preview',
      data: FormData.fromMap(<String, dynamic>{
        'id': topicId.toString(),
        if (scope != null && scope.isNotEmpty) 'scope': scope,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '暂时算不出退款人数，请稍后重试');
    }
    final Object? data = body['data'];
    final Object? raw = data is Map<String, dynamic>
        ? data['paidPlayers']
        : null;
    final int? n = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    if (n == null || n < 0) {
      throw Exception((body['msg'] as String?) ?? '暂时算不出退款人数，请稍后重试');
    }
    return n;
  }

  /// 定价预览:`POST /api/topic/pricing/preview`(JSON body)。
  ///
  /// ★ 资金路径。地板缺失时抛 [PricingIncompleteException] 而不是当 0 放行 ——
  ///   当 0 会让「确认终价并开售」在一个算不出成本的主题上放行。
  Future<PricingPreview> pricingPreview({
    required int topicId,
    required PricingSubType subType,
    double? leadCost,
    int? teamSize,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/pricing/preview',
      data: <String, dynamic>{
        'topicId': topicId,
        'subType': subType.wire,
        if (subType == PricingSubType.guided) 'leadCost': leadCost,
        if (subType == PricingSubType.guided) 'teamSize': teamSize,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw Exception((body['msg'] as String?) ?? '定价信息加载失败');
    }
    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) throw const PricingIncompleteException();
    return PricingPreview.fromJson(data);
  }

  /// 确认终价并开售:`POST /api/topic/pricing/confirm`。
  ///
  /// ⚠️ 这一步之后主题就**开售**了,是不可轻易撤销的动作。
  Future<void> pricingConfirm({
    required int topicId,
    required PricingSubType subType,
    required num finalPrice,
    double? leadCost,
    int? teamSize,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/pricing/confirm',
      data: <String, dynamic>{
        'topicId': topicId,
        if (subType == PricingSubType.guided) 'guidedPrice': finalPrice,
        if (subType == PricingSubType.guided) 'leadCost': leadCost,
        if (subType == PricingSubType.guided) 'teamSize': teamSize,
        if (subType == PricingSubType.self) 'selfPrice': finalPrice,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw Exception((body['msg'] as String?) ?? '确认失败');
    }
  }

  /// 主题列表:`POST /api/topic/list`。
  /// isMy=0 取所有(公开,未登录可用);1 取我发布的。分页由后端 startPage。
  Future<List<Topic>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    bool recommend = false,
    int pageNum = 1,
    int pageSize = 10,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/list',
      data: FormData.fromMap(<String, dynamic>{
        'is_my': isMy.toString(),
        'keyword': ?keyword,
        'category_id': ?categoryId,
        if (recommend) 'is_recommend': '1',
        // RuoYi startPage() 自动读取 pageNum/pageSize
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    // 后端 AjaxResult.success(getDataTable(list)) → 列表在 data.rows
    final data = body['data'];
    final list =
        (data is Map<String, dynamic>
            ? data['rows'] as List<dynamic>?
            : null) ??
        (body['rows'] as List<dynamic>?) ??
        <dynamic>[];
    return list
        .map((dynamic e) => Topic.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 路线详情:`POST /api/topic/info-to-user`。
  Future<TopicDetail> detail(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/info-to-user',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return TopicDetail.fromJson(data);
  }

  /// 商家可见投影的路线详情:`POST /api/topic/info-to-merchant`(表单 id)。
  ///
  /// M-12 降级位:商家浏览「招商中、但尚未对玩家上架」的主题时,
  /// 玩家接口 [detail] 判不存在(回包 `name` 为空),这条与招商列表同口径。
  /// 已上架主题仍走玩家接口(带评分/评论/票务),不反过来了 ——
  /// 商家投影没有那些玩家侧字段(后端 `selectMerchantVisibleCmsTopicById`)。
  Future<TopicDetail> detailForMerchant(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/info-to-merchant',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '路线详情读取失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return TopicDetail.fromJson(data);
  }

  /// 评价主题:`POST /api/comment/add`，owner_type=1 是主题。
  /// 评分与正文是同一次用户意图，缺一都不提交；成功后调用方重拉详情对账。
  Future<void> addReview({
    required int topicId,
    required int rating,
    required String contents,
    List<String> images = const <String>[],
  }) async {
    if (rating < 1 || rating > 5 || contents.trim().isEmpty) {
      throw ArgumentError('评分和评价内容不能为空');
    }
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/comment/add',
      data: FormData.fromMap(<String, dynamic>{
        'owner_type': '1',
        'owner_id': topicId.toString(),
        'rating': rating.toString(),
        'contents': contents.trim(),
        if (images.isNotEmpty) 'img_arr': images.join(';'),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '评价失败');
    }
  }

  /// 主题 XP 预算总览:`POST /api/topic/xp-budget`(表单 topic_id)。
  ///
  /// ★ 发布前的 budget-bar。**App 此前完全没接** —— 创作者看不到自己分了多少 XP、
  ///   还剩多少、有没有超,只能等**提交之后**被后端拒。
  ///
  /// ⚠️ 是否超预算**以后端的 `over` 为准**,不要前端自己比大小:
  ///   边界(相等算不算超)和将来可能的豁免规则都在服务端。
  Future<XpBudget> xpBudget(int topicId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/xp-budget',
      data: FormData.fromMap(<String, dynamic>{'topic_id': topicId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '预算读取失败');
    }
    return XpBudget.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 移交主题给俱乐部承接:`POST /api/topic/transfer-to-club`
  /// (表单 topicId / clubId)→ `data.newTopicId`。
  ///
  /// ★★ **不是"改个归属"** —— 后端 summary 原话:
  ///   「**复制一份新草稿**挂该俱乐部,**原主题下架**;发起人保留所有权」。
  ///   ⇒ 文案必须说清这三件事同时发生。写成「已移交」会让人以为
  ///     原来那个主题还在、只是换了个人管 —— 而它已经下架了。
  ///
  /// ★ 后端的槽模型(注释原话):内容槽留发起人(策划权+票款),
  ///   组织槽给俱乐部(只带队,**不能改内容**)。
  ///   所以"移交"之后发起人并没有失去这个主题。
  ///
  /// ⚠️ 两道闸,拒绝话术自带指引,原文透传:
  ///   · 「无权移交该主题」(不是创建者本人)
  ///   · 「需为该俱乐部主理人,或先获得该俱乐部的合作邀约通过,才能移交承接」
  Future<int> transferToClub({
    required int topicId,
    required int clubId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/transfer-to-club',
      data: FormData.fromMap(<String, dynamic>{
        'topicId': topicId.toString(),
        'clubId': clubId.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '移交失败');
    }
    final Object? id = (body['data'] as Map<String, dynamic>?)?['newTopicId'];
    if (id is! num) {
      throw Exception('没拿到新主题号 —— 别当移交成功了');
    }
    return id.toInt();
  }

  /// Beta 转正:`POST /api/topic/beta/graduate`(表单 topicId)。
  ///
  /// 快照 `pages/topic/index/index.js:782`:入口只在 `betaFlag==1` 时存在,
  /// 且仅主题作者(isOwner)点得到;二次确认后才调 —— 转正是不可逆的
  /// (清 `beta_flag`,主题从此不挂 Beta 标识)。
  ///
  /// ★ 服务端 `WHERE beta_flag=1` 才清:重复点击/并发只会成功一次,
  ///   失败按「不在 Beta 期」回话,**原文透传**,别改写成「转正失败请重试」。
  Future<void> graduateBetaTopic(int topicId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/beta/graduate',
      data: FormData.fromMap(<String, dynamic>{'topicId': topicId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '转正失败');
    }
  }

  /// 本主题的招商章节:`POST /api/topic/merchant-recruitment-chapters`
  /// (表单 id = 主题 id)。
  Future<List<Map<String, dynamic>>> merchantRecruitmentChapters(
    int topicId,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/merchant-recruitment-chapters',
      data: FormData.fromMap(<String, dynamic>{'id': topicId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '章节读取失败');
    }
    final Object? data = body['data'];
    return (data is List ? data : <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}
