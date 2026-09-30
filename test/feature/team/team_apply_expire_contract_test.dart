// 申请失效时刻(applyExpireTime)与申请留言的链路契约。
//
// ★ 真源 = github/master@a7d179760(经 ~/Downloads/chengyin 对账,晚于本模型
//   原快照 master@90e66d70):
//     subpackageRoam/utils/map-team.js            expireLeft / 三处消费面 / messageText
//     tests/unit/apply-expire-contract.test.js    契约逐条对拍
//   migration_20260915_play_team_public_apply.sql:真实失效 = min(申请+24h, 场次开始)。
//   活动 2 小时后开场时申请 2 小时就失效,前端写死「24 小时」就是撒谎 ——
//   xcx 契约测试专门钉了「兜底文案不许再断言 24 小时」。
// ★ 申请留言(2026-09-17 拍板第19条):留言**弹层**因需扩展原生输入桥
//   (内容行 + maxlength)另行立项;这里先钉**队长侧展示面** —— 小程序用户
//   发的 applyMessage 必须能进 P5 审批行(服务端已做 200 字上限与机审)。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/data/models/team_map.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/team/team_nearby_page.dart';

import '../../support/source_text.dart';

final DateTime _now = DateTime.parse('2026-09-16T20:00:00');
final int _expire2h = _now.add(const Duration(hours: 2)).millisecondsSinceEpoch;

Map<String, dynamic> _base() => <String, dynamic>{
  'teamId': 7,
  'title': '外滩夜行',
  'activityId': 11,
  'activityName': '外滩夜行 · 周五 19:30 场',
  'topicId': 3,
  'productType': 1,
  'joinedCount': 2,
  'maxMembers': 4,
  'viewerHasTicket': true,
};

