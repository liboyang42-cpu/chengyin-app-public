import '../models/coop_failure.dart';
import '../../core/network/request_session_scope.dart';
import '../../core/network/dio_client.dart';
import '../models/coop_pool.dart';
import '../models/coop_finance.dart';
import '../models/coop_candidate.dart';
import '../models/merchant_coop.dart' show CoopHandleAction;
import '../models/coop_invite.dart';

/// 合作池。对齐后端 `ApiCoopPoolController`(/api/coop/pool)。
///
/// ★ 这四个端点在**独立控制器** ApiCoopPoolController 里,不在 ApiCoopController。
///   我一度在后者里 grep 到 0 命中就判成"后端不存在" —— 是误判,已记进 memory。
class CoopApi {
  CoopApi(this._client);
  final DioClient _client;

  /// 合作池列表:`POST /api/coop/pool/list`。
  Future<CoopPool> pool() async {
    final data = await _post('/api/coop/pool/list');
    return CoopPool.fromJson(data);
  }

  /// 发起承接申请:`POST /api/coop/pool/apply`。
  Future<void> apply(int topicId) =>
      _post('/api/coop/pool/apply', <String, dynamic>{'topicId': topicId});

  /// 撤回申请:`POST /api/coop/pool/withdraw`。
  ///
  /// ★★ 键是 **topicId**,不是申请 id —— 2026-09-17 按小程序真源更正:
  ///   小程序 `pages/coop/list/index.js:420-424` 发的是 `{topicId}`,
  ///   且 `tests/unit/coop-list-inbox.test.js:71` 把这一点钉死
  ///   (`assert.deepEqual(JSON.parse(w.data), { topicId: 8 })`)。
  ///   原来这里发 `{id: ...}`,后端绑不到参数 —— 那种错**不报错**,
  ///   表现只是「撤回失败」,所以页面按钮看着在、点下去永远不成。
  Future<void> withdraw(int topicId) =>
      _post('/api/coop/pool/withdraw', <String, dynamic>{'topicId': topicId});

  /// 我发出的带队申请:`POST /api/coop/pool/mine` → 裸 List。
  ///
  /// ★ 与 [pool] 不是一条:那条只列**还开放可承接**的主题(池子),
  ///   这条列出全部申请记录(含已拒绝/已撤回/已回邀约)——
  ///   用池子当发件箱会让处理过的申请凭空消失
  ///   (小程序 tests/unit/coop-list-inbox.test.js「锁价/已处理的历史申请不会从
  ///     发件箱消失」就是在钉这一点)。
  Future<List<Map<String, dynamic>>> poolMine() =>
      _postRows('/api/coop/pool/mine', const <String, dynamic>{});

  /// 别人对我主题的带队申请:`POST /api/coop/pool/received` → 裸 List。
  ///
  /// 「收到的」口径 = 登录人即主题发布者;行上的 `scope=MERCHANT` 表示
  /// 这是商家员工在处理 owner 的主题,处理时要把它传回 /decline。
  Future<List<Map<String, dynamic>>> poolReceived() =>
      _postRows('/api/coop/pool/received', const <String, dynamic>{});

