import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/club_topic_ops.dart';
import 'club_api.dart' show ClubApiException;
import 'club_ops_api.dart' show ensureClubOpsOk;

/// 俱乐部 · 主题运营(4-B)接口层,对齐小程序
/// `pages/club/topic-detail`、`pages/club/topic-story` 消费的端点。
///
/// 口径与 `club_ops_api.dart` 完全一致(同一份 `ensureClubOpsOk`):
/// 全部 `POST`;`@RequestBody` 端点一律发 JSON(裸 FormData 会 415 且**照样回 HTTP 200**,
/// 小程序在 topic-node-answer 上踩过这个零告警哑火,注释见下)。
///
/// ⚠️ `/api/topic/info-to-user` 是唯一一个吃**表单参数**的端点
///   (后端 `topicInfo(String id)` 从表单读),所以它走 FormData,
///   其余全部 JSON —— 这一条在小程序 topic-detail 里也写着。
class ClubTopicOpsApi {
  ClubTopicOpsApi(this._client);
  final DioClient _client;

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Response<Map<String, dynamic>> resp = await _client.dio
        .post<Map<String, dynamic>>(
          path,
          data: body,
          options: Options(contentType: Headers.jsonContentType),
        );
    return resp.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _postForm(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Response<Map<String, dynamic>> resp = await _client.dio
        .post<Map<String, dynamic>>(path, data: FormData.fromMap(body));
    return resp.data ?? <String, dynamic>{};
  }

  Object? _data(Map<String, dynamic> body) => body['data'];

  // ── 主题公开投影(两页共用的数据源)────────────────────────

  /// `POST /api/topic/info-to-user`(表单参数 `id`)→ 俱乐部视角主题投影。
  ///
  /// ★ 用玩家视角的公开投影做**陈列**是刻意的:模板已过 `TemplateSecrets.strip`,
  ///   答案/提示不在里面 —— topic-story 正是靠这一点才敢把它当陈列源,
  ///   答案另走 [nodeAnswer](小程序顶部注释原话)。
  Future<ClubTopicOverview> overview(int topicId) async {
    final Map<String, dynamic> body = await _postForm(
      '/api/topic/info-to-user',
      <String, dynamic>{'id': topicId.toString()},
    );
    ensureClubOpsOk(body);
    final ClubTopicOverview? parsed = ClubTopicOverview.tryFromJson(
      _data(body),
    );
    if (parsed == null) throw ClubApiException('主题信息回执不完整');
    return parsed;
  }

  /// `POST /api/club/topic-node-answer` → 主理人看某一站的答案。
  ///
  /// ⚠️ 后端是 `@RequestBody` 端点:不传 JSON 头就发成 urlencoded,
  ///   业务一行都不执行却照样回 HTTP 200 + code 500 —— 零告警的哑火
  ///   (小程序 2026 的原注释)。所以这里必须 JSON。
  ///
  /// 403 由调用方按「没有治理权限」处理(服务端 canGovernClub 校验)。
  Future<TopicNodeAnswer> nodeAnswer({
    required int clubId,
    required int topicId,
    required int nodeId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/topic-node-answer',
      <String, dynamic>{'clubId': clubId, 'topicId': topicId, 'nodeId': nodeId},
    );
    ensureClubOpsOk(body);
    final TopicNodeAnswer? parsed = TopicNodeAnswer.tryFromJson(_data(body));
    if (parsed == null) throw ClubApiException('答案回执不完整');
    return parsed;
  }

  // ── 主题 · 俱乐部设置(topic-setting)─────────────────────

  /// `POST /api/club/topic-setting/detail` → 三个开关 + 章节承接状态。
  /// 403 由调用方按「没有权限」处理(小程序 settingState = denied)。
  Future<TopicSetting> settingDetail({
    required int clubId,
    required int topicId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/topic-setting/detail',
      <String, dynamic>{'clubId': clubId, 'topicId': topicId},
    );
    ensureClubOpsOk(body);
    final TopicSetting? parsed = TopicSetting.tryFromJson(_data(body));
    if (parsed == null) throw ClubApiException('主题设置回执不完整');
    return parsed;
  }

