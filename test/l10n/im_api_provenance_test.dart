import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:chengyin_app/l10n/app_localizations_zh.dart';
import 'package:chengyin_app/l10n/im_api_display.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends TokenStore {
  _Store() : super(const FlutterSecureStorage());
  @override
  Future<String?> read() async => 'test-token';
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DioClient client;
  late ImApi api;
  late Map<String, dynamic> body;
  setUp(() {
    body = {'code': 200};
    client = DioClient(_Store());
    client.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, data: body));
    }));
    api = ImApi(client);
  });
  tearDown(() => client.dio.close());

  test('receipt fallback differs from identical original server text', () async {
    final local = await api.blockReceipt(8);
    expect(local.serverMessage, isNull);
    expect(imReceiptText(local, AppLocalizationsEn()), 'Blocked');
    expect(imReceiptText(local, AppLocalizationsZh()), '已拉黑');
    body = {'code': 200, 'msg': '已拉黑'};
    final server = await api.blockReceipt(8);
    expect(imReceiptText(server, AppLocalizationsEn()), '已拉黑');
    expect(await api.block(8), '已拉黑');
  });

  test('report receipt promises review rather than deletion', () async {
    final receipt = await api.reportMessageReceipt(12, '原始举报原因');
    expect(imReceiptText(receipt, AppLocalizationsEn()), 'Report submitted for review');
    expect(await api.reportMessage(12, '原始举报原因'), '举报已提交,将进入审核');
    expect(imReceiptText(await api.muteReceipt(2, muted: false), AppLocalizationsEn()), 'Notifications unmuted');
    expect(imReceiptText(await api.deleteConversationReceipt(2), AppLocalizationsEn()), 'Conversation deleted');
  });

  test('typed local failure keeps terminal code while server text remains verbatim', () async {
    body = {'code': 400, 'errorCode': 'HANGOUT_CLOSED'};
    await expectLater(api.messages(7), throwsA(isA<ImApiException>()
      .having((e) => e.errorCode, 'terminal code', 'HANGOUT_CLOSED')
      .having((e) => imErrorText(e, AppLocalizationsEn()), 'localized fallback', 'The request failed')));
    body = {'code': 400, 'msg': '请求失败', 'errorCode': 'HANGOUT_CLOSED'};
    await expectLater(api.messages(7), throwsA(isA<ImApiException>()
      .having((e) => e.localReason, 'local provenance', isNull)
      .having((e) => e.errorCode, 'terminal code', 'HANGOUT_CLOSED')
      .having((e) => imErrorText(e, AppLocalizationsEn()), 'original', '请求失败')));
  });

  test('malformed successful start retains a local failure instead of chat zero', () async {
    body = {'code': 200, 'data': {'conversationId': 0}};
    await expectLater(api.startChat(8), throwsA(isA<ImApiException>()
      .having((e) => e.localReason, 'reason', ImLocalFailure.missingConversation)
      .having((e) => imErrorText(e, AppLocalizationsEn()), 'copy',
        'Could not start the chat. Try again later.')));
  });
}
