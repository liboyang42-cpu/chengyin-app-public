import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/category.dart';

/// 分类接口。对齐后端 `ApiCategoryController`(/api/category)。
class CategoryApi {
  CategoryApi(this._client);
  final DioClient _client;

  /// 分类列表:`POST /api/category/list`(表单参数)。
  /// type=1主题 2活动 3创意广场。后端 `success(list)` → data 直接是数组(非 rows)。
  /// 注意:后端对 parentid 直接做 `.equals("0")`,必须显式传 "0" 否则 NPE。
  Future<List<Category>> list({String? type}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/category/list',
      data: FormData.fromMap(<String, dynamic>{
        'parentid': '0',
        'type': ?type,
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    final code = body['code'];
    if (code != 200) {
      throw Exception((body['msg'] as String?) ?? '分类加载失败');
    }
    // success(sysCategoryList) → data 直接是 List。
    final data = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return data
        .map((dynamic e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
