import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/banner.dart';

/// 轮播图接口。对齐后端 `ApiCommonController`(/api/common/banner)。
class BannerApi {
  BannerApi(this._client);
  final DioClient _client;

  /// 轮播图:`POST /api/common/banner`(表单参数)。
  /// showType=1 首页头部轮播;linkType 玩家端传 0(后端仅当 linkType==1 才过滤)。
  /// 返回 AjaxResult.success(`List<SysBanner>`) → data 直接是数组。
  Future<List<HomeBanner>> list({int showType = 1, int linkType = 0}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/banner',
      data: FormData.fromMap(<String, dynamic>{
        'showType': showType.toString(),
        'linkType': linkType.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return data
        .map((dynamic e) => HomeBanner.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
