import 'dart:convert';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_operator_api.dart';
import 'package:chengyin_app/data/models/merchant_operator.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('team 只从操作员名单端点读取团队', () async {
    late RequestOptions sent;
    final MerchantOperatorApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'operators': const <dynamic>[],
          'invites': const <dynamic>[],
        },
      };
    });

    final team = await api.team();

    expect(sent.path, '/api/merchant/operators/list');
    expect(sent.method, 'POST');
    expect(sent.data, isNull);
    expect(team.activeOperators, isEmpty);
  });

  test('幂等意图跨 store 实例保留并可在确认后清理', () async {
    final Map<String, String> storage = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            final Map<Object?, Object?> args =
                call.arguments as Map<Object?, Object?>;
            final String key = args['key']! as String;
            return switch (call.method) {
              'read' => storage[key],
              'write' => storage[key] = args['value']! as String,
              'delete' => storage.remove(key),
              _ => null,
            };
          },
        );
    final SecureMerchantOperatorIntentStore first =
        SecureMerchantOperatorIntentStore(const FlutterSecureStorage());
    await first.write('invite:1:MERCHANT_FINANCE', 'merchant-invite:stable:1');

    final SecureMerchantOperatorIntentStore afterRestart =
        SecureMerchantOperatorIntentStore(const FlutterSecureStorage());
    expect(
      await afterRestart.read('invite:1:MERCHANT_FINANCE'),
      'merchant-invite:stable:1',
    );

    await afterRestart.delete('invite:1:MERCHANT_FINANCE');
    expect(await first.read('invite:1:MERCHANT_FINANCE'), isNull);
  });

  test('invite 只提交后端固定岗位和可重放 requestId', () async {
    late RequestOptions sent;
    final MerchantOperatorApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'invite': <String, dynamic>{
            'id': 21,
            'roleCode': 'MERCHANT_MARKETING',
            'status': 'PENDING',
            'expiresAt': '2026-08-28 10:30:00',
            'version': 0,
          },
          'token': 'merchant-invite-token-123456',
        },
      };
    });

    final MerchantInviteCreation creation = await api.invite(
      role: MerchantOperatorRole.marketing,
      requestId: 'merchant-invite:21:a1',
    );

    expect(sent.path, '/api/merchant/operators/invite');
    expect(sent.data, <String, dynamic>{
      'roleCode': 'MERCHANT_MARKETING',
      'requestId': 'merchant-invite:21:a1',
    });
    expect(creation.invite.id, 21);
    expect(creation.token, 'merchant-invite-token-123456');
  });

  test('改岗提交旧版本并校验精确新版本回执', () async {
    late RequestOptions sent;
    final MerchantOperatorApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 12,
          'nickname': '小林',
          'avatar': null,
          'roleCode': 'MERCHANT_FINANCE',
          'status': 'ACTIVE',
          'acceptedAt': '2026-08-27 10:30:00',
          'version': 4,
          'mutationState': 'EXACT_RESULT',
        },
      };
    });
    final MerchantOperator operator = _operator();

    final MerchantOperatorReceipt receipt = await api.updateRole(
      operator: operator,
      role: MerchantOperatorRole.finance,
      requestId: 'merchant-role:12:3:finance',
    );

    expect(sent.path, '/api/merchant/operators/role');
    expect(sent.data, <String, dynamic>{
      'operatorId': 12,
      'roleCode': 'MERCHANT_FINANCE',
      'version': 3,
      'requestId': 'merchant-role:12:3:finance',
    });
    expect(receipt.operator.version, 4);
  });

  test('改岗响应允许后续权威状态已经移除，但拒绝伪装成精确结果', () async {
    final MerchantOperatorApi api = _api((RequestOptions request) {
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 12,
          'nickname': '小林',
          'avatar': null,
          'roleCode': 'MERCHANT_CHECKIN',
          'status': 'REVOKED',
          'acceptedAt': '2026-08-27 10:30:00',
          'version': 5,
          'mutationState': 'LATER_AUTHORITATIVE',
        },
      };
    });

    final MerchantOperatorReceipt receipt = await api.updateRole(
      operator: _operator(),
      role: MerchantOperatorRole.finance,
      requestId: 'merchant-role:12:3:finance',
    );

    expect(receipt.mutationState, MerchantMutationState.laterAuthoritative);
    expect(receipt.operator.status, MerchantOperatorStatus.revoked);
    expect(receipt.operator.version, 5);

    final MerchantOperatorApi invalidExact = _api((RequestOptions request) {
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 12,
          'nickname': '小林',
          'avatar': null,
          'roleCode': 'MERCHANT_FINANCE',
          'status': 'REVOKED',
          'acceptedAt': '2026-08-27 10:30:00',
          'version': 4,
          'mutationState': 'EXACT_RESULT',
        },
      };
    });
    expect(
      () => invalidExact.updateRole(
        operator: _operator(),
        role: MerchantOperatorRole.finance,
        requestId: 'merchant-role:12:3:finance',
      ),
      throwsA(isA<MerchantOperatorApiException>()),
    );
  });

  test('移除成员与撤销邀请使用各自目标 ID、版本和原因', () async {
    final List<RequestOptions> sent = <RequestOptions>[];
    final MerchantOperatorApi api = _api((RequestOptions request) {
      sent.add(request);
      final bool operator = request.path.endsWith('/remove');
      return <String, dynamic>{
        'code': 200,
        'data': operator
            ? <String, dynamic>{
                'id': 12,
                'nickname': '小林',
                'avatar': null,
                'roleCode': 'MERCHANT_MARKETING',
                'status': 'REVOKED',
                'acceptedAt': '2026-08-27 10:30:00',
                'version': 4,
                'mutationState': 'EXACT_RESULT',
              }
            : <String, dynamic>{
                'id': 21,
                'roleCode': 'MERCHANT_FINANCE',
                'status': 'REVOKED',
                'expiresAt': '2026-08-28 10:30:00',
                'version': 1,
                'mutationState': 'EXACT_RESULT',
              },
      };
    });

    await api.remove(
      operator: _operator(),
      reason: ' 店主在经营团队页移除成员 ',
      requestId: 'merchant-remove:12:3',
    );
    await api.revokeInvite(
      invite: MerchantOperatorInvite(
        id: 21,
        role: MerchantOperatorRole.finance,
        status: MerchantInviteStatus.pending,
        expiresAt: DateTime(2026, 8, 28, 10, 30),
        version: 0,
      ),
      reason: '店主在经营团队页撤销邀请',
      requestId: 'merchant-revoke:21:0',
    );

    expect(sent.first.path, '/api/merchant/operators/remove');
    expect(sent.first.data, <String, dynamic>{
      'operatorId': 12,
      'version': 3,
      'reason': '店主在经营团队页移除成员',
      'requestId': 'merchant-remove:12:3',
    });
    expect(sent.last.path, '/api/merchant/operators/invite/revoke');
    expect((sent.last.data as Map<String, dynamic>)['inviteId'], 21);
  });

  test('接受邀请只提交一次凭证和 requestId', () async {
    late RequestOptions sent;
    final MerchantOperatorApi api = _api((RequestOptions request) {
      sent = request;
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'id': 18,
          'nickname': '小陈',
          'avatar': null,
          'roleCode': 'MERCHANT_CHECKIN',
          'status': 'ACTIVE',
          'acceptedAt': '2026-08-27 11:00:00',
          'version': 0,
        },
      };
    });

    final MerchantOperator operator = await api.acceptInvite(
      token: ' merchant-invite-token-123456 ',
      requestId: 'merchant-accept:18:a1',
    );

    expect(sent.path, '/api/merchant/operators/invite/accept');
    expect(sent.data, <String, dynamic>{
      'token': 'merchant-invite-token-123456',
      'requestId': 'merchant-accept:18:a1',
    });
    expect(operator.status, MerchantOperatorStatus.active);
  });
}

MerchantOperator _operator() => MerchantOperator(
  id: 12,
  nickname: '小林',
  avatar: null,
  role: MerchantOperatorRole.marketing,
  status: MerchantOperatorStatus.active,
  acceptedAt: DateTime(2026, 8, 27, 10, 30),
  version: 3,
);

MerchantOperatorApi _api(
  Map<String, dynamic> Function(RequestOptions request) reply,
) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = _StubAdapter(reply);
  return MerchantOperatorApi(client);
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions request) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
