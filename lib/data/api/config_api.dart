import '../../core/network/dio_client.dart';

/// 灰度功能开关接口（对齐 `/api/config/features`）。
class ConfigApi {
  ConfigApi(this._client);

  final DioClient _client;

  Future<Map<String, dynamic>> fetchFeatures() async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/config/features',
    );
    final body = response.data;
    if (body == null || body['code']?.toString() != '200') {
      return <String, dynamic>{};
    }
    final data = body['data'];
    if (data is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }
}