  /// `POST /api/club/topic-setting/save` → 三个开关**一起**提交。
  ///
  /// ⚠️ 少传一个后端就拒绝,**不会**把没传的那个当 false 关掉 ——
  ///   所以这个方法的三个参数都是 required,别给默认值。
  Future<TopicSetting> saveSetting({
    required int clubId,
    required int topicId,
    required bool coopOpen,
    required bool pinned,
    required bool memberOnly,
  }) async {
    final Map<String, dynamic> body =
        await _postJson('/api/club/topic-setting/save', <String, dynamic>{
          'clubId': clubId,
          'topicId': topicId,
          'coopOpen': coopOpen,
          'pinned': pinned,
          'memberOnly': memberOnly,
        });
    ensureClubOpsOk(body);
    final TopicSetting? parsed = TopicSetting.tryFromJson(_data(body));
    if (parsed == null) throw ClubApiException('主题设置回执不完整');
    return parsed;
  }

  /// `POST /api/club/topic-setting/end` → 停售 + 把这个主题名下所有在办场次
  /// 逐场取消并全额退款。
  ///
  /// ★ 服务端**先下架再逐场退**(顺序反了会在退款过程中又卖出新票),
  ///   每场一个事务 —— 一场失败不回滚已退掉的,失败场次原样报回。
  ///   回执里的 [TopicEndResult.failedSessions] 必须照实显示,不能吞。
  Future<TopicEndResult> endTopic({
    required int clubId,
    required int topicId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/topic-setting/end',
      <String, dynamic>{'clubId': clubId, 'topicId': topicId},
    );
    ensureClubOpsOk(body);
    final TopicEndResult? parsed = TopicEndResult.tryFromJson(_data(body));
    if (parsed == null) throw ClubApiException('结束回执不完整');
    return parsed;
  }

  // ── 章节 · 商家承接(topic/chapter)───────────────────────

  /// `POST /api/topic/chapter/recruit`(表单参数)→ 开关某一章的商家承接。
  ///
  /// ★ 一条规则都不在前端判(合法值、已有申请时不许关、条款档与门槛、容量、
  ///   父主题上架与软删全在服务层)—— 前端自己先判一遍就是两套规则,
  ///   而分叉的那一侧就是绕过闸的入口。拒绝理由原样回显。
  Future<void> chapterRecruit({
    required int chapterId,
    required bool enabled,
    String scope = '',
  }) async {
    final Map<String, dynamic> body = await _postForm(
      '/api/topic/chapter/recruit',
      <String, dynamic>{
        'chapterId': chapterId,
        'enabled': enabled ? 1 : 0,
        'scope': scope,
      },
    );
    ensureClubOpsOk(body);
  }

  /// `POST /api/topic/chapter/finish`(表单参数)→ 结束这一章。
  /// 不可逆写;**只有发起人能调**(服务端原话),俱乐部侧调用时 scope 传空。
  Future<void> chapterFinish({
    required int chapterId,
    String scope = '',
  }) async {
    final Map<String, dynamic> body = await _postForm(
      '/api/topic/chapter/finish',
      <String, dynamic>{'chapterId': chapterId, 'scope': scope},
    );
    ensureClubOpsOk(body);
  }

  // ── 招商台 / 成员名单 ────────────────────────────────────

  /// `POST /api/club/recruit/overview` → 这个主题下的站点与承接商家。
  /// 403 = 没有权限看招商盘(小程序 merchantState = denied)。
  Future<RecruitOverview> recruitOverview({
    required int clubId,
    required int topicId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/recruit/overview',
      <String, dynamic>{'clubId': clubId, 'topicId': topicId},
    );
    ensureClubOpsOk(body);
    final RecruitOverview? parsed = RecruitOverview.tryFromJson(_data(body));
    if (parsed == null) throw ClubApiException('招商回执不完整');
    return parsed;
  }

  /// `POST /api/club/crm/topic-customers` → 主题内成员名单。
  ///
  /// [filter] 是服务端筛选(`''` / `pending` / `contacted` / `verified`),
  /// **不是**前端再筛一遍;三个统计数永远是全量口径(服务端过滤前先数完)。
  Future<TopicCustomers> customers({
    required int clubId,
    required int topicId,
    String filter = '',
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/crm/topic-customers',
      <String, dynamic>{'clubId': clubId, 'topicId': topicId, 'filter': filter},
    );
    ensureClubOpsOk(body);
    final TopicCustomers? parsed = TopicCustomers.tryFromJson(_data(body));
    if (parsed == null) throw ClubApiException('成员名单回执不完整');
    return parsed;
  }

