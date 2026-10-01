import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/my_project_api.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:chengyin_app/l10n/my_project_error_display.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  Map<String, dynamic> body = {'code': 409};
  final List<RequestOptions> sent = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    sent.add(options);
    return ResponseBody.fromString(jsonEncode(body), 200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('project reads preserve response code and exact backend errors', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    final adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close(force: true));
    final api = MyProjectApi(client);
    final strings = AppLocalizationsEn();
    final reads = <Future<Object?> Function()>[
      () => api.projectPlayers(topicId: 7),
      () => api.projectHome(topicId: 7),
      () => api.page(),
      () => api.publishHome(),
      () => api.recommendations(),
      () => api.worldHome(),
    ];
    for (final read in reads) {
      adapter.body = {'code': 409};
      await expectLater(read(), throwsA(isA<MyProjectApiException>()
        .having((e) => e.code, 'unchanged code', 409)
        .having((e) => myProjectErrorCopy(strings, e), 'local copy', 'Could not load')));
      for (final message in ['加载失败', '', '  ', 'Server message']) {
        adapter.body = {'code': 409, 'msg': message};
        await expectLater(read(), throwsA(isA<MyProjectApiException>()
          .having((e) => e.localCode, 'server provenance', isNull)
          .having((e) => myProjectErrorCopy(strings, e), 'exact message', message)));
      }
    }
    expect(adapter.sent.first.path, '/api/project/players');
    expect(adapter.sent.first.data, {'topicId': 7});
  });

  test('unsupported project action remains local and sends no request', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    final adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close(force: true));
    final api = MyProjectApi(client);
    final project = MyProject.fromJson({'id': 7, 'title': '服务端标题', 'bizType': 'unsupported'});
    await expectLater(api.remove(project), throwsA(isA<MyProjectApiException>()
      .having((e) => myProjectErrorCopy(AppLocalizationsEn(), e), 'local copy',
        'This type cannot be deleted yet')));
    expect(adapter.sent, isEmpty);
  });
}
