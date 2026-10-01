import 'package:chengyin_app/data/api/club_lead_api.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/feature/participation/participation_api.dart';
import 'package:chengyin_app/data/api/club_crm_api.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/profile_edit.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/request_session_scope.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _PausedRead extends TokenStore {
  _PausedRead() : super(const FlutterSecureStorage());
  final started = Completer<void>();
  final credential = Completer<String?>();
  @override
  Future<String?> read() {
    started.complete();
    return credential.future;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    return ResponseBody.fromString('{"code":200,"data":{}}', 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final operations = <String, Future<void> Function(DioClient)>{
    'team leader progress': (client) async { await ClubLeadApi(client).teamProgress(7); },
    'team leader broadcast': (client) => ClubLeadApi(client).broadcast(7, 'private announcement'),
    'team leader start': (client) => ClubLeadApi(client).start(7),
    'team leader arrive': (client) => ClubLeadApi(client).arrive(7),
    'team leader unlock': (client) => ClubLeadApi(client).unlockChapter(7),
    'team leader settle': (client) => ClubLeadApi(client).settle(7),
    'team leader redemption': (client) async { await RegistrationApi(client).scanGroupMemberTicket(code: 'private-code', activityId: 7); },
    'player paid cancellation': (client) async { await ActivityApi(client).cancelRegistrationWithOutcome(registrationId: 11, paid: true); },
    'player unpaid cancellation': (client) async { await ActivityApi(client).cancelRegistrationWithOutcome(registrationId: 11, paid: false); },
    'participation refund readback': (client) async { await ParticipationApi(client).list(); },
    'participation detail': (client) async { await ParticipationApi(client).detail(11); },
    'owner registration readback': (client) async {
      await ClubCrmApi(client).checkinDetail(clubId: 1, registrationId: 11);
    },
    'owner roster readback': (client) async {
      await ClubApi(client).topicRegistrations(clubId: 1, topicId: 11);
    },
    'owner registration cancellation': (client) async {
      await ClubApi(client).cancelRegistrationByOwner(11);
    },
    'read account profile': (client) async {
      await RegistrationApi(client).userDetail();
    },
    'save account profile': (client) => RegistrationApi(client).updateProfile(
      const ProfileEditForm(name: 'Account A edit'),
    ),
    'collaboration deposit creation': (client) async { await CoopApi(client).createDeposit(12); },
    'collaboration deposit readback': (client) async { await CoopApi(client).depositStatus(12); },
    'collaboration apply': (client) => CoopApi(client).apply(8),
    'collaboration withdraw': (client) => CoopApi(client).withdraw(8),
    'collaboration accept invitation': (client) => CoopApi(client).handleInvite(
      inviteId: 12, action: CoopHandleAction.accept,
    ),
    'send and retry': (client) async {
      await ImApi(client).send(9, content: 'Account A message',
          clientMessageId: '0123456789abcdef');
    },
    'read acknowledgement': (client) => ImApi(client).read(9),
    'invitation join': (client) async {
      await PageParityApi(client).teamJoin('invite-for-A');
    },
    'team leave': (client) => PageParityApi(client).teamAction('quit', {'teamId': 8}),
    'leader changes invitation mode': (client) =>
        TeamMapApi(client).setJoinMode(teamId: 8, inviteOnly: true),
  };
  for (final operation in operations.entries) {
    test('${operation.key}: account switch during token read prevents dispatch', () async {
      final store = _PausedRead();
      final client = DioClient(store);
      final adapter = _RecordingAdapter();
      client.dio.httpClientAdapter = adapter;
      bool current = true;
      final scope = RequestSessionScope(() => current);
      final request = RequestSessionScope.run(scope, () => operation.value(client));
      final failure = expectLater(request, throwsA(
        operation.key == 'leader changes invitation mode'
            ? isA<TeamMapApiException>()
            : operation.key == 'owner registration readback'
                ? isA<ClubCrmApiException>()
            : isA<DioException>().having((error) => error.type,
                'cancellation type', DioExceptionType.cancel),
      ));
      await store.started.future;
      current = false;
      store.credential.complete('account-B-token');
      await failure;
      expect(adapter.calls, isEmpty,
          reason: 'Account A intent must never reach HTTP with account B credential');
      client.dio.close();
    });
  }

  test('matching session sends with the credential read for that request', () async {
    final store = _PausedRead();
    final client = DioClient(store);
    final adapter = _RecordingAdapter();
    client.dio.httpClientAdapter = adapter;
    final request = RequestSessionScope.run(
      RequestSessionScope(() => true),
      () => ImApi(client).read(9),
    );
    await store.started.future;
    store.credential.complete('account-A-token');
    await request;
    expect(adapter.calls.single.headers['Authorization'], 'account-A-token');
    expect(adapter.calls.single.path, '/api/im/read');
    client.dio.close();
  });
}
