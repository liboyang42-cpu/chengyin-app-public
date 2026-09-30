import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/creator_center.dart';

/// 创作者中心。后端两条接口(`/api/creator/center` · `/apply`)一直都在,
/// App 侧此前**一条没接** —— 用户申请不了创作者,也看不到自己的申请到哪一步。
class CreatorApi {
  CreatorApi(this._client);
  final DioClient _client;

  /// 创作者中心。返回四态之一,见 [CreatorApplyStatus]。
  Future<CreatorCenter> center() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/creator/center',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '加载失败').toString());
    }
    return CreatorCenter.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 申请成为创作者。
  ///
  /// ⚠️ 后端收的是**表单**(CreatorProfileApplyDTO 没标 @RequestBody),
  ///   传 JSON 它读不到字段 —— 会变成一次「提交成功但什么都没存」的静默失败。
  /// ⚠️⚠️ 2026-08-20 更正:这个方法原来声明返回 `CreatorCenter`,
  ///   而后端 `ICreatorCenterService.apply` 返回的是 **int**
  ///   (`success(int)` ⇒ data 是个数字,不是对象)。
  ///   于是 `body['data'] as Map?` 恒 null ⇒ `CreatorCenter.fromJson({})`
  ///   ⇒ status 落回 `not_applied` ⇒ **申请成功后界面还显示「去申请」**。
  ///   零调用方,所以一直没人发现。
  ///
  /// ★★ 而且 `code` 恒 200:后端把「没存进去」表达成 **data == 0**,不是错误码。
  ///   不判 data 就是把失败当成功报。这里改成返回 bool,0 一律当失败。
  ///
  /// ⚠️ 后端 `apply` 开头有一条 `if (selectByMemberId(memberId) != null) return 0;`
  ///   —— **只要有过档案就拒收**,所以被驳回的人**永远重申请不了**。
  ///   这不是客户端能绕的,页面必须如实说,不能给一张按下去必失败的表单。
  Future<bool> apply({
    required String creatorName,
    String? bio,
    String? avatarUrl,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/creator/apply',
      data: FormData.fromMap(<String, dynamic>{
        'creatorName': creatorName,
        if (bio != null && bio.isNotEmpty) 'bio': bio,
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '提交失败').toString());
    }
    // data 是受影响行数:1 = 存进去了,0 = 没有(名称为空 / 已有档案)。
    final Object? data = body['data'];
    return data is num && data > 0;
  }
}
