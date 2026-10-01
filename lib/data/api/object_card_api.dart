import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/network/request_session_scope.dart';
import '../models/object_card.dart';

class ObjectCardApi {
  ObjectCardApi(this._client);
  final DioClient _client;

  /// Spring scalar parameters require form encoding. Ownership comes from JWT.
  /// The mini-program intentionally displays only the latest 40 per category.
  Future<ObjectCardCollection> list({String category = ''}) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/object-card/list',
      data: {'pageNum': 1, 'pageSize': 40, 'category': category},
      options: RequestSessionScope.options(
        Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    final body = response.data;
    if (body == null || body['code'].toString() != '200') {
      throw const FormatException('Object-card request failed');
    }
    return ObjectCardCollection.fromJson(body['data']);
  }
}
