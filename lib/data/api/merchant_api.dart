import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/network/request_session_scope.dart';
import '../models/merchant.dart';
import '../models/merchant_dashboard.dart';
import '../models/merchant_ledger.dart';
import '../models/merchant_coop.dart';
import '../models/merchant_apply.dart';
import '../models/merchant_customer.dart';
import '../models/merchant_relation.dart';
import '../models/merchant_city_node.dart';
import '../models/merchant_marketing.dart';
import '../models/merchant_insight.dart';
import '../models/merchant_finance.dart';
import '../models/merchant_apply.dart'
    show RegistrationListFilter, TopicRegistration;
import '../models/merchant_application.dart';
import '../models/nearby_merchant.dart';
import '../models/chapter_application.dart';
import '../models/merchant_decor.dart';

/// `POST /api/merchant/access/me` 的 App 端唯一经营权限投影。
///
/// 页面不再从旧 `role` / `userType` 猜权限：只有 active、门店主体、
/// 固定岗位和权限码同时可信才放行。
class MerchantAccess {
  const MerchantAccess({
    required this.active,
    required this.merchantId,
    required this.merchantName,
    required this.merchantLogo,
    required this.roleCode,
    required this.permissions,
    this.applicationState,
    this.application,
  });

  factory MerchantAccess.fromJson(Map<String, dynamic> json) {
    final Object? activeRaw = json['active'];
    if (activeRaw is! bool) throw const FormatException('经营身份状态不完整');
    final Set<String> permissions = switch (json['permissions']) {
      final List<dynamic> values =>
        values.whereType<String>().where(_knownPermissions.contains).toSet(),
      _ => <String>{},
    };
    if (!activeRaw) {
      // ★ 未激活**不等于没有内容**:后端对「审核中/被驳回/已停用」的店主
      //   会一并下发 `roleCode` 与 `merchant` 摘要(id/name/logo/status/
      //   accountStatus)。此前这里见到这两样就抛 —— 于是这三种人
      //   在工作台连自己处于哪一态都读不到,只能撞上一句通用报错。
      final Object? merchantRaw = json['merchant'];
      final Map<String, dynamic> summary = merchantRaw is Map<String, dynamic>
          ? merchantRaw
          : const <String, dynamic>{};
      final String? inactiveRole = _text(json['roleCode']);
      final MerchantApplication? application =
          MerchantApplication.fromAccessSummary(summary);
      // 真源 `inactiveAccess`:三样**同时**成立才算一个申请态 ——
      // 状态词在表里、岗位是店主、门店摘要读得出一行。少一样就是 NONE,
      // 不拿着半截数据渲染「审核中」(那是把没查到说成业务事实)。
      final bool isApplicationState =
          _applicationStates.contains(_text(json['applicationState'])) &&
          inactiveRole == 'MERCHANT_OWNER' &&
          application != null;
      return MerchantAccess(
        active: false,
        merchantId: isApplicationState ? _idOf(summary) : null,
        merchantName: isApplicationState ? _text(summary['name']) : null,
        merchantLogo: isApplicationState ? _text(summary['logo']) : null,
        roleCode: isApplicationState ? 'MERCHANT_OWNER' : null,
        permissions: const <String>{},
        applicationState: isApplicationState
            ? _text(json['applicationState'])
            : 'NONE',
        application: isApplicationState ? application : null,
      );
    }
    final Object? merchantRaw = json['merchant'];
    if (merchantRaw is! Map<String, dynamic>) {
      throw const FormatException('经营门店主体不完整');
    }
    final int? merchantId = switch (merchantRaw['id']) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };
    final String roleCode = (json['roleCode'] ?? '').toString().trim();
    if (merchantId == null || merchantId <= 0) {
      throw const FormatException('经营门店主体不完整');
    }
    if (!_roleCodes.contains(roleCode)) {
      throw const FormatException('经营岗位无效');
    }
    String? optionalText(Object? value) {
      final String text = (value ?? '').toString().trim();
      return text.isEmpty ? null : text;
    }

    return MerchantAccess(
      active: true,
      merchantId: merchantId,
      merchantName: optionalText(merchantRaw['name']) ?? '门店',
      merchantLogo: optionalText(merchantRaw['logo']),
      roleCode: roleCode,
      permissions: Set<String>.unmodifiable(permissions),
    );
  }

  static const Set<String> _roleCodes = <String>{
    'MERCHANT_OWNER',
    'MERCHANT_MANAGER',
    'MERCHANT_CHECKIN',
    'MERCHANT_MARKETING',
    'MERCHANT_FINANCE',
  };

  /// 未激活身份可能带的申请态(后端 `ApiMerchantOperatorController` 原话)。
  static const Set<String> _applicationStates = <String>{
    'PENDING',
    'REJECTED',
    'DISABLED',
  };

  static const Set<String> _knownPermissions = <String>{
    'merchant:basic:read',
    'merchant:profile:write',
    'merchant:project:manage',
    'merchant:verify',
    'merchant:verify:record:read',
    'merchant:order:read',
    'merchant:crm:read',
    'merchant:crm:sensitive:read',
    'merchant:crm:segment',
    'merchant:crm:export',
    'merchant:finance:read',
    'merchant:aftercare:read',
    'merchant:aftercare:respond',
    'merchant:aftercare:decide',
    'merchant:aftercare:evidence',
    'merchant:marketing:read',
    'merchant:marketing:write',
    'merchant:coupon:manage',
    'merchant:coop:manage',
    'merchant:operator:manage',
  };

  final bool active;
  final int? merchantId;
  final String? merchantName;
  final String? merchantLogo;
  final String? roleCode;
  final Set<String> permissions;

  /// 仅 `active == false` 时有意义:NONE / PENDING / REJECTED / DISABLED。
  /// ★ 拿不到就留 null —— 那说明后端没给结论,界面不能自己编一个状态。
  final String? applicationState;

  /// 未激活时下发的申请摘要(审核中/驳回/停用),供工作台状态卡使用。
  final MerchantApplication? application;

  bool has(String permission) => active && permissions.contains(permission);
  bool get canReadBasic => has('merchant:basic:read');
  bool get canWriteProfile => has('merchant:profile:write');
  bool get canManageProjects => has('merchant:project:manage');
  bool get canVerify => has('merchant:verify');
  bool get canReadVerifyRecords => has('merchant:verify:record:read');
  bool get canReadOrders => has('merchant:order:read');
  bool get canReadCrm => has('merchant:crm:read');
  bool get canReadCrmSensitive => has('merchant:crm:sensitive:read');
  bool get canSegmentCrm => has('merchant:crm:segment');
  bool get canExportCrm => has('merchant:crm:export');
  bool get canReadFinance => has('merchant:finance:read');
  bool get canReadAftercare => has('merchant:aftercare:read');
  bool get canRespondAftercare => has('merchant:aftercare:respond');
  bool get canReadMarketing => has('merchant:marketing:read');
  bool get canWriteMarketing => has('merchant:marketing:write');
  bool get canManageCoupons => has('merchant:coupon:manage');
  bool get canManageCoop => has('merchant:coop:manage');
  bool get canManageOperators => has('merchant:operator:manage');

  /// 是不是店主本人。★ 这条**不是权限位**,是身份:
  /// `/api/merchant/dashboard` 与 todo/events 三个请求在后端是 owner-only,
  /// 财务岗的 `canReadFinance` 为真也照样 403 —— 小程序因此在 JS 侧
  /// 按 `roleCode === 'MERCHANT_OWNER'` 才发这几个请求。
  bool get isOwner => active && roleCode == 'MERCHANT_OWNER';

  /// 岗位中文名(小程序 `ROLE_LABELS`)。未知岗位不猜一个名字。
  String get roleName => switch (roleCode) {
    'MERCHANT_OWNER' => '店主',
    'MERCHANT_MANAGER' => '店长',
    'MERCHANT_CHECKIN' => '核销员',
    'MERCHANT_MARKETING' => '运营',
    'MERCHANT_FINANCE' => '财务',
    _ => '未知岗位',
  };

  static int? _idOf(Map<String, dynamic> json) => switch (json['id']) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value),
    _ => null,
  };

  static String? _text(Object? value) {
    final String text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  void require(String permission, String capabilityLabel) {
    if (!active) {
      throw const MerchantAccessDeniedException('当前账号没有有效经营身份');
    }
    if (!has(permission)) {
      throw MerchantAccessDeniedException('当前岗位没有$capabilityLabel权限');
    }
  }
}