  /// `POST /api/club/crm/topic-manage-stats` → 管理向统计 + 三个身份字段。
  ///
  /// ⚠️ `activityId` 要**照传 null**(从俱乐部页进来没有「这一场」):
  ///   后端按它决定「本场人数 / 待核销」是全主题口径还是单场口径,
  ///   悄悄省掉这个键就是把两种口径混成一个。
  Future<ClubTopicManageStats> manageStats({
    required int clubId,
    required int topicId,
    int? activityId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/crm/topic-manage-stats',
      <String, dynamic>{
        'clubId': clubId,
        'topicId': topicId,
        'activityId': activityId,
      },
    );
    ensureClubOpsOk(body);
    final ClubTopicManageStats? parsed = ClubTopicManageStats.tryFromJson(
      _data(body),
    );
    if (parsed == null) throw ClubApiException('管理向统计回执不完整');
    return parsed;
  }

  /// `POST /api/club/lead/edit-ops` → 承接方领队改这一场的集合时间(HO-26)。
  ///
  /// [startDate] 是**秒级** `YYYY-MM-DD HH:mm:00`(小程序 `confirmOpsTime` 逐字)。
  /// 前端不自判能不能改:已售锁定(CR-63)与「只有承接方领队可改」都在服务端,
  /// 拒绝文案原样带出去 —— 自己先判一遍就是两套规则,分叉那侧是绕过闸的入口。
  Future<void> editOps({
    required int activityId,
    required String startDate,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/lead/edit-ops',
      <String, dynamic>{'activityId': activityId, 'startDate': startDate},
    );
    ensureClubOpsOk(body);
  }

  // ── 俱乐部开放设置(open-settings)────────────────────────

  /// `POST /api/club/open-settings/public-visible` → 「俱乐部公开可见」。
  ///
  /// 三个开关各写各的方法而不合并成一张 `{url, field}` 表:接口路径必须是
  /// 可枚举字面量(全仓能 grep 出「谁调了这个端点」比省二十行值钱,小程序 U1 门禁)。
  Future<ClubOpenSettingValue> setPublicVisible({
    required int clubId,
    required bool enabled,
  }) => _toggleOpenSetting(
    '/api/club/open-settings/public-visible',
    'publicVisible',
    clubId,
    enabled,
  );

  /// `POST /api/club/open-settings/member-post` → 「允许成员发帖」。
  Future<ClubOpenSettingValue> setMemberPost({
    required int clubId,
    required bool enabled,
  }) => _toggleOpenSetting(
    '/api/club/open-settings/member-post',
    'memberPostAllowed',
    clubId,
    enabled,
  );

  /// `POST /api/club/open-settings/merchant-coop` → 「开放商家承接」。
  Future<ClubOpenSettingValue> setMerchantCoop({
    required int clubId,
    required bool enabled,
  }) => _toggleOpenSetting(
    '/api/club/open-settings/merchant-coop',
    'merchantUndertakeOpen',
    clubId,
    enabled,
  );

  /// 三个端点的公共实现(private:唯一调用点是上面三个具名方法)。
  ///
  /// ★ 只有**请求/回读逻辑**共用;路径字面量仍各自写在上面三个方法里 ——
  ///   一度改成在这里拼 `'/api/club/open-settings/$pathTail'`,于是全仓
  ///   `rg '/api/club/open-settings/member-post'` 一条都搜不到,
  ///   端点裁判(`tool/endpoint_parity.py`)也把三条都判成「App 没接」。
  Future<ClubOpenSettingValue> _toggleOpenSetting(
    String path,
    String field,
    int clubId,
    bool enabled,
  ) async {
    final Map<String, dynamic> body = await _postJson(path, <String, dynamic>{
      'id': clubId,
      field: enabled ? 1 : 0,
    });
    ensureClubOpsOk(body);
    final ClubOpenSettingValue? saved = ClubOpenSettingValue.tryFromJson(
      field,
      _data(body),
    );
    // 没有回读到这个开关的新值 = 「没保存成」,不是「保存成了但没显示」——
    // 界面上的「已开启/已关闭」要么是库里的事实,要么是一条明说的错误,不作第三种。
    if (saved == null) throw ClubApiException('服务端没有回读到这个开关的新值');
    return saved;
  }
}
