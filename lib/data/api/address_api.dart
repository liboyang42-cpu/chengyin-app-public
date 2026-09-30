import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';

/// 收货地址。
///
/// ★★ 与 `ParticipantApi` **共用同一组端点和同一张表**
///   (`ums_member_address` / `/api/user/address/*`)——
///   小程序的两页只是把地址那几栏藏起来当"参与人",存的是同一批行。
///
///   ⇒ 两件事必须记住:
///   ① **删一条"参与人"就等于删掉了那条收货地址**,反之亦然。
///      界面上别说"删除参与人"就完事,那条地址也没了。
///   ② 列表是**同一批数据**:参与人页看到的和地址页看到的是一批行,
///      只是显示的字段不同。所以两页都改完要互相 invalidate。
///
/// ⚠️ 之所以另起一个类而不是往 ParticipantApi 上加地址字段:
///   参与人保存时**不该**发省市区(发了会把已有地址覆盖成空)。
///   两个类各自只发自己那几栏,是有意的隔离。
class AddressApi {
  AddressApi(this._client);
  final DioClient _client;

  /// 地址列表:`POST /api/user/address/list`(列表在 data.rows)。
  Future<List<MemberAddress>> list() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/list',
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    _ok(body);
    final Map<String, dynamic> data =
        (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return ((data['rows'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(MemberAddress.fromJson)
        .toList();
  }

  /// 详情:`POST /api/user/address/info`。
  ///
  /// ★ 归属在后端查询里(`selectOwnedAddressById`)—— 查别人的返回"地址不可用",
  ///   不是别人的地址。照原文显示。
  Future<MemberAddress> info(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/info',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final Map<String, dynamic> body = resp.data ?? <String, dynamic>{};
    _ok(body);
    return MemberAddress.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 新增 / 编辑:`POST /api/user/address/action`(传 id 是编辑)。
  ///
  /// ⚠️ 与 ParticipantApi.save **走同一条端点**,但这里会发省市区。
  ///   反过来参与人保存时不发这几栏 —— 发了会把已填的地址覆盖成空。
  /// ⚠️ 实体上**没有 city / area 两栏** —— `province` 这一栏装的就是
  ///   "省市区"整串(后端 @Parameter 原文:「province: 省市区」)。
  ///   我第一版按常见电商模型拆成三栏,那是猜的,后端根本不收。
  Future<void> save({
    int? id,
    required String fullName,
    required String mobilePhone,
    String? province,
    String? detailAddress,
    bool isDefault = false,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/action',
      data: FormData.fromMap(<String, dynamic>{
        if (id != null) 'id': id.toString(),
        'fullName': fullName,
        'mobilePhone': mobilePhone,
        if (province != null && province.isNotEmpty) 'province': province,
        // ⚠️ 提交键是 **detailAddress**(后端 @Parameter),不是 address。
        if (detailAddress != null && detailAddress.isNotEmpty)
          'detailAddress': detailAddress,
        'isDefault': isDefault ? '1' : '0',
      }),
    );
    _ok(resp.data ?? <String, dynamic>{});
  }

  /// 删除:`POST /api/user/address/delete`。
  ///
  /// ★★ 这条**同时删掉了那个"参与人"** —— 同一张表同一行。
  ///   确认文案要说清,别只说"删除地址"。
  Future<void> remove(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/delete',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    _ok(resp.data ?? <String, dynamic>{});
  }

  /// 设为默认地址:`POST /api/user/address/setDefault`。
  ///
  /// 小程序保留了同名操作，现有编辑表单也可在保存时设默认；
  /// 这个窄方法用于不重写其他地址字段的直接切换。
  Future<void> setDefault(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/setDefault',
      data: FormData.fromMap(<String, dynamic>{
        'id': id.toString(),
        'isDefault': '1',
      }),
    );
    _ok(resp.data ?? <String, dynamic>{});
  }

  void _ok(Map<String, dynamic> body) {
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
  }
}

/// 收货地址一行。
class MemberAddress {
  const MemberAddress({
    required this.id,
    required this.fullName,
    required this.mobilePhone,
    this.province,
    this.detailAddress,
    this.isDefault = false,
  });

  final int id;
  final String fullName;
  final String mobilePhone;

  /// ★ 这一栏装的是**省市区整串**,不是只有省 ——
  ///   实体上没有 city/area 两栏(后端 @Parameter:「province: 省市区」)。
  final String? province;

  final String? detailAddress;

  final bool isDefault;

  /// 拼好的一行地址。任一栏为空就只显示另一栏 ——
  /// 拼出带空洞的串比不显示更糟。
  String get oneLine => <String?>[
    province,
    detailAddress,
  ].where((String? s) => s != null && s.trim().isNotEmpty).join(' ');

  /// 这条有没有地址信息。**参与人行没有** —— 同一张表,两种用途。
  bool get hasAddress => oneLine.isNotEmpty;

  factory MemberAddress.fromJson(Map<String, dynamic> json) => MemberAddress(
    id: json['id'] is num ? (json['id'] as num).toInt() : 0,
    fullName: (json['fullName'] ?? '').toString(),
    mobilePhone: (json['mobilePhone'] ?? '').toString(),
    province: json['province']?.toString(),
    detailAddress: json['detailAddress']?.toString(),
    isDefault:
        json['isDefault'] == 1 ||
        json['isDefault'] == '1' ||
        json['isDefault'] == true,
  );
}