class MerchantAccessDeniedException implements Exception {
  const MerchantAccessDeniedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 商家公开接口。对齐后端 `ApiMerchantController`(/api/merchant)。
class MerchantApi {
  MerchantApi(this._client);
  final DioClient _client;

  /// 当前账号的服务端经营身份与岗位权限。
  Future<MerchantAccess> access() async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/access/me',
    );
    return MerchantAccess.fromJson(data);
  }

  /// 商家搜索:`POST /api/merchant/list`(JSON body {name}) → success(`List<Merchant>`)。
  /// 与小程序 discover-search 同参:JSON body,不是 FormData;dio 默认 contentType
  /// 即 JSON,传 Map 即序列化。data 是裸 List(非 data.rows 分页)。
  /// 按**标签**发现商家:`POST /api/merchant/list`(body `tags`)。
  ///
  /// ★ 与 [searchByName] 是**两个筛选轴**,不是同一个方法的两种用法:
  ///   name 走 `name like`,tags 走 `tags like`(MmsMerchantMapper.xml:60)。
  ///   小程序的「发现商家」页按调性(标签 / 城市角色)找店,
  ///   App 此前只有按店名搜 —— 想找「适合组队的店」是找不到的。
  ///
  /// ⚠️ 后端强制 `status=1`(仅审核通过)+ `delFlag=0`,前端传这两个没意义。
  Future<List<Merchant>> discoverByTag(String tag) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/list',
      data: <String, dynamic>{'tags': tag},
    );
    return _merchants(resp.data ?? <String, dynamic>{});
  }

  /// 两条筛选共用的解析。
  List<Merchant> _merchants(Map<String, dynamic> body) {
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '请求失败');
    }
    return ((body['data'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(Merchant.fromJson)
        .toList();
  }

  Future<List<Merchant>> searchByName(String name) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/list',
      data: <String, dynamic>{'name': name},
    );
    final body = resp.data ?? <String, dynamic>{};
    final code = (body['code'] as num?)?.toInt();
    if (code != 200) {
      throw Exception((body['msg'] as String?) ?? '请求失败');
    }
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .map((dynamic e) => Merchant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 工作台:`POST /api/merchant/dashboard`。
  ///
  /// ⚠️ 非商家身份时后端返回 `error("商家信息不存在")` —— 那是**身份态不是故障**,
  ///   界面要分流成「你还不是商家」而不是「加载失败 + 重试」。
  Future<MerchantDashboard> dashboard() async {
    final data = await _postObject('/api/merchant/dashboard');
    return MerchantDashboard.fromJson(data);
  }

  /// 待办概要:`POST /api/merchant/todo-summary`。
  Future<MerchantTodo> todoSummary() async {
    final data = await _postObject('/api/merchant/todo-summary');
    return MerchantTodo.fromJson(data);
  }

  /// 读回当前营业状态:`POST /api/merchant/business-status`。
  ///
  /// ★ **此前只接了写、没接读** —— 于是工作台上那两个按钮恒定长一个样,
  ///   「开始营业」永远高亮,哪怕商家现在就是营业中。
  ///   界面根本不知道当前状态,商家也就无法确认自己上次到底设成了什么。
  ///
  /// 返回后端的 `businessStatusText`(「营业中」/「已打烊」)一并带出 ——
  /// 状态文案用后端的原话,不在前端另编一套。
  Future<({bool open, String text})> businessStatus() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/business-status',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final int bs = (data['businessStatus'] as num?)?.toInt() ?? 0;
    return (
      open: bs == 1,
      text:
          (data['businessStatusText'] as String?) ?? (bs == 1 ? '营业中' : '已打烊'),
    );
  }

  /// 更新营业状态:`POST /api/merchant/business-status/update`(表单 business_status)。
  /// 1 营业中 / 0 已打烊。返回后端的提示原话(「已营业」/「已打烊」)。
  Future<String> updateBusinessStatus({required bool open}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/business-status/update',
      data: FormData.fromMap(<String, dynamic>{
        'business_status': open ? '1' : '0',
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '操作失败');
    }
    return (body['msg'] as String?) ?? (open ? '已营业' : '已打烊');
  }

  /// 核销记录:`POST /api/merchant/finance/redemptions`(JSON body)。
  ///
  /// [filter] 由后端定义(all / pending / settled …),前端**不自行过滤** ——
  /// 顶部汇总是服务端按全集算的,前端再筛会让汇总与列表对不上。
  Future<MerchantRedemptionPage> redemptions({
    String filter = 'all',
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/finance/redemptions',
      data: <String, dynamic>{
        'filter': filter,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '加载失败');
    }
    return MerchantRedemptionPage.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 开放承接的路线:`POST /api/merchant/marketing-home` → data.recruiting.items。
  ///
  /// ⚠️ 非商家时后端返回 `error("仅商家可访问")` —— 身份态,不是故障。
  Future<List<RecruitingRoute>> recruitingRoutes() async {
    final data = await _postObject('/api/merchant/marketing-home');
    final recruiting = data['recruiting'];
    final items = recruiting is Map<String, dynamic>
        ? (recruiting['items'] as List<dynamic>? ?? const <dynamic>[])
        : const <dynamic>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(RecruitingRoute.fromJson)
        .toList();
  }

  /// 官方活动给商家的承接邀约:`GET /api/official/merchant-invites`。
  Future<List<MerchantInvite>> merchantInvites() async {
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _client.dio.get<Map<String, dynamic>>(
        '/api/official/merchant-invites',
      );
    } on DioException catch (e) {
      // ★ 协作邀请页对**俱乐部主理人**也会拉这条(后端注释原话):
      //   后端用 403 + `errorCode=NOT_ACTIVE_MERCHANT` 说「不是商家」——
      //   那是「本来就没有官方邀约」,不是故障,不能把整块渲染成错误态。
      final Object? data = e.response?.data;
      if (data is Map && data['errorCode'] == 'NOT_ACTIVE_MERCHANT') {
        return <MerchantInvite>[];
      }
      rethrow;
    }
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '加载失败');
    }
    final raw = body['data'];
    final rows = raw is List ? raw : const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(MerchantInvite.fromJson)
        .toList();
  }

  /// 提交入驻申请:`POST /api/merchant/merchant_registration`(JSON body)。
  ///
  /// ⚠️ 后端有一道**账户互斥闸**:已是俱乐部主理人时返回
  ///   「您已是俱乐部主理人,一个账户不能同时是商户与俱乐部主理人」。
  ///   那是**有意的产品规则**,不是故障 —— 界面要原样说给用户,别包装成"提交失败"。
  Future<void> submitApply(MerchantApplyForm form) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/merchant_registration',
      data: form.toJson(),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '提交失败');
    }
  }

  /// 客户名册:`POST /api/merchant/customers`(JSON body)。
  ///
  /// ⚠️ 后端会拒:「仅启用且审核通过的商家可查看客户名册」——
  ///   那是审核态,不是故障也不是"还不是商家"(申请已提交、只是还没过)。
  Future<List<MerchantCustomer>> customers({
    String? keyword,
    String? segment,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/customers',
      data: <String, dynamic>{
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        if (segment != null && segment.isNotEmpty) 'segment': segment,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '加载失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ((data['rows'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(MerchantCustomer.fromJson)
        .toList();
  }

  /// 关系与发现:`POST /api/merchant/relation-home`(JSON body,可带定位)。
  ///
  /// 一次返回三块:已建立的关系 relations、可发现的商家 discovery.merchants、
  /// 统计 stats。⚠️ 非商家时后端返回「仅商家可访问」。
  Future<MerchantRelationHome> relationHome({
    double? originLat,
    double? originLng,
    int limit = 20,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/relation-home',
      data: <String, dynamic>{
        'originLat': ?originLat,
        'originLng': ?originLng,
        'limit': limit,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '加载失败');
    }
    return MerchantRelationHome.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 我的据点 + 认领申请 + 配额:`POST /api/merchant/city-node/list`。
  Future<CityNodeHome> cityNodes() async {
    final data = await _postObject('/api/merchant/city-node/list');
    return CityNodeHome.fromJson(data);
  }

  /// 可认领的地点:`POST /api/merchant/city-node/claimable`(表单 keyword)。
  Future<List<CityNode>> claimableNodes({String? keyword}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/city-node/claimable',
      data: FormData.fromMap(<String, dynamic>{'keyword': ?keyword}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '加载失败');
    }
    final raw = body['data'];
    final rows = raw is List ? raw : const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(CityNode.fromJson)
        .toList();
  }

  /// 提交认领:`POST /api/merchant/city-node/claim`(表单 poiId)。
  Future<void> claimNode(int poiId) => _postForm(
    '/api/merchant/city-node/claim',
    <String, dynamic>{'poiId': poiId.toString()},
  );

  /// 撤回待审的认领申请:`POST /api/merchant/city-node/claim/cancel`(表单 poiId)。
  ///
  /// ★ 不撤回的话这个节点会一直锁在「已有待审申请」,别人认领不了
  ///   (快照 citynode/index.js:308 注释)。被平台接手审核后不可撤回,
  ///   那时后端会返回失败原因。
  Future<void> cancelClaim(int poiId) => _postForm(
    '/api/merchant/city-node/claim/cancel',
    <String, dynamic>{'poiId': poiId.toString()},
  );

  /// 据点上/下架:`POST /api/merchant/city-node/offline`
  /// (表单 poiId + status，1 上架 / 0 下线)。
  Future<String> setNodeStatus(int poiId, {required bool online}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/city-node/offline',
      data: FormData.fromMap(<String, dynamic>{
        'poiId': poiId.toString(),
        'status': online ? '1' : '0',
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '操作失败');
    }
    return (body['data'] as String?) ??
        (body['msg'] as String?) ??
        (online ? '已上架' : '已下线');
  }

  /// 据点核销码/海报:`POST /api/merchant/city-node/poster-code`(表单 poiId)。
  /// 返回 {code, qrcodeUrl, nodeName}。
  Future<Map<String, dynamic>> nodePosterCode(int poiId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/city-node/poster-code',
      data: FormData.fromMap(<String, dynamic>{'poiId': poiId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '获取失败');
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  Future<void> _postForm(String path, Map<String, dynamic> form) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(form),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '操作失败');
    }
  }

  /// 营销首页:`POST /api/merchant/marketing-home`(券 / 内容 / 漏斗三块)。
  Future<MerchantMarketing> marketingHome() async {
    final data = await _postObject('/api/merchant/marketing-home');
    return MerchantMarketing.fromJson(data);
  }

  /// AI 店铺参谋：`POST /api/ai/merchant/insight`。
  ///
  /// 商家主体从登录态解析，客户端不传 merchantId；`facts` 是必出层，
  /// 缺失时必须失败关闭，不能冒充为一页真实的全 0 经营数据。
  Future<MerchantInsight> merchantInsight() async {
    final Map<String, dynamic> data = await _postObject(
      '/api/ai/merchant/insight',
    );
    if (data['facts'] is! Map<String, dynamic>) {
      throw MerchantApiException('店铺数据加载失败');
    }
    return MerchantInsight.fromJson(data);
  }

  /// 附近商家线索:`POST /api/merchant/nearby`(表单 longitude/latitude/radius/limit)。
  ///
  /// ★ 隐私由服务端把关:不可拨打时后端**直接把 phone 置 null**,
  ///   不是发真号让前端藏 —— 所以这里不做任何前端脱敏。
  /// ★ radius 兜底值对齐真源 `pages/coop/nearby/index.js:276`
  ///   (`radius: 5000, limit: 30`)—— 此前少 2km,同一片商圈 App 会少一批商家。
  Future<List<NearbyMerchant>> nearby({
    required double longitude,
    required double latitude,
    int radius = 5000,
    int limit = 30,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/nearby',
      data: FormData.fromMap(<String, dynamic>{
        'longitude': longitude.toString(),
        'latitude': latitude.toString(),
        'radius': radius.toString(),
        'limit': limit.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '加载失败');
    }
    final raw = body['data'];
    return (raw is List ? raw : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(NearbyMerchant.fromJson)
        .toList();
  }

  /// 我的章节承接申请:`POST /api/merchant/chapter-application/mine`。
  Future<List<ChapterApplication>> myChapterApplications() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/chapter-application/mine',
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '加载失败');
    }
    final raw = body['data'];
    return (raw is List ? raw : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ChapterApplication.fromJson)
        .toList();
  }

  /// 申请承接某章节:`POST /api/merchant/chapter-application/apply`。
  Future<void> applyChapter(int chapterId, {String? message}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/chapter-application/apply',
      data: <String, dynamic>{
        'chapterId': chapterId,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '申请失败');
    }
  }

  /// 撤回申请:`POST /api/merchant/chapter-application/withdraw`。
  ///
  /// ⚠️ 只有**自己申请的、还在审核中**的能撤 —— 主办方邀请的不该由商家撤,
  ///   已通过/已拒绝的后端也会拒。前端按 [ChapterApplication.canWithdraw] 决定摆不摆按钮。
  Future<void> withdrawChapterApplication(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/chapter-application/withdraw',
      // ★ 键是 applicationId,不是 id(真源 merchantinfo.js:948;后端
      //   ApiMerchantChapterApplicationController.withdraw 只读这个键 ——
      //   发错了不报异常,只回「缺少申请」,按钮看着在、点下去永远不成)。
      data: <String, dynamic>{'applicationId': id},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '撤回失败');
    }
  }

  /// 保存店铺装修:`POST /api/merchant/decor/save`(JSON body)。
  ///
  /// ⚠️ 后端跑**内容安全审核**(slogan/cityRole/storyTitle 等自填文本),
  ///   命中违规直接拒 —— 与个人资料同一条:**内容被拒时重试没用,要改文字**。
  ///   这里按文案分流,让页面决定给不给重试。
  Future<void> saveDecor(MerchantDecor decor) async {
    await _saveDecorFields(decor.toJson());
  }

  /// 相册子页只更新 gallery，避免用空 [MerchantDecor] 把其他字段覆盖。
  Future<void> saveDecorGallery(List<String> gallery) =>
      _saveDecorFields(<String, dynamic>{
        'gallery': MerchantDecor(gallery: gallery).toJson()['gallery'],
      });

  /// 品牌故事页不再编辑标题，但保存时要带回已读到的原值。
  Future<void> saveDecorStoryTitle(String storyTitle) =>
      _saveDecorFields(<String, dynamic>{'storyTitle': storyTitle.trim()});

  /// 标签子流程只更新 tags，保存格式与相册一样是 canonical JSON。
  Future<void> saveDecorTags(List<String> tags) => _saveDecorFields(
    <String, dynamic>{'tags': MerchantDecor(tags: tags).toJson()['tags']},
  );

  Future<void> _saveDecorFields(Map<String, dynamic> fields) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/decor/save',
      data: fields,
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '保存失败');
    }
  }

  Future<Map<String, dynamic>> _postObject(String path) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path);
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] as String?) ?? '请求失败');
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 结算概览:`POST /api/merchant/finance/overview`。
  ///
  /// ★ 商家此前在 App 里**看不到自己的结算总账** —— 只有一页核销流水,
  ///   「这个月到账多少、对公还欠我多少、有没有待执行的调整」全都没有。
  Future<MerchantSettlementOverview> financeOverview() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/finance/overview',
      data: <String, dynamic>{},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    return MerchantSettlementOverview.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 商家资料:`POST /api/merchant/info`。
  ///
  /// ★ 与 `/update` 成对,**两条都没接** —— 商家在 App 里
  ///   既看不到自己的资料,也改不了。店铺装修页有,但那是另一套(decor)。
  Future<Map<String, dynamic>> merchantInfo() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/info',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 入驻申请行:`POST /api/merchant/info`(**只取申请状态那几个字段**)。
  ///
  /// ★ 与 [merchantInfo] 是两条不同用途的读:那一条给「已生效商家」读资料,
  ///   这一条给**还没生效**的申请人读自己的审核态 —— 后端注释写死了:
  ///   「入驻申请页必须能回读待审/驳回状态;active guard 只适用于已生效商家与员工」。
  ///
  /// 返回 null = 后端明说「这个账号名下没有申请行」(`applicationState:"NONE"`)
  /// —— 那是**结论**,进四步表单;拿不到结论一律抛,不静默当"没有"。
  Future<MerchantApplication?> application() async {
    final Map<String, dynamic> body;
    try {
      final resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/merchant/info',
        data: FormData.fromMap(<String, dynamic>{}),
      );
      body = resp.data ?? <String, dynamic>{};
    } on DioException {
      // 网络失败**不是**「没有申请」。落成表单会让人以为可以从头再交一份,
      // 而后端那边早就有一条了 —— 重复提交会被拒,那句报错他看不懂。
      throw MerchantApiException('网络连接失败，请检查网络后重新检查');
    }
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    if (isNoApplication(body)) return null;
    final Object? data = body['data'];
    final MerchantApplication? application = data is Map<String, dynamic>
        ? MerchantApplication.tryParse(data)
        : null;
    // 有 data 但读不出一行合法申请 —— 真源同一判据:这是「没结论」,
    // 不是「没申请」。这里不能回 null,否则会放行一份重复申请。
    return application ?? (throw MerchantApiException('暂时无法确认申请状态，请重试'));
  }

  /// 更新商家资料:`POST /api/merchant/update`(JSON body)。
  ///
  /// ★ 后端**只认六个白名单字段**(ApiMerchantController:536-541):
  ///   logo / name / description / derivatives / website / preference。
  ///   传别的会被忽略 —— 界面别把不可改的字段做成可编辑,那是骗用户。
  ///
  /// ⚠️ 后端会先做**内容安全预检**(商家资料匿名可访问,所以文本命中违规即拒),
  ///   失败文案要原样透传 —— 那句话会说清是哪段文字有问题。
  ///   logo 还会异步送检,**返回成功不等于 logo 已过审**;
  ///   界面别写「已生效」,只说「已提交」。
  Future<String> updateMerchant({
    String? logo,
    String? name,
    String? description,
    String? derivatives,
    String? website,
    String? preference,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/update',
      data: <String, dynamic>{
        if (logo != null) 'logo': logo,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (derivatives != null) 'derivatives': derivatives,
        if (website != null) 'website': website,
        if (preference != null) 'preference': preference,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '更新失败').toString());
    }
    return (body['msg'] as String?) ?? '已提交';
  }

  /// 商家核销台账:`POST /api/merchant/verification-records`。
  ///
  /// ★ 与 `/finance/redemptions`(结算流水)**不是一回事**:
  ///   这条是「谁在什么时候扫了哪张码」的**动作记录**,
  ///   前者是「这些核销该结多少钱」的**资金记录**。
  ///   商家追一次现场纠纷要的是前者。
  Future<List<Map<String, dynamic>>> verificationRecords() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/verification-records',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List
        ? data
        : ((data as Map<String, dynamic>?)?['rows'] as List<dynamic>?) ??
              <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList();
  }

  /// 商家订单/异常列表:`POST /api/merchant/orders`(按状态/售后筛)。
  ///
  /// ⚠️ **不要传 mmsMerchantId** —— 后端会无条件 `setMmsMerchantId(当前登录人)`
  ///   锁定卖家维度防越权(ApiMerchantController:1010)。前端传了也会被覆盖,
  ///   传了反而让人以为这里可以查别人的订单。
  Future<List<Map<String, dynamic>>> merchantOrders({
    int? status,
    int? aftersaleStatus,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/orders',
      data: <String, dynamic>{
        if (status != null) 'status': status,
        if (aftersaleStatus != null) 'aftersaleStatus': aftersaleStatus,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    final Object? data = body['data'];
    final List<dynamic> rows = data is List
        ? data
        : ((data as Map<String, dynamic>?)?['rows'] as List<dynamic>?) ??
              <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList();
  }

  // ------------------------------------------------------ 资金域四条查询
  //
  // ★★ 这四条的金额全是 **String**。别 parse 成 double 再格式化 ——
  //   后端用 String 正是为了避开浮点误差,前端转一圈等于把它请回来。

  /// 已成立收入与调整明细:`POST /api/merchant/finance/settlement-entries`。
  ///
  /// `source` 后端默认 "all";pageSize 被夹在 [1,50]。
  Future<MerchantFinancePage<MerchantSettlementEntry>> settlementEntries({
    String source = 'all',
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final Map<String, dynamic> data = await _financePost(
      '/api/merchant/finance/settlement-entries',
      <String, dynamic>{
        'source': source,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    return MerchantFinancePage<MerchantSettlementEntry>.fromJson(
      data,
      MerchantSettlementEntry.fromJson,
    );
  }

  /// 对公结算批次:`POST /api/merchant/finance/public-transfer-batches`。
  Future<MerchantFinancePage<PublicTransferBatch>> publicTransferBatches({
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final Map<String, dynamic> data = await _financePost(
      '/api/merchant/finance/public-transfer-batches',
      <String, dynamic>{'pageNum': pageNum, 'pageSize': pageSize},
    );
    return MerchantFinancePage<PublicTransferBatch>.fromJson(
      data,
      PublicTransferBatch.fromJson,
    );
  }

  /// 批次详情:`POST /api/merchant/finance/public-transfer-batch-detail`。
  ///
  /// ★ 不是本商家的批次,后端返回 `error("记录不可见")` —— 那是**越权保护**,
  ///   不是"这条没了"。提示照原文,别渲成「加载失败,请重试」让人一直点。
  Future<PublicTransferBatchDetail> publicTransferBatchDetail(
    int batchId,
  ) async {
    final Map<String, dynamic> data = await _financePost(
      '/api/merchant/finance/public-transfer-batch-detail',
      <String, dynamic>{'batchId': batchId},
    );
    return PublicTransferBatchDetail.fromJson(data);
  }

  /// 单笔核销详情:`POST /api/merchant/finance/redemption-detail`。
  ///
  /// ⚠️ `recordType` 后端**只认字符串 "redemption"**,别的一律当查不到
  ///   (`if (!"redemption".equals(recordType)) return null` → error("记录不可见"))。
  Future<MerchantRedemptionView> redemptionDetail({
    required String recordId,
    String recordType = 'redemption',
  }) async {
    final Map<String, dynamic> data = await _financePost(
      '/api/merchant/finance/redemption-detail',
      <String, dynamic>{'recordType': recordType, 'recordId': recordId},
    );
    return MerchantRedemptionView.fromJson(data);
  }

  /// 资金域四条共用:JSON body,取 data 的 Map;非 200 抛后端原文。
  Future<Map<String, dynamic>> _financePost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path, data: body);
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((res['msg'] ?? '加载失败').toString());
    }
    return (res['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  // ---------------------------------------------- 章节承接(主办方侧)
  //
  // ★ 这三条都只有**主题原发布者**能调(后端「谁发布谁审核」)。
  //   非发布者拿到的是业务错误原文,不是 403 —— 照原文显示。

  /// 本主题可邀请的商家:`POST /api/merchant/chapter-application/invitable`。
  ///
  /// ★ 定位是**可选**的:给了按距离从近到远排,没给(用户拒授权/取不到)
  ///   仍按原顺序返回 —— 后端明确「不当错误」。
  ///   ⇒ 界面不要因为拿不到定位就拦住这个功能。
  Future<List<Map<String, dynamic>>> invitableMerchants(
    int topicId, {
    double? latitude,
    double? longitude,
  }) async {
    return _rows(
      '/api/merchant/chapter-application/invitable',
      <String, dynamic>{
        'topicId': topicId,
        'latitude': ?latitude,
        'longitude': ?longitude,
      },
    );
  }

  /// 邀请商家承接本章节:`POST /api/merchant/chapter-application/invite`。
  ///
  /// ★ 后端把邀请定义成「**预先批准的申请**」—— 商家收到后可直接填供给与点位,
  ///   不再走一遍审核。所以这个动作比"发个消息"重,文案别写成「已发送邀请」。
  Future<Map<String, dynamic>> inviteChapterMerchant({
    required int chapterId,
    required int merchantMemberId,
  }) async {
    final Map<String, dynamic> body = await _postJsonData(
      '/api/merchant/chapter-application/invite',
      <String, dynamic>{
        'chapterId': chapterId,
        'merchantMemberId': merchantMemberId,
      },
    );
    return body;
  }

  /// 我发布的主题下的章节申请:`POST /api/merchant/chapter-application/owner-list`。
  Future<List<Map<String, dynamic>>> chapterApplicationsForTopic(int topicId) =>
      _rows('/api/merchant/chapter-application/owner-list', <String, dynamic>{
        'topicId': topicId,
      });

  /// 审核章节承接申请:`POST /api/merchant/chapter-application/audit`。
  Future<void> auditChapterApplication({
    required int applicationId,
    required bool approve,
    String? reason,
  }) async {
    await _postJsonData(
      '/api/merchant/chapter-application/audit',
      <String, dynamic>{
        'id': applicationId,
        'approve': approve,
        'reason': ?reason,
      },
    );
  }

  // ---------------------------------------------- 章节点位(商家侧)

  /// 提交/更新我在章节下的点位:`POST /api/merchant/chapter-node/submit`。
  ///
  /// ★★ 后端**刻意不收整个 CmsTopicNode**,原话:
  ///   「那样客户端能连 merchantMemberId、nodeAuditStatus、topicId 一起传进来,
  ///     而这三样正是权限本身」。
  ///   ⇒ 这里也**只发它认的那几个字段**。多发的会被忽略,但更重要的是
  ///     别在界面上做出"可以改归属/审核态"的错觉。
  ///
  /// ⚠️ 提交即回到**待审**(哪怕只改了一个字),文案要说清,
  ///   否则商家会以为改个营业时间就立刻生效了。
  Future<Map<String, dynamic>> submitChapterNode({
    required int chapterId,
    int? templateId,
    String? name,
    String? description,
    String? address,
    String? longitude,
    String? latitude,
    String? imgUrl,
    String? businessTime,
    int? xpValue,
  }) async {
    return _postJsonData('/api/merchant/chapter-node/submit', <String, dynamic>{
      'chapterId': chapterId,
      'templateId': ?templateId,
      'name': ?name,
      'description': ?description,
      'address': ?address,
      'longitude': ?longitude,
      'latitude': ?latitude,
      'imgUrl': ?imgUrl,
      'businessTime': ?businessTime,
      'xpValue': ?xpValue,
    });
  }

  /// 我的章节点位(含待审与驳回原因):`POST /api/merchant/chapter-node/mine`。
  ///
  /// ⚠️ topicId 是**表单参数**,不是 JSON body(后端签名是裸参数)。
  Future<List<Map<String, dynamic>>> myChapterNodes({int? topicId}) =>
      _formRows('/api/merchant/chapter-node/mine', <String, dynamic>{
        if (topicId != null) 'topicId': topicId.toString(),
      });

  /// 主办方:我主题下待审的商家点位:`POST /api/merchant/chapter-node/pending`。
  Future<List<Map<String, dynamic>>> pendingChapterNodes(int topicId) =>
      _formRows('/api/merchant/chapter-node/pending', <String, dynamic>{
        'topicId': topicId.toString(),
      });

  /// 取本店到店打卡码:`POST /api/merchant/chapter-node/poster-code`。
  /// 返回 code / qrcodeUrl / nodeId / nodeName / topicId / chapterId。
  Future<Map<String, dynamic>> chapterNodePosterCode(int nodeId) => _formData(
    '/api/merchant/chapter-node/poster-code',
    <String, dynamic>{'nodeId': nodeId.toString()},
  );

  /// 现场出示的打卡码:`POST /api/merchant/chapter-node/live-checkin-code`。
  ///
  /// ★ 与 [chapterNodePosterCode] 是**两张不同的码**,别互相替代:
  ///   · poster-code = 贴在店里长期用的那张,不刷新;
  ///   · live-checkin-code = 现场出示给玩家扫的那张,带 `ttlMs`(秒级过期),
  ///     过期必须重新取 —— 一张永不过期的现场码等于把打卡敞开给任何截图的人。
  ///
  /// 返回 `code / qrcodeUrl / ttlMs`(小程序 pages/merchant/game-node/index.js:556)。
  Future<Map<String, dynamic>> chapterNodeLiveCheckinCode(int nodeId) => _formData(
    '/api/merchant/chapter-node/live-checkin-code',
    <String, dynamic>{'nodeId': nodeId.toString()},
  );

  /// 读章节点位的 AI 角色:`POST /api/merchant/chapter-node/npc/detail`。
  ///
  /// ★ 没配过时后端回 **`data: null`**(小程序 node-npc-form/index.js:81 实测),
  ///   不是 404、也不是空对象 —— 所以「没配过」是一个正常空态,
  ///   调用方按空表单渲染,别当加载失败。
  ///
  /// ⚠️ 这是**节点头上的**角色,和门店形象(`/api/merchant/npc/*`,店铺级)是两套,
  ///   后端明确「节点 NPC 不得复用门店形象端点」(node-npc-form.test.js:132)。
  Future<Map<String, dynamic>?> chapterNodeNpcDetail(int nodeId) async {
    final Map<String, dynamic> res = await _formDataRaw(
      '/api/merchant/chapter-node/npc/detail',
      <String, dynamic>{'nodeId': nodeId.toString()},
    );
    final Object? data = res['data'];
    return data is Map<String, dynamic> ? data : null;
  }

  /// 保存章节点位角色:`POST /api/merchant/chapter-node/npc/save`。
  ///
  /// 只发后端收的四个字段(nodeId/name/avatar/greeting)—— 归属与审核态
  /// 由后端从登录态解析,和小程序 node-npc-form/index.js:273 同参。
  ///
  /// ⚠️ 后端会拒:「承接已失效或未生效,不能编辑节点内容」——
  ///   那是权限/状态态,不是重试能解决的,照原文显示。
  Future<Map<String, dynamic>> chapterNodeNpcSave({
    required int nodeId,
    required String name,
    required String avatar,
    String greeting = '',
  }) => _formData('/api/merchant/chapter-node/npc/save', <String, dynamic>{
    'nodeId': nodeId.toString(),
    'name': name,
    'avatar': avatar,
    'greeting': greeting,
  });

  /// 提交节点头的录音克隆:`POST /api/merchant/chapter-node/npc/voice/enroll`。
  ///
  /// ★ 节点侧收的是**一段**录音(`voiceSample`),不是门店侧那种五段数组
  ///   (`/api/merchant/npc/voice/enroll` 收 `sampleUrls`)—— 两者别抄错。
  Future<Map<String, dynamic>> chapterNodeNpcVoiceEnroll({
    required int nodeId,
    required String voiceSample,
  }) => _formData('/api/merchant/chapter-node/npc/voice/enroll', <String, dynamic>{
    'nodeId': nodeId.toString(),
    'voiceSample': voiceSample,
  });

  /// 清除节点头的录音:`POST /api/merchant/chapter-node/npc/voice/reset`。
  ///
  /// 小程序在清除后**回读状态**(node-npc-form/index.js:417)→ 这里由调用方回读。
  Future<void> chapterNodeNpcVoiceReset(int nodeId) => _formData(
    '/api/merchant/chapter-node/npc/voice/reset',
    <String, dynamic>{'nodeId': nodeId.toString()},
  );

  /// 节点头录音的生成状态:`POST /api/merchant/chapter-node/npc/voice/status`。
  ///
  /// 返回 `{voiceStatus, voiceSample}`。voiceStatus 只认四态
  /// (小程序 node-npc-form/index.js:399 的四态表):
  ///   `0` 未配置 · `1` 生成中 · `2` 已就绪 · `3` 上次生成失败。
  ///   ★ 别的值一律**不当作已知状态** —— 猜一个会把失败说成成功。
  Future<Map<String, dynamic>> chapterNodeNpcVoiceStatus(int nodeId) => _formData(
    '/api/merchant/chapter-node/npc/voice/status',
    <String, dynamic>{'nodeId': nodeId.toString()},
  );

  /// 主办方:审核商家点位:`POST /api/merchant/chapter-node/audit`。
  ///
  /// ★ 后端 summary 写明这是「**准入,非背书**」—— 通过不代表平台为该商家担保。
  Future<Map<String, dynamic>> auditChapterNode({
    required int nodeId,
    required bool approve,
    String? reason,
  }) => _formData('/api/merchant/chapter-node/audit', <String, dynamic>{
    'nodeId': nodeId.toString(),
    'approve': approve.toString(),
    if (reason != null && reason.isNotEmpty) 'reason': reason,
  });

  /// 下载一张图片的字节(点位码要「保存到相册」,相册要的是字节不是 URL)。
  ///
  /// ★ 放在 API 层而不是页面里:仓规是「feature 层不直接发 http」,
  ///   而且这条要跟着 [DioClient] 的基址/鉴权走,自己拼 URL 会绕过统一网络层。
  Future<Uint8List> fetchImageBytes(String url) async {
    final Response<List<int>> resp = await _client.dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final List<int>? bytes = resp.data;
    if (bytes == null || bytes.isEmpty) {
      throw MerchantApiException('图片没下载下来,请重试');
    }
    return Uint8List.fromList(bytes);
  }

  // ---------------------------------------------- 城市据点

  /// 提交据点投放申请:`POST /api/merchant/city-node/save`(**表单参数**)。
  ///
  /// ★ 这是 roam_poi 的**唯一写入路径**(后端 summary 原话)。
  ///
  /// ⚠️ 三条会被后端直接拒的:
  ///   · 没选模板 → 「请先选择互动模板」(templateId 必填,且必须是自己的);
  ///   · 传了已上线据点的 poiId → 「已上线据点不能复用投放申请入口」;
  ///   · 在架据点到配额上限 → 「在架据点已达上限(N),请先下线其他据点」。
  ///
  /// ★ **坐标可以不传**:后端会回落到商家档案里的店址
  ///   (原话:报名成为节点只要求「配个玩法」,店址平台本来就有)。
  ///   档案里也没坐标时才报错。⇒ 界面别硬性要求先在地图上打点。
  Future<Map<String, dynamic>> saveCityNode({
    required int templateId,
    double? lat,
    double? lng,
    int? radius,
    String? name,
    String? address,
    String? tags,
    String? coverImg,
    String? cityCode,
  }) => _formData('/api/merchant/city-node/save', <String, dynamic>{
    'templateId': templateId.toString(),
    if (lat != null) 'lat': lat.toString(),
    if (lng != null) 'lng': lng.toString(),
    if (radius != null) 'radius': radius.toString(),
    if (name != null && name.isNotEmpty) 'name': name,
    if (address != null && address.isNotEmpty) 'address': address,
    if (tags != null && tags.isNotEmpty) 'tags': tags,
    if (coverImg != null && coverImg.isNotEmpty) 'coverImg': coverImg,
    if (cityCode != null && cityCode.isNotEmpty) 'cityCode': cityCode,
  });

  /// 提交/更新据点互动模板:`POST /api/merchant/city-node/template/submit`
  /// (JSON body,收整个 CmsMemberTemplate)→ data 是模板 id。
  ///
  /// ★★ 后端按**验证方式**校验必填项,并且注释说明了为什么闸在服务端:
  ///   「配不全就落库的话,玩家侧只会表现成『怎么答都不对』,商家还看不出哪里错了」。
  ///   ⇒ 前端表单也该拦一道,但那只是体验;**服务端返回的错误必须原文显示**,
  ///     它才说得清缺的是哪一项。
  ///
  /// ⚠️ 这条是**免人工审**:过了内容安全就直接上线(nodeSubmitStatus=2)。
  ///   所以成功文案可以说「已生效」—— 与别处的"待审"不同。
  Future<int> submitNodeTemplate(Map<String, dynamic> template) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/city-node/template/submit',
      data: template,
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '提交失败').toString());
    }
    final Object? id = body['data'];
    if (id is! num) {
      throw MerchantApiException('模板没返回编号 —— 别当保存成功了');
    }
    return id.toInt();
  }

  // ---------------------------------------------- 本节共用的三个小helper

  Future<List<Map<String, dynamic>>> _rows(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Map<String, dynamic> wrapped = await _postJsonRaw(path, body);
    return ((wrapped['data'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>> _postJsonData(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Map<String, dynamic> wrapped = await _postJsonRaw(path, body);
    return (wrapped['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _postJsonRaw(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path, data: body, options: RequestSessionScope.options());
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((res['msg'] ?? '请求失败').toString());
    }
    return res;
  }

  /// 后端签名是裸参数 ⇒ 必须走表单,发 JSON 绑不上(全是 null,而且**不报错**)。
  /// 与 [_formData] 同路,但**保留原始 data**(可能是 null)。
  /// 用于「没配置」是一个合法空态、且与「出错」必须分得开的端点。
  Future<Map<String, dynamic>> _formDataRaw(
    String path,
    Map<String, dynamic> form,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(form),
    );
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((res['msg'] ?? '请求失败').toString());
    }
    return res;
  }

  Future<Map<String, dynamic>> _formData(
    String path,
    Map<String, dynamic> form,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(form),
    );
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((res['msg'] ?? '请求失败').toString());
    }
    final Object? data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _formRows(
    String path,
    Map<String, dynamic> form,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(form),
    );
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((res['msg'] ?? '请求失败').toString());
    }
    final Object? data = res['data'];
    return (data is List ? data : <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  // ---------------------------------------------- 商家主题报名(六条)

  /// 我的报名:`POST /api/registration/merchant/list`(表单 status)。
  ///
  /// ⚠️ status 是**字符串数字**:0全部 / 1进行中 / 2审核中 / 3已驳回 / 4已结束。
  ///   data 走 `getDataTable` ⇒ 列表在 **data.rows**,直接读 data 会拿到空且不报错。
  Future<List<TopicRegistration>> myTopicRegistrations({
    RegistrationListFilter filter = RegistrationListFilter.all,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/merchant/list',
      data: FormData.fromMap(<String, dynamic>{'status': filter.wire}),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ((data['rows'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(TopicRegistration.fromJson)
        .toList();
  }

  /// 报名详情:`POST /api/registration/merchant/info`(**query** 参数 id)。
  ///
  /// ⚠️ 后端是 `@RequestParam("id")` ⇒ 必须走 query,不是表单也不是 body。
  Future<Map<String, dynamic>> topicRegistrationDetail(
    int registrationId,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/merchant/info',
      queryParameters: <String, dynamic>{'id': registrationId.toString()},
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '加载失败').toString());
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 我报过这个主题没有:`POST /api/registration/merchant/select`(表单 id)。
  ///
  /// ★★ **这条的返回是反的**,别按常规判 code:
  ///   · 已报名 → `error("您已报名此主题，请勿重复报名")`(code ≠ 200)
  ///   · 未报名 → `success("未报名")`(code == 200)
  ///   按"非 200 即失败"处理的话,已报名会显示成「出错了」;
  ///   按"200 即已报名"处理的话,含义整个反过来。
  ///
  /// ★ 参数名叫 id,但后端是 `setTopicId(Long.valueOf(id))` —— 它要的是
  ///   **主题 id**,Swagger 上那句「报名id」是错的。传报名 id 会查错东西。
  Future<bool> hasRegisteredTopic(int topicId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/merchant/select',
      data: FormData.fromMap(<String, dynamic>{'id': topicId.toString()}),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    final String msg = (body['msg'] ?? '').toString();
    if ((body['code'] as num?)?.toInt() == 200) return false;
    // 非 200 里只有"已报名"这一种是正常态,其余(未登录/参数非法)照抛。
    if (msg.contains('已报名')) return true;
    throw MerchantApiException(msg.isEmpty ? '查询失败' : msg);
  }

  /// 创建商家主题报名:`POST /api/registration/merchant/create`(JSON body)。
  ///
  /// ⚠️ 后端 `@Validated`,**topicId 必填**(「主题ID不能为空」)。
  Future<String> createTopicRegistration(Map<String, dynamic> param) =>
      _registrationWrite('/api/registration/merchant/create', param);

  /// 修改报名:`POST /api/registration/merchant/update`(JSON body)。
  ///
  /// ★ 后端只允许**审核中 / 已驳回,且主题未开始**时改。原注释说明了为什么加它:
  ///   「原来只有 create/cancel:被驳回的商家想补一张现场图,
  ///     只能取消重报,记录丢失、重新排队」。
  ///   ⇒ 被驳回的报名要给「修改」而不是只给「重新报名」。
  Future<String> updateTopicRegistration(Map<String, dynamic> param) =>
      _registrationWrite('/api/registration/merchant/update', param);

  /// 取消报名:`POST /api/registration/merchant/cancel`(表单 id)。
  ///
  /// ★ **已中标的不能取消**(闸在 service 里)。界面对已中标的报名
  ///   别给取消按钮 —— 给了就是点下去必报错。
  Future<String> cancelTopicRegistration(int registrationId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/merchant/cancel',
      data: FormData.fromMap(<String, dynamic>{
        'id': registrationId.toString(),
      }),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '取消失败').toString());
    }
    return (body['msg'] ?? '报名已取消').toString();
  }

  Future<String> _registrationWrite(
    String path,
    Map<String, dynamic> param,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: param,
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '提交失败').toString());
    }
    return (body['msg'] ?? '已提交').toString();
  }

  // ---------------------------------------------- 营销 / 档案 / 订阅(六条)

  /// 我的付费权益:`POST /api/merchant/subscription`。
  ///
  /// ★ 后端只查 `isActive=1` —— 返回的**就是当前生效的那些**,
  ///   空列表 = 没有生效权益,不是"没查到"。别渲染成加载失败。
  Future<List<Map<String, dynamic>>> mySubscriptions() =>
      _rows('/api/merchant/subscription', <String, dynamic>{});

  /// 即将到店的场次(含俱乐部包团):`POST /api/merchant/upcoming-runs`。
  Future<List<Map<String, dynamic>>> upcomingRuns({int? topicId}) => _rows(
    '/api/merchant/upcoming-runs',
    <String, dynamic>{'topicId': ?topicId},
  );

  /// 商家实时动态:`POST /api/merchant/events`。
  ///
  /// ★ 后端把"收入到账/核销"等**真实事件**拼成一条时间线,
  ///   时间已按 `MM-dd HH:mm` 格式化好 —— 前端**别再解析再格式化**,
  ///   那串里没有年份和时区,重新解析必然按当前年/本地时区猜,跨年就错。
  Future<List<Map<String, dynamic>>> merchantEvents() =>
      _rows('/api/merchant/events', <String, dynamic>{});

  /// 商家看俱乐部列表(发邀请用):`POST /api/merchant/clubs`。
  /// 后端强制 `status=1`(仅已开放),前端传这个没意义。
  Future<List<Map<String, dynamic>>> clubsForInvite({String? name}) => _rows(
    '/api/merchant/clubs',
    <String, dynamic>{if (name != null && name.isNotEmpty) 'name': name},
  );

  /// 商家公开主页:`POST /api/merchant/public-home`(**匿名可访问**)。
  ///
  /// ★★ **失败关闭**:必须**恰好给一个** id 或 memberId。
  ///   后端原话:「都给会让两条查询路径的可见性判定含糊,都不给等于全表公开入口」。
  ///   ⇒ 这里用命名构造强制二选一,别做成两个都可空的参数。
  ///
  /// ★ 不可见时统一回 `error("商家不存在或未开放")` —— **不区分**是不存在
  ///   还是未审核还是被封,那是有意的(不给探测),照原文显示即可。
  Future<Map<String, dynamic>> merchantPublicHomeById(int id) =>
      _objectOf('/api/merchant/public-home', <String, dynamic>{'id': id});

  Future<Map<String, dynamic>> merchantPublicHomeByMember(int memberId) =>
      _objectOf('/api/merchant/public-home', <String, dynamic>{
        'memberId': memberId,
      });

  /// 商家承接档案(读自己的):`POST /api/merchant/coop-profile`。
  Future<Map<String, dynamic>> coopProfile() =>
      _objectOf('/api/merchant/coop-profile', <String, dynamic>{});

  /// 保存商家承接档案:`POST /api/merchant/coop-profile/save`。
  ///
  /// ★★ 后端**只 set 这六个字段**,传别的静默忽略 ——
  ///   界面把不可改的字段做成可编辑,是在骗用户。
  /// ⚠️ `demand`(合作需求自由文本)过**同步**内容安全检查,
  ///   违规直接拒并给出原话,照原文显示。
  Future<String> saveCoopProfile({
    int? capacity,
    String? availableTime,
    String? suitActivityTypes,
    int? chargeType,
    String? demand,
    int? coopOpen,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'capacity': ?capacity,
      'availableTime': ?availableTime,
      'suitActivityTypes': ?suitActivityTypes,
      'chargeType': ?chargeType,
      'demand': ?demand,
      'coopOpen': ?coopOpen,
    };
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/coop-profile/save',
      data: body,
    );
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((res['msg'] ?? '保存失败').toString());
    }
    return (res['msg'] ?? '已保存').toString();
  }

  Future<Map<String, dynamic>> _objectOf(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(path, data: body, options: RequestSessionScope.options());
    final Map<String, dynamic> res = resp.data ?? <String, dynamic>{};
    if ((res['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((res['msg'] ?? '加载失败').toString());
    }
    return (res['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  // ---------------------------------------------- 商家增值购买

  /// 我能买什么:`POST /api/merchant/commerce/capabilities`。
  ///
  /// ★ 两种拒绝含义不同,别合并成「加载失败」:
  ///   · 「请先登录」 → 去登录
  ///   · 「请先完成商家入驻」 → 去入驻,不是重试
  Future<Map<String, dynamic>> commerceCapabilities() =>
      _objectOf('/api/merchant/commerce/capabilities', <String, dynamic>{});

  /// 下单买增值:`POST /api/merchant/commerce/order`。
  ///
  /// ★★ 后端会先查**微信身份绑定**:没绑直接
  ///   「微信身份未绑定，无法发起支付」——那是**去绑微信**,不是重试下单。
  ///   ⚠️ 也就是说这条链路依赖 wxOpenId;App 端没走过微信登录的账号
  ///     调它必然失败。界面要把这句话原样透出去。
  Future<Map<String, dynamic>> createCommerceOrder(Map<String, dynamic> body) =>
      _objectOf('/api/merchant/commerce/order', body);

  /// 读一笔增值订单的终态:`POST /api/merchant/commerce/order/status`。
  ///
  /// 与小程序 `pages/merchant/decor/index.js:435` 的
  /// `createPaymentVerifier.requestStatus` 同参(`{orderSn}`)同义。
  ///
  /// ★ 只有 `success` / `failed` 是终态;`pending` 与一切读不懂的值都归一成
  ///   `unknown` —— 把「不知道」猜成成功或失败,是这条接口唯一不能犯的错。
  Future<String> commerceOrderStatus(String orderSn) async {
    final Map<String, dynamic> data = await _objectOf(
      '/api/merchant/commerce/order/status',
      <String, dynamic>{'orderSn': orderSn},
    );
    final String status = (data['paymentStatus'] ?? '').toString();
    return const <String>{'success', 'pending', 'failed'}.contains(status)
        ? status
        : 'unknown';
  }

  /// 我的模板详情:`POST /api/template/myinfo`(表单 id)。
  ///
  /// ★ 与公开的模板详情不是一条 —— 这条只给**自己的**模板,
  ///   含答案/正确选项等只有拥有者能看的字段。
  Future<Map<String, dynamic>> myTemplateInfo(int templateId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/template/myinfo',
      data: FormData.fromMap(<String, dynamic>{'id': templateId.toString()}),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw MerchantApiException((body['msg'] ?? '模板读取失败').toString());
    }
    return (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }
}

/// 带后端原话的异常 —— 「商家信息不存在」需要按文案分流成身份态。
class MerchantApiException implements Exception {
  MerchantApiException(this.message);
  final String message;

  /// 内容被安全审核拒了。★ 重试没用 —— 要改文字。
  ///
  /// ⚠️ 先排除明确的故障词,避免把网络问题误判成内容问题
  ///   (误判就不给重试了,那是另一个方向的坏)。
  bool get isContentRejected {
    if (message.contains('网络') || message.contains('稍后重试')) return false;
    return const <String>['违规', '敏感', '不合规', '含有'].any(message.contains);
  }

  /// 是不是「商家还在审核中」。★ 与「还不是商家」不同:申请**已经提交了**,
  /// 界面该说「审核通过后可用」,而不是再给一个「去申请入驻」按钮
  /// —— 他点进去会发现自己已经申请过了。
  ///
  /// ⚠️ 判据与 isNotMerchant **有重叠风险**(这句里也含「商家」二字),
  ///    所以 merchantErrorView 里必须先判这一条。有页面级测试锁着顺序。
  bool get isPendingReview =>
      message.contains('仅启用且审核通过') || message.contains('审核通过的商家');

  /// 是不是撞上了「一个账户不能同时是商户与俱乐部主理人」这条产品规则。
  /// ★ 这不是故障也不是"还不是商家" —— 是**永远不能成为商家**,
  ///   界面必须说清原因,不能给重试也不能引导去申请。
  bool get isClubLeaderConflict => message.contains('俱乐部主理人');

  /// 是不是「你不是商家」而非「出错了」。两者界面完全不同:
  /// 前者给「去申请入驻」,后者给「重试」。给错了用户会一直点一个不会好的重试。
  bool get isNotMerchant =>
      message.contains('商家信息不存在') ||
      message.contains('数据获取失败') ||
      message.contains('仅商家可访问') ||
      message.contains('仅商家可查看') ||
      message.contains('请先完成商家入驻');

  /// 公开主页判定「不可公开」。⚠️ **只能认后端这句原话** ——
  ///   后端没有错误码,public-home 的不可公开合同就是这句话
  ///   (`merchant_api.dart` public-home 注释 + 小程序 `UNAVAILABLE_MSG`)。
  ///   文案一改,真实的「这家店看不了」会退化成可重试的错误态。
  bool get isPublicHomeUnavailable => message == '商家不存在或未开放';

  @override
  String toString() => message;
}
