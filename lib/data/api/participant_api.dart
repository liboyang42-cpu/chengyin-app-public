import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';

/// 参与人信息(姓名 + 手机号)。
///
/// ★ 后端复用的是**地址表** `ums_member_address`(`/api/user/address/*`)——
///   小程序的 `mode=participant` 只是把省市区/详细地址那几栏藏起来,存的是同一张表。
///   所以这里不新建概念,直接对齐那组端点,只是不碰地址字段。
class ParticipantApi {
  ParticipantApi(this._client);
  final DioClient _client;

  /// 我的参与人列表:`POST /api/user/address/list`(分页,列表在 data.rows)。
  Future<List<Participant>> list() async {
    final resp = await _client.dio.post<Map<String, dynamic>>('/api/user/address/list');
    final body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final rows = (data['rows'] as List<dynamic>?) ?? const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Participant.fromJson)
        .toList();
  }

  /// 新增或编辑:`POST /api/user/address/action`(表单;传 id 是编辑,不传是新增)。
  Future<void> save({
    int? id,
    required String fullName,
    required String mobilePhone,
    bool isDefault = false,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/action',
      data: FormData.fromMap(<String, dynamic>{
        if (id != null) 'id': id.toString(),
        'fullName': fullName,
        'mobilePhone': mobilePhone,
        'isDefault': isDefault ? '1' : '0',
      }),
    );
    _assertOk(resp.data ?? <String, dynamic>{});
  }

  /// 删除:`POST /api/user/address/delete`。
  Future<void> remove(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/delete',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    _assertOk(resp.data ?? <String, dynamic>{});
  }

  void _assertOk(Map<String, dynamic> body) {
    if (body['code'] != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
  }

  /// 设为默认参与人:`POST /api/user/address/setDefault`(id)。
  ///
  /// ★ App 此前**只能在新增/编辑表单里勾「设为默认」** —— 已经存在的那几位
  ///   想改默认,只能进编辑页改一遍再保存。后端专门有这条接口,一直没接。
  ///
  /// ⚠️ 后端 `rows == 1` 才算成功,否则回 ADDRESS_UNAVAILABLE ——
  ///   那既可能是 id 不存在,也可能**不属于当前用户**(selectOwned 语义)。
  ///   两种都别猜成「网络问题」,原样透传。
  Future<void> setDefault(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/address/setDefault',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '设置失败');
    }
  }
}

/// 参与人。只取姓名/手机号两栏 —— 地址字段属于收货场景,报名用不到。
class Participant {
  const Participant({
    required this.id,
    required this.fullName,
    required this.mobilePhone,
    this.isDefault = false,
  });

  final int id;
  final String fullName;
  final String mobilePhone;
  final bool isDefault;

  /// 列表里显示的掩码手机号。
  ///
  /// ★ 这是**用户自己看自己的**信息,掩码是习惯不是合规要求;
  ///   真正的脱敏在服务端。别把掩码后的值当成可提交的数据 —— 提交一律用原值。
  String get maskedPhone => mobilePhone.length == 11
      ? '${mobilePhone.substring(0, 3)}****${mobilePhone.substring(7)}'
      : mobilePhone;

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullName: (json['fullName'] as String?) ?? '',
      mobilePhone: (json['mobilePhone'] as String?) ?? '',
      isDefault: (json['isDefault'] as num?)?.toInt() == 1,
    );
  }
}