  /// 我发布主题的结算:`POST /api/coop/finance` → data.topics。
  Future<List<CoopFinanceRow>> finance() async {
    final data = await _post('/api/coop/finance');
    return ((data['topics'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(CoopFinanceRow.fromJson)
        .toList();
  }

  /// 某主题的候选池:`POST /api/coop/candidates`。
  ///
  /// ⚠️ **仅主题发布者可看**(后端 ApiCoopController:708)。
  ///   非发布者返回「仅主题发布者可查看候选池」—— 权限态,不是故障。
  Future<CoopCandidates> candidates(int topicId) async {
    final data = await _post('/api/coop/candidates', <String, dynamic>{
      'topicId': topicId,
    });
    return CoopCandidates.fromJson(data);
  }

  /// 确认候选:`POST /api/coop/candidates/confirm`。
  ///
  /// ★ 2026-08-19 修:body key 原来写的是 `regId`,但后端读的是
  ///   `body.get("registrationId")`(ApiCoopController.java:766)—— key 对不上,
  ///   之前调用这个方法恒得到「缺少报名」,与传的 id 无关。此方法此前零调用方,
  ///   没有任何界面因这处改动而变化。
  Future<void> confirmCandidate(int registrationId) => _post(
    '/api/coop/candidates/confirm',
    // ⚠️ key 必须是 **registrationId**:后端读的是
    //   `body.get("registrationId")`(ApiCoopController:766)。
    //   原来发的是 'regId',于是**每次调用都返回「缺少报名」**,
    //   跟传的 id 对不对无关。
    <String, dynamic>{'registrationId': registrationId},
  );

  /// 收到的承接报名(跨主题聚合):`POST /api/coop/candidates/received` → `data.rows`。
  ///
  /// ★ 与 [poolReceived] **不是一条**:那条是**俱乐部**申请带队,
  ///   这条是**商家**报名承接我主题的节点(真源 `pages/coop/list/index.js:354`)。
  ///   两路在界面上各自结算 —— 报名那一块加载失败不能把带队申请也整块打没。
  ///
  /// ⚠️ 响应外层是 `{rows, hasMore}`(后端 ApiCoopController.candidatesReceived),
  ///   不是裸 List —— 按裸 List 解析会恒空,而空列表看着像"没人报名"。
  Future<List<Map<String, dynamic>>> receivedRegistrations() async {
    final Map<String, dynamic> data = await _post(
      '/api/coop/candidates/received',
      const <String, dynamic>{},
    );
    return ((data['rows'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 婉拒承接报名:`POST /api/coop/candidates/reject`。
  ///
  /// ★★ 键是 **registrationId**(后端 :1194 `body.get("registrationId")`)——
  ///   与 [declineApply](婉拒**俱乐部带队申请**,键 applyId、走 `/pool/decline`)
  ///   是两条不同的路:报名=意向,婉拒后对方可修改后重新报名。
  Future<void> rejectCandidate(int registrationId) => _post(
    '/api/coop/candidates/reject',
    <String, dynamic>{'registrationId': registrationId},
  );

  /// 婉拒俱乐部承接申请:`POST /api/coop/pool/decline`。
  ///
  /// ★★ 键是 **applyId**(可带 scope)—— 同 2026-09-17 更正:
  ///   小程序两处调用都发 `{applyId[, scope]}`
  ///   (`pages/coop/list/index.js:456`、`pages/coop/candidates/index.js:402-406`)。
  ///
  /// ⚠️ [scope] 是「商家员工处理 owner 主题上的申请」带的归属标记(`MERCHANT`),
  ///   必须原样回传 —— 漏了会被判成无权处理。
  Future<void> declineApply(int applyId, {String? scope}) =>
      _post('/api/coop/pool/decline', <String, dynamic>{
        'applyId': applyId,
        if (scope != null && scope.isNotEmpty) 'scope': scope,
      });

  /// 发起合作邀约:`POST /api/coop/invite`。
  ///
  /// ⚠️ 后端一次只收**一个** toId。多选时由调用方逐个调,
  ///   并**逐个处理成败** —— 不能一个失败就把整批说成失败。
  Future<void> invite(CoopInviteForm form, CoopInviteTarget target) =>
      _post('/api/coop/invite', form.toJson(target));

  /// 处理协作邀请(接受/拒绝/取消):`POST /api/coop/handle`。
  ///
  /// ★★ 规则见 [CoopHandleAction] —— 谁能做什么取决于
  ///   **当前状态 + 你是发起方还是受邀方**。界面要按那张表露按钮。
  ///
  /// ⚠️ 取消一个**已接受**的合作必须填 reason(后端拒空);
  ///   取消一个还在待确认的则不需要。
  ///
  /// ★ 历史商家节点邀约会被拒:「历史商家节点邀约仅供查看，不能再处理」——
  ///   那是正常态,照原文显示,别给重试。
  ///
  /// ★★ 理由的**字段名按动作分岔**,不是一个 key 通吃 —— 后端
  ///   `ApiCoopController.handle` 取消(3)读 `message`,接受/拒绝(1/2)读
  ///   `handleReason`,两个字段在 `CoopInvite` 上互相独立(小程序审查记过同型的
  ///   C1:取消发 `handleReason` 恒回「取消已接受的合作需填写理由」)。
  ///   ⇒ 统一发一个 key 的后果是**接受/拒绝时写的那句回复被静默丢掉** ——
  ///     和 `review/save` 发 content 被 Jackson 丢掉是同一类不报错的错。
  Future<void> handleInvite({
    required int inviteId,
    required CoopHandleAction action,
    String? reason,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'id': inviteId,
      // status 就是**目标状态**,不是动作码。
      'status': action.wire,
    };
    // 空理由不发空串:后端把空串当「没填」,发过去只会让它回「需填写理由」。
    if (reason != null && reason.trim().isNotEmpty) {
      body[action == CoopHandleAction.cancel ? 'message' : 'handleReason'] =
          reason;
    }
    await _post('/api/coop/handle', body);
  }

  /// 锁价后缴纳合作保证金:`POST /api/coop/deposit/create/app`。
  ///
  /// 返回值保持服务端支付参数原样，只把 value 规范成 String；签名、金额和
  /// prepayId 都不能由客户端补算。调用方必须先确认拿到 App 支付六元组再调微信。
  Future<Map<String, String>> createDeposit(int inviteId) async {
    final data = await _post('/api/coop/deposit/create/app', <String, dynamic>{
      'inviteId': inviteId,
    });
    return data.map((key, value) => MapEntry(key, '${value ?? ''}'));
  }

  /// 回读保证金服务端终态:`POST /api/coop/deposit/status`。
  ///
  /// 微信 SDK 的 success / cancelled / failed 都不是入账真源。
  /// 未知值保持 unknown，不猜成 failed 或 success。
  Future<String> depositStatus(int inviteId) async {
    final data = await _post('/api/coop/deposit/status', <String, dynamic>{
      'inviteId': inviteId,
    });
    final String status = data['paymentStatus']?.toString() ?? 'unknown';
    return const <String>{
          'success',
          'pending',
          'failed',
          'unknown',
        }.contains(status)
        ? status
        : 'unknown';
  }

  /// 重试保证金退款:`POST /api/coop/deposit/refund/retry`。
  ///
  /// ★ 涉资链路的兜底入口,判据照真源 `pages/coop/list/index.js:909-928`:
  ///   **只有「可确认的成功」才算回执** —— code 200 且 `data.refundState`
  ///   是字符串且 `msg` 非空,三者缺一就不算。网络失败 / 状态异常一律回
  ///   「退款结果暂无法确认，请先核对，勿重复提交」—— 状态未知时催用户
  ///   去核对,而不是让他反复点重试把退款打重。
  ///   成功时返回服务端 msg 原话,由调用方作为 toast 显示。
  Future<String> retryDepositRefund(int inviteId) async {
    Map<String, dynamic> res;
    try {
      final resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/coop/deposit/refund/retry',
      options: RequestSessionScope.options(),
        data: <String, dynamic>{'inviteId': inviteId},
      );
      res = resp.data ?? const <String, dynamic>{};
    } catch (_) {
      // 真源的 fail / successStatusAbnormal 两个分支都是这一句。
      throw CoopFailure.local(CoopFailureKind.refundUnknown, '退款结果暂无法确认，请先核对，勿重复提交');
    }
    final String msg = res['msg'] is String ? res['msg'] as String : '';
    final int? code = res['code'] is num ? (res['code'] as num).toInt() : null;
    final rawData = res['data'];
    final Object? refundState = rawData is Map ? rawData['refundState'] : null;
    if (code == 200 && refundState is String && msg.trim().isNotEmpty) return msg;
    if (code != 200) {
      // failureText(res, '退款重试失败'):后端原话优先,没有才用兜底。
      throw msg.trim().isNotEmpty ? CoopFailure.server(msg)
          : const CoopFailure.local(CoopFailureKind.refundRetry, '退款重试失败');
    }
    throw CoopFailure.local(CoopFailureKind.refundUnknown, '退款结果暂无法确认，请先核对，勿重复提交');
  }

  // ---------------------------------------------- 常备权益模板

  /// 我的常备权益模板列表:`POST /api/coop/perk-template/list`。
  Future<List<Map<String, dynamic>>> perkTemplates() =>
      _postRows('/api/coop/perk-template/list', <String, dynamic>{});

  /// 新增常备权益模板:`POST /api/coop/perk-template/save` → `data.id`。
  ///
  /// ⚠️ 后端五道校验,每条的原话都带着修复指引,必须原文显示:
  ///   · 名称必填 · perkType ∈ [0,2] · 零售价为正数且 ≤99999999.99、最多两位小数
  ///   · 成本价 0~99999999.99、最多两位小数 · quota 必须是正整数
  /// ★ 后端**只新增不更新**(`body.setId(null)`)—— 界面别做成"编辑"。
  ///   传了 id 也会被丢掉,结果是又多一条模板,而用户以为改了原来那条。
  Future<int> savePerkTemplate(Map<String, dynamic> template) async {
    final Map<String, dynamic> d = await _post(
      '/api/coop/perk-template/save',
      template,
    );
    final Object? id = d['id'];
    if (id is! num) throw CoopFailure.local(CoopFailureKind.templateId, '模板没返回编号 —— 别当保存成功了');
    return id.toInt();
  }

  /// 删除常备权益模板:`POST /api/coop/perk-template/delete`。
  Future<void> deletePerkTemplate(int id) async {
    await _post('/api/coop/perk-template/delete', <String, dynamic>{'id': id});
  }

  // ---------------------------------------------- 供给申报

  /// 从常备模板申报本次供给:`POST /api/coop/perks/attach` → `data.count`。
  Future<int> attachPerks({
    required int inviteId,
    required List<int> templateIds,
  }) async {
    final Map<String, dynamic> d = await _post(
      '/api/coop/perks/attach',
      <String, dynamic>{'inviteId': inviteId, 'templateIds': templateIds},
    );
    return (d['count'] as num?)?.toInt() ?? 0;
  }

  /// 某邀约已申报的供给:`POST /api/coop/perks/list`。
  ///
  /// ★★ **成本价 `unitCost` 只有受邀方本人看得到** —— 后端对发起方主动
  ///   `perk.setUnitCost(null)`。那是商业机密,不是"这条没填"。
  ///   ⇒ 前端**不许把它兜成 0 或「¥0.00」** —— 那等于对发起方谎称
  ///     对方的成本是零。拿不到就整行不显示。
  ///
  /// ★ 非合作双方调用会拿到 `error("无权查看")`(防 IDOR),照原文显示。
  Future<List<Map<String, dynamic>>> perksOfInvite(int inviteId) => _postRows(
    '/api/coop/perks/list',
    <String, dynamic>{'inviteId': inviteId},
  );

  // ---------------------------------------------- 入驻章节(③ 开卖前置)

  /// 商家入驻章节,落一行生效供给:`POST /api/coop/offer/enroll`。
  ///
  /// ★★ 这条是 **③ 自由探索能不能卖票的前置**。后端原注释:
  ///   「在此之前 merchant_chapter_offer 零 insert 入口 ⇒ 供给池恒空
  ///     ⇒ reserveEntitlements 算出的容量恒 ≤0
  ///     ⇒ 任何有章节的 ③ 主题购票 100% 被拒」。
  ///   也就是说没有它,玩家侧表现成"这个主题永远买不到票",而且不报任何错。
  ///
  /// ⚠️ 服务端会把 id / topicId / merchantId / quotaUsed / status 一律**清掉**
  ///   (防前端越权塞值)。所以这里也不发这五个 —— 发了不只是白发,
  ///   更会在界面上做出"可以选主题/改状态"的错觉。
  Future<Map<String, dynamic>> enrollChapterOffer(
    Map<String, dynamic> offer,
  ) async {
    const List<String> serverOwned = <String>[
      'id',
      'topicId',
      'merchantId',
      'quotaUsed',
      'status',
    ];
    final Map<String, dynamic> body = <String, dynamic>{
      for (final MapEntry<String, dynamic> e in offer.entries)
        if (!serverOwned.contains(e.key)) e.key: e.value,
    };
    return _post('/api/coop/offer/enroll', body);
  }

  /// 圈层供给「无变化,重新确认」:`POST /api/coop/offer/circle-supply/reconfirm-current`。
  ///
  /// ★ 商家**不用重填表单**:服务端复制当前快照、只刷新确认时间。
  ///   传的是 **offerId**(供给编号),不是申请 id —— 后端读
  ///   `body.getOfferId()`(ApiCoopController:701);
  ///   真源 `pages/topic/merchantinfo/merchantinfo.js:445` body 也只有 `{offerId}`。
  ///
  /// ⚠️ 与 `/api/coop/offer/circle-supply/reconfirm` 不是同一条:那条要商家把整份
  ///   供给档案再发一遍,小程序产品代码从没用过它。它续的是**当前那条 offer**
  ///   (current),不是重新提交一份 —— 别拿 [enrollChapterOffer] 去顶:
  ///   `offerActive` 的申请在真源里连提交入口都不给(会先弹「承接状态已变化」)。
  Future<void> reconfirmCircleSupply(int offerId) => _post(
    '/api/coop/offer/circle-supply/reconfirm-current',
    <String, dynamic>{'offerId': offerId},
  );

  /// 暂停自己的这份圈层供给:`POST /api/coop/offer/circle-supply/pause`。
  ///
  /// ★ 暂停 ≠ 删除:后端只把这份供给下线,历史记录保留
  ///   (小程序确认弹窗原话「历史记录不会删除」)。
  ///   真源 `pages/topic/merchantinfo/merchantinfo.js:466`:body 只有 `{offerId}`;
  ///   这句说明得由调用界面先给,后端成功后只回码不回文案。
  Future<void> pauseCircleSupply(int offerId) => _post(
    '/api/coop/offer/circle-supply/pause',
    <String, dynamic>{'offerId': offerId},
  );

  // ---------------------------------------------- 互评与履约率

  /// 提交合作互评:`POST /api/coop/review/save`。
  ///
  /// ⚠️ rating 必须 1~5(后端 `请打 1~5 分`),且**不能评价自己**。
  ///
  /// ★ 2026-08-19 修:body key 原来写的是 `content`,但后端 `CoopReview` 域对象
  ///   (Jackson 按 getter/setter 反序列化)的字段是 `comment`
  ///   (CoopReview.java:19)——评语会被后端**静默丢弃**:rating 照样保存成功,
  ///   用户以为评语也存上了,其实没有。此方法此前零调用方,没有任何界面因这处
  ///   改动而变化。
  Future<void> saveReview({
    required int topicId,
    required int toId,
    required int rating,
    String? content,
  }) async {
    await _post('/api/coop/review/save', <String, dynamic>{
      'topicId': topicId,
      'toId': toId,
      'rating': rating,
      // ⚠️ key 必须是 **comment**:后端域对象 `CoopReview.comment`
      //   (CoopReview.java:19),Jackson 按属性名反序列化。
      //   原来发的是 'content' ⇒ 评语被**静默丢弃**:评分照样成功,
      //   用户以为评语也存上了,其实没有。三条里这条最坏 —— 它不报错。
      'comment': ?content,
    });
  }

  /// 某人的评价摘要:`POST /api/coop/review/summary` → `{summary, reviews}`。
  Future<Map<String, dynamic>> reviewSummary(int toId) =>
      _post('/api/coop/review/summary', <String, dynamic>{'toId': toId});

  /// 履约率:`POST /api/coop/credit`。
  ///
  /// ★ 不传 memberId = 查自己;传了 = 查他人(主页展示合作方履约率)。
  Future<Map<String, dynamic>> creditSummary({int? memberId}) =>
      _post('/api/coop/credit', <String, dynamic>{'memberId': ?memberId});

  // ---------------------------------------------- 投诉

  /// 可投诉的主题:`POST /api/coop/complaint/topics`。
  ///
  /// ★★ **必须用这一条作为投诉页的选择源**,不要拿「我参与的」列表顶替。
  ///   后端注释记了两个真库实测出来的坑:
  ///   ① 那条链路末端会砍掉结束超过 7 天的主题(订单列表的视觉收纳规则),
  ///      而投诉本就是事后行为、受理口没有时间窗
  ///      ⇒ 玩家选不到、后端却允许;
  ///   ② 那条链路只对 owner_type=1 挂主题,活动单两个取 id 的来源全空,
  ///      ③ 自由探索玩家**整条选不到**。
  ///   选择源与受理口读的是同一份判据,换一个就必然漂。
  Future<List<Map<String, dynamic>>> complainableTopics() =>
      _postRows('/api/coop/complaint/topics', <String, dynamic>{});

  /// 提交投诉:`POST /api/coop/complaint/report`。
  ///
  /// ★★ 后端**只信任 topicId + reason**;过错方 / 垫付额 / 过错比例 /
  ///   扣划额 / status / handler 一律由客服后台设,**绝不从 body 取**。
  ///   ⇒ 界面上不许出现"选择过错方""填写赔付金额"这类输入 ——
  ///     填了也不生效,而用户会以为自己已经索赔了。
  ///
  /// ⚠️ 两种正常拒绝,都要原文显示:
  ///   · 「仅本主题已支付参与者可投诉」(非参与者 / 已退款)
  ///   · 「你对该主题已有处理中的投诉」(防重复建单)
  Future<Map<String, dynamic>> reportComplaint({
    required int topicId,
    required String reason,
  }) => _post('/api/coop/complaint/report', <String, dynamic>{
    'topicId': topicId,
    'reason': reason,
  });

  /// data 是裸 List 的那几条共用。
  Future<List<Map<String, dynamic>>> _postRows(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path, data: body, options: RequestSessionScope.options());
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      final message = res['msg'];
      throw message is String ? CoopFailure.server(message)
          : const CoopFailure.local(CoopFailureKind.operation, '操作失败');
    }
    return ((res['data'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      options: RequestSessionScope.options(),
      data: body ?? <String, dynamic>{},
    );
    final data = resp.data ?? <String, dynamic>{};
    if ((data['code'] as num?)?.toInt() != 200) {
      final message = data['msg'];
      throw message is String ? CoopFailure.server(message)
          : const CoopFailure.local(CoopFailureKind.operation, '操作失败');
    }
    return (data['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 联系合作方:`POST /api/coop/contact`(id = 邀约 id)→ `{conversationId}`。
  ///
  /// 合作达成后，邀约详情的「联系对方」入口取/建 1:1 会话（幂等）。
  ///
  /// ⚠️ 后端有五道闸,文案都很具体,**一律原样透传**:
  ///   「仅已合作可联系」(status != 1)、「无权联系」(既不是发起方也不是接收方)、
  ///   「历史商家节点邀约仅供查看,不能再创建会话」、「对方暂不可联系」、
  ///   「邀约不存在」。换成笼统的「联系失败」,用户完全不知道该怎么办 ——
  ///   尤其「仅已合作可联系」是在告诉他"先把合作谈成"。
  Future<int> contact(int inviteId) async {
    // _post 已经把 code!=200 抛成带后端原话的异常了 —— 五道闸的文案照样透传。
    final Map<String, dynamic> data = await _post(
      '/api/coop/contact',
      <String, dynamic>{'id': inviteId},
    );
    final int? cid = (data['conversationId'] as num?)?.toInt();
    if (cid == null || cid <= 0) {
      throw CoopFailure.local(CoopFailureKind.conversation, '会话创建失败,请稍后再试');
    }
    return cid;
  }

  /// 我的协作邀请(**发出的 + 收到的**):`POST /api/coop/list`。
  ///
  /// ⚠️ 一个列表里混着两个方向 —— 界面必须分得开「我邀请别人」和「别人邀请我」,
  ///   两者的下一步动作完全不同(前者等回复,后者要处理)。
  /// 我的协作邀请(**发出的 + 收到的**):`POST /api/coop/list`。
  ///
  /// ⚠️ 一个列表里混着两个方向 —— 界面必须分得开「我邀请别人」和「别人邀请我」,
  ///   两者的下一步动作完全不同(前者等回复,后者要处理)。
  ///
  /// ★ 2026-08-19 修:此前实现读 `data['rows']`,注释称「走 getDataTable」——
  ///   查了 ApiCoopController.list(:880-962)才发现是错的:它返回的是裸 Map
  ///   `{sent, received, slots}`(AjaxResult.success(d)),根本没有分页 rows 这层。
  ///   照原实现调用只会拿到恒空列表。此方法此前零调用方,没有任何界面因这处
  ///   改动而变化。
  /// ★★ 原样返回整个 `{sent, received, slots}`,**不在这一层拆**。
  ///   我一度改成「返回打好 direction 标的扁平列表 + 另一个 inviteSlots()」——
  ///   那样 slots 得**再打一次同样的请求**(我自己在注释里写了这条,
  ///   然后实现里正是这么干的)。一次响应的三半,拆开取就是白打请求。
  ///   ⇒ 由调用方从这一个 Map 里取三样。
  Future<Map<String, dynamic>> inviteList() =>
      _post('/api/coop/list', <String, dynamic>{});

  /// 商家结算工作台(履约率 + 结算记录):`POST /api/coop/mybiz`。
  Future<Map<String, dynamic>> myBiz() async {
    return _post('/api/coop/mybiz', <String, dynamic>{});
  }
}