void main() {
  group('expireLeft:以服务端 applyExpireTime 为准', () {
    test('epoch 毫秒:说真实剩余,不再出现「24 小时」', () {
      final TeamCardState s = teamCardState(<String, dynamic>{
        ..._base(),
        'viewerStatus': 'PENDING',
        'applyExpireTime': _expire2h,
      }, now: _now);
      expect(s.mode, 'pending');
      expect(s.foot, isNot(contains('24 小时')));
      expect(s.foot, '队长没处理的话,申请 2 小时后自动失效');
    });

    test('「yyyy-MM-dd HH:mm:ss」字符串同样能算(与 appliedAt 同格式)', () {
      final TeamCardState s = teamCardState(<String, dynamic>{
        ..._base(),
        'viewerStatus': 'PENDING',
        'applyExpireTime': '2026-09-16 21:30:00',
      }, now: _now);
      // 90 分钟按快照口径向下取整成小时(min<60 才说分钟)。
      expect(s.foot, '队长没处理的话,申请 1 小时后自动失效');
    });

    test('不足 1 分钟说「1 分钟」;小时向下取整', () {
      String foot(Duration left) => teamCardState(<String, dynamic>{
        ..._base(),
        'viewerStatus': 'PENDING',
        'applyExpireTime': _now.add(left).millisecondsSinceEpoch,
      }, now: _now).foot;
      expect(foot(const Duration(seconds: 30)), contains('1 分钟后自动失效'));
      expect(
        foot(const Duration(hours: 2, minutes: 59)),
        contains('2 小时后自动失效'),
      );
    });

    test('拿不到 / 已过期 / 解析不出来:兜底句非空且不断言 24 小时', () {
      for (final Object? bad in <Object?>[
        null,
        '',
        '不是时间',
        _now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
      ]) {
        final TeamCardState s = teamCardState(<String, dynamic>{
          ..._base(),
          'viewerStatus': 'PENDING',
          'applyExpireTime': bad,
        }, now: _now);
        expect(s.foot, isNotEmpty);
        expect(s.foot, isNot(contains('24')));
        expect(s.foot, '队长没处理或活动开始时,申请自动失效');
      }
    });
  });

  test('P6「申请中」行说真实剩余时间', () {
    final List<MyTeamRow> rows = myTeamRows(
      <Map<String, dynamic>>[],
      <Map<String, dynamic>>[
        <String, dynamic>{
          'teamId': 8,
          'title': '苏河湾探店日',
          'leaderName': '阿May',
          'applyStatus': 'PENDING',
          'applyExpireTime': _expire2h,
        },
      ],
      now: _now,
    );
    expect(rows, hasLength(1));
    expect(rows.first.sub, contains('2 小时后失效'));
    expect(rows.first.sub, isNot(contains('24')));
  });

  test('P5 申请列表行:剩余时间与留言都进视图', () {
    final List<TeamApplicantRow> rows = teamApplicantRows(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'memberId': 5,
          'memberName': '阿杰',
          'memberAvatar': 'x',
          'appliedAt': '2026-09-16 19:58:00',
          'applyExpireTime': _expire2h,
          'applyMessage': '同场两个人,想拼个合影',
        },
        <String, dynamic>{
          'memberId': 6,
          'memberName': '阿May',
          'appliedAt': '2026-09-16 19:59:00',
        },
      ],
      _now,
    );
    expect(rows.first.sub, contains('2 小时后失效'));
    expect(rows.first.sub, isNot(contains('24')));
    expect(rows.first.messageText, '“同场两个人,想拼个合影”');
    // 空留言不渲染引号框(与 coop 申请留言同一口径)。
    expect(rows[1].messageText, '');
    expect(rows[1].sub, '持本场票 · 1 分钟前申请');
  });

  test('卡片文案模块不再出现写死的「24 小时」', () {
    expect(codeOf('lib/data/models/team_map.dart'), isNot(contains('24 小时')));
  });

  group('TeamMapApi.apply 回执', () {
    test('data.applyExpireTime 透出给页面回填卡片;没带就是 null', () async {
      final _StubAdapter adapter = _StubAdapter(
        (_) => <String, dynamic>{
          'code': 200,
          'msg': '已申请，等待队长同意',
          'data': <String, dynamic>{'applyExpireTime': _expire2h},
        },
      );
      final TeamMapApi api = TeamMapApi(_client(adapter));
      expect(await api.apply(7), _expire2h);
      expect(adapter.sent.single.path, '/api/team/apply');
    });

    test('回执没有 data 也不炸,返回 null', () async {
      final _StubAdapter adapter = _StubAdapter(
        (_) => <String, dynamic>{'code': 200, 'msg': 'ok'},
      );
      final TeamMapApi api = TeamMapApi(_client(adapter));
      expect(await api.apply(7), isNull);
    });
  });

  testWidgets('页面接线:申请成功 foot 立刻说真实剩余时间,不写死 24 小时', (
    WidgetTester tester,
  ) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        <String, dynamic>{
          ..._base(),
          'viewerStatus': 'NONE',
          'addressName': '外滩源',
          'coordSource': 'GATHER',
          'latitude': 31.2,
          'longitude': 121.4,
          'distance': 600,
          'leaderName': '小周',
          'memberAvatars': const <String>['a.png'],
        },
      ]
      ..applyReceipt = DateTime.now()
          .add(const Duration(hours: 2, minutes: 5))
          .millisecondsSinceEpoch;
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_SignedInAuth.new),
        ].cast(),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TeamNearbyPage(
            api: api,
            locate: () async =>
                const MapCoordinate(latitude: 31.2304, longitude: 121.4737),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('外滩夜行 · 周五 19:30 场'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('申请加入'));
    await tester.pumpAndSettle();

    expect(api.applied, <int>[7]);
    final Text foot = tester.widget<Text>(find.textContaining('后自动失效'));
    expect(foot.data, isNot(contains('24')));
    expect(foot.data, '队长没处理的话,申请 2 小时后自动失效');
  });
}

DioClient _client(_StubAdapter adapter) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = adapter;
  return client;
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> Function(RequestOptions options) reply;
  final List<RequestOptions> sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SignedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

/// 与 team_nearby_page_test 同型的假接口:只记调用,不碰网络。
class _FakeTeamMapApi extends TeamMapApi {
  _FakeTeamMapApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<Map<String, dynamic>> teams = <Map<String, dynamic>>[];
  Object? applyReceipt;
  final List<int> applied = <int>[];

  @override
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async => teams;

  @override
  Future<Object?> apply(int teamId) async {
    applied.add(teamId);
    return applyReceipt;
  }

  @override
  Future<void> withdraw(int teamId) async {}

  @override
  Future<List<Map<String, dynamic>>> myTeams() async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> myApplications() async =>
      <Map<String, dynamic>>[];
}
