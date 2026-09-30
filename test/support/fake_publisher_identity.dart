import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/publisher_identity_api.dart';
import 'package:chengyin_app/feature/publisher/publisher_identity.dart';

DioClient dummyDioClient() => DioClient(TokenStore(const FlutterSecureStorage()));

/// 记录调用的 PublisherIdentityApi 假实现(三入口行为测试共用)。
///
/// `registered` 控制 status() 回什么;`registerError` 让 register() 抛业务异常;
/// register 的四个入参按真接口形状原样记录,测试用它核对「字段没串、
/// 值已归一化、consent 恒真」。
class FakePublisherIdentityApi extends PublisherIdentityApi {
  FakePublisherIdentityApi({this.registered = false}) : super(dummyDioClient());

  bool registered;
  Object? registerError;

  int statusCalls = 0;
  final List<Map<String, Object?>> registerCalls =
      <Map<String, Object?>>[];

  @override
  Future<bool> status() async {
    statusCalls++;
    return registered;
  }

  @override
  Future<void> register({
    required String realName,
    required String idCard,
    required bool consent,
    required String source,
  }) async {
    registerCalls.add(<String, Object?>{
      'realName': realName,
      'idCard': idCard,
      'consent': consent,
      'source': source,
    });
    if (registerError != null) throw registerError!;
    registered = true;
  }
}

/// 一套能通过 checkIdentityForm 的合法表单值(身份证号校验位自洽)。
PublisherIdentityFormState validIdentityForm({String source = 'club_apply'}) {
  return PublisherIdentityFormState(
    realName: '陈晨',
    idCard: '99000019491231019X',
    consented: true,
    source: source,
  );
}
