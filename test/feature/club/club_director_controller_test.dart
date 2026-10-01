// 导演台写状态机(club_director_controller.dart)的行为测试。
//
// 这个控制器的价值不在「发请求」,而在三条安全出口:
//   ① 每条写先落存根再发;② 拿不到终态回执一律 unknown-write 锁全部写;
//   ③ 核对用原 requestId 回读(绝不重发),重试才用同 requestId 重放。
// 下面每条断言都对着「接错了会悄悄重复扣一次 / 丢一次动作」的场景写。

import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/data/models/user.dart';
import '../../support/fixed_auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/club_director.dart';
import 'package:chengyin_app/feature/club/club_director_controller.dart';

const int _activityId = 41;

class _ChangingAuth extends AuthController {
  @override
  AuthState build() => signedInAuthState();
  void switchTo(int? id, {bool loading = false}) => state = AuthState(
    initialized: true, loading: loading,
    user: id == null ? null : User(id: id, nickname: 'user', avatar: '', role: 'player'),
  );
}

class _LegacyStore extends ClubDirectorPendingStore {
  _LegacyStore() : super.memory(ownerId: 1);
  @override
  Future<bool> hasUnownedLegacy(int activityId) async => true;
}


class _FakeDirectorGateway implements ClubDirectorGateway {
  _FakeDirectorGateway(this.projection);

  ClubDirectorProjection projection;
  Object? loadError;
  Completer<ClubDirectorProjection>? delayedLoad;
  Completer<GameSessionReceipt>? delayedSubmit;

  /// submitClubCommand 依次弹出:GameSessionReceipt 直接返回,其余抛出。
  final List<Object> submitQueue = <Object>[];

  /// readClubReceipt 依次弹出,同上。
  final List<Object> receiptQueue = <Object>[];

  final List<GameSessionCommand> submitted = <GameSessionCommand>[];
  final List<Map<String, String>> receiptReads = <Map<String, String>>[];
  int loadCalls = 0;

  @override
  Future<ClubDirectorProjection> loadClubProjection({
    required int activityId,
  }) async {
    loadCalls += 1;
    if (delayedLoad != null) return delayedLoad!.future;
    if (loadError != null) throw loadError!;
    return projection;
  }

  @override
  Future<GameSessionReceipt> submitClubCommand(
    GameSessionCommand command,
  ) async {
    submitted.add(command);
    if (delayedSubmit != null) return delayedSubmit!.future;
    if (submitQueue.isNotEmpty) {
      final Object next = submitQueue.removeAt(0);
      if (next is GameSessionReceipt) return next;
      throw next;
    }
    return _applied(command.requestId, command.action);
  }

  @override
  Future<GameSessionReceipt> readClubReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async {
    receiptReads.add(<String, String>{
      'requestId': requestId,
      'expectedAction': expectedAction,
    });
    if (receiptQueue.isNotEmpty) {
      final Object next = receiptQueue.removeAt(0);
      if (next is GameSessionReceipt) return next;
      throw next;
    }
    return _applied(requestId, expectedAction);
  }
}

GameSessionReceipt _applied(String requestId, String action) =>
    GameSessionReceipt(
      activityId: _activityId,
      requestId: requestId,
      action: action,
      outcome: GameReceiptOutcome.applied,
      receiptId: 'rcpt-$action',
      revision: 99,
    );

GameSessionReceipt _terminal({
  required String requestId,
  required String action,
  required GameReceiptOutcome outcome,
}) => GameSessionReceipt(
  activityId: _activityId,
  requestId: requestId,
  action: action,
  outcome: outcome,
  receiptId: 'rcpt-$action',
  revision: 99,
);

DioException _networkDown() => DioException(
  requestOptions: RequestOptions(path: '/api/game/session/command'),
  type: DioExceptionType.connectionTimeout,
);

ClubDirectorProjection _projection({
  String status = 'RUNNING',
  int revision = 3,
  List<String> actions = const <String>['FINISH'],
  Map<String, dynamic>? club,
}) => ClubDirectorProjection.fromJson(<String, dynamic>{
  'perspective': 'CLUB',
  'activityId': _activityId,
  'status': status,
  'revision': revision,
  'availableActions': actions,
  'club':
      club ??
      <String, dynamic>{
        'readiness': <String, dynamic>{
          'requiredStations': 0,
          'readyStations': 0,
          'teamsReady': false,
        },
      },
});

class _BrokenWriteStore extends ClubDirectorPendingStore {
  _BrokenWriteStore() : super.memory();

  @override
  Future<void> write(ClubDirectorPendingWrite value) async {
    throw const FlutterSecureStorageErrorStub();
  }
}

/// 任意异常即可 —— 控制器只把「存根落不下去」当写不安全的信号。
class FlutterSecureStorageErrorStub implements Exception {
  const FlutterSecureStorageErrorStub();
}

({
  ProviderContainer container,
  _FakeDirectorGateway gateway,
  ClubDirectorController controller,
})
_harness({
  required ClubDirectorProjection projection,
  ClubDirectorPendingStore? store,
}) {
  final _FakeDirectorGateway gateway = _FakeDirectorGateway(projection);
  // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,靠推断。
  final ProviderContainer container = ProviderContainer(
    overrides: [
      signedInAuthOverride(),
      clubDirectorApiProvider.overrideWithValue(gateway),
      clubDirectorPendingStoreProvider.overrideWith(
        (ref) => store ?? ClubDirectorPendingStore.memory(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    gateway: gateway,
    controller: container.read(clubDirectorProvider(_activityId).notifier),
  );
}

ClubDirectorState _state(ProviderContainer container) =>
    container.read(clubDirectorProvider(_activityId));

Future<ClubDirectorController> _readyHarness(
  ClubDirectorProjection projection,
) async {
  final ({
    ProviderContainer container,
    _FakeDirectorGateway gateway,
    ClubDirectorController controller,
  })
  h = _harness(projection: projection);
  await h.controller.load();
  return h.controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pending storage is owner namespaced and legacy data is not adopted', () async {
    FlutterSecureStorage.setMockInitialValues({
      'club_director_pending_v1_41': 'legacy-unowned-private-payload',
    });
    const storage = FlutterSecureStorage();
    final first = ClubDirectorPendingStore(storage, ownerId: 1);
    final second = ClubDirectorPendingStore(storage, ownerId: 2);
    final pending = ClubDirectorPendingWrite.fromCommand(GameSessionCommand(
      activityId: 41, nodeId: null, requestId: 'owner-one-123', expectedRevision: 3,
      action: 'FINISH', payload: const {},
    ));
    await first.write(pending);
    expect((await first.read(41))?.requestId, pending.requestId);
    expect(await second.read(41), isNull);
    expect(await second.hasUnownedLegacy(41), isTrue);
    await second.clear(41);
    expect((await first.read(41))?.requestId, pending.requestId);
    expect(await storage.read(key: 'club_director_pending_v1_41'), 'legacy-unowned-private-payload');
  });

  test('account transition clears projection and rejects late read completion', () async {
    final gateway = _FakeDirectorGateway(_projection())
      ..delayedLoad = Completer<ClubDirectorProjection>();
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_ChangingAuth.new),
      clubDirectorApiProvider.overrideWithValue(gateway),
      clubDirectorPendingStoreProvider.overrideWith((ref) => ClubDirectorPendingStore.memory()),
    ]);
    addTearDown(container.dispose);
    final listener = container.listen(clubDirectorProvider(_activityId), (_, __) {});
    addTearDown(listener.close);
    final controller = container.read(clubDirectorProvider(_activityId).notifier);
    final loading = controller.load();
    await Future<void>.delayed(Duration.zero);
    (container.read(authControllerProvider.notifier) as _ChangingAuth).switchTo(2);
    await container.pump();
    gateway.delayedLoad!.complete(_projection());
    await loading;
    expect(_state(container).projection, isNull);
    expect(_state(container).writeLocked, isFalse);
    (container.read(authControllerProvider.notifier) as _ChangingAuth).switchTo(null);
    await container.pump();
    await controller.load();
    expect(gateway.loadCalls, 1);
  });

  test('late command receipt never clears persisted pending or changes new account', () async {
    final gateway = _FakeDirectorGateway(_projection());
    final store = ClubDirectorPendingStore.memory(ownerId: 1);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_ChangingAuth.new),
      clubDirectorApiProvider.overrideWithValue(gateway),
      clubDirectorPendingStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    final listener = container.listen(clubDirectorProvider(_activityId), (_, __) {});
    addTearDown(listener.close);
    final controller = container.read(clubDirectorProvider(_activityId).notifier);
    await controller.load();
    gateway.delayedSubmit = Completer<GameSessionReceipt>();
    final writing = controller.finish();
    await Future<void>.delayed(Duration.zero);
    final command = gateway.submitted.single;
    (container.read(authControllerProvider.notifier) as _ChangingAuth).switchTo(2);
    await container.pump();
    gateway.delayedSubmit!.complete(_applied(command.requestId, command.action));
    await writing;
    expect(_state(container).projection, isNull);
    expect(_state(container).refreshTick, 0);
    expect((await store.read(_activityId))?.requestId, command.requestId);
  });

  test('legacy unowned pending blocks new commands without replay or deletion', () async {
    final h = _harness(projection: _projection(), store: _LegacyStore());
    await h.controller.load();
    expect(_state(h.container).writeLocked, isTrue);
    expect(_state(h.container).canRetryUnknownWrite, isFalse);
    expect(await h.controller.finish(), ClubDirectorWriteResult.blocked);
    expect(await h.controller.reconcileOutcome(), isNull);
    expect(h.gateway.submitted, isEmpty);
    expect(h.gateway.receiptReads, isEmpty);
  });

  test('local message provenance clears when a raw server message replaces it', () {
    const local = ClubDirectorState(activityId: 41,
      writeMessage: '正在提交…', localWriteMessage: ClubDirectorLocalMessage.submitting);
    expect(local.copyWith(refreshTick: 1).localWriteMessage, ClubDirectorLocalMessage.submitting);
    final raw = local.copyWith(writeMessage: '正在提交…');
    expect(raw.writeMessage, local.writeMessage);
    expect(raw.localWriteMessage, isNull);
    expect(local.copyWith(writeMessage: '').localWriteMessage, isNull);
  });

  test('controller separates local fallback from identical backend explanation', () async {
    final h = _harness(projection: _projection());
    h.gateway.loadError = _networkDown();
    await h.controller.load();
    expect(_state(h.container).localErrorMessage, ClubDirectorLocalMessage.networkUnavailable);
    h.gateway.loadError = const GameSessionContractException('网络不可用，请稍后重试');
    await h.controller.load();
    expect(_state(h.container).errorText, '网络不可用，请稍后重试');
    expect(_state(h.container).localErrorMessage, isNull);
    h.gateway.loadError = const GameSessionContractException('活动导演数据与当前活动不匹配',
      reasonCode: 'PROJECTION_MISMATCH', isLocal: true);
    await h.controller.load();
    expect(_state(h.container).localErrorMessage, ClubDirectorLocalMessage.projectionMismatch);
  });

  group('三态主链:PREPARE / START / FINISH', () {
    test('PREPARE:无局空壳(revision 0)进准备 → APPLIED → confirmed,主页面回读', () async {
      // `club: null` + NOT_PREPARED + PREPARE 是合法开局入口(适配器闸)。
      final ClubDirectorProjection shell = ClubDirectorProjection.fromJson(
        <String, dynamic>{
          'perspective': 'CLUB',
          'activityId': _activityId,
          'status': 'NOT_PREPARED',
          'revision': 0,
          'availableActions': <String>['PREPARE'],
        },
      );
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: shell);
      await h.controller.load();
      expect(h.controller.state.load, ClubDirectorLoadState.ready);

      final ClubDirectorWriteResult result = await h.controller.prepare();

      expect(result, ClubDirectorWriteResult.confirmed);
      final GameSessionCommand command = h.gateway.submitted.single;
      expect(command.action, 'PREPARE');
      expect(command.activityId, _activityId);
      expect(command.nodeId, isNull, reason: '俱乐部动作除暂停/恢复外整局为对象');
      expect(command.expectedRevision, 0);
      expect(
        command.requestId,
        matches(r'^gd-41-\d+-\d+$'),
        reason: r'请求号必须过服务端 ^[A-Za-z0-9_-]{8,64}$ 这关',
      );
      expect(
        RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(command.requestId),
        isTrue,
      );
      expect(_state(h.container).refreshTick, 1, reason: '写被确认 → 宿主页一起回读');
      expect(h.gateway.loadCalls, 2, reason: '确认后再拉一次投影');
      expect(_state(h.container).writeState, ClubDirectorWriteState.idle);
    });

    test('START:READY + 站点全 READY + 队伍就绪才给开', () async {
      final ClubDirectorProjection ready = _projection(
        status: 'READY',
        actions: <String>['START'],
        club: <String, dynamic>{
          'readiness': <String, dynamic>{
            'requiredStations': 2,
            'readyStations': 2,
            'teamsReady': true,
          },
        },
      );
      expect(ready.canStart, isTrue);
      final ClubDirectorController controller = await _readyHarness(ready);

      final ClubDirectorWriteResult result = await controller.start();

      expect(result, ClubDirectorWriteResult.confirmed);
      expect(controller.state.projection?.status, 'READY');
    });

    test('START 缺一个条件就不能开:站点没齐 / 队伍没就绪 / 服务端没给动作', () {
      ClubDirectorProjection withReadiness({
        int required = 2,
        int ready = 2,
        bool? teamsReady = true,
        List<String> actions = const <String>['START'],
      }) => _projection(
        status: 'READY',
        actions: actions,
        club: <String, dynamic>{
          'readiness': <String, dynamic>{
            'requiredStations': required,
            'readyStations': ready,
            'teamsReady': teamsReady,
          },
        },
      );
      expect(withReadiness(ready: 1).canStart, isFalse);
      expect(withReadiness(teamsReady: false).canStart, isFalse);
      expect(withReadiness(teamsReady: null).canStart, isFalse);
      expect(withReadiness(actions: const <String>[]).canStart, isFalse);
      expect(
        withReadiness(required: 0, ready: 0).canStart,
        isFalse,
        reason: '零站点不算备好',
      );
    });

    test('FINISH:进行中 → confirmed,写消息清空、闸门放回 idle', () async {
      final ClubDirectorController controller = await _readyHarness(
        _projection(actions: <String>['FINISH']),
      );

      expect(await controller.finish(), ClubDirectorWriteResult.confirmed);
      expect(controller.state.writeState, ClubDirectorWriteState.idle);
      expect(controller.state.writeMessage, '');
      expect(controller.state.writeLocked, isFalse);
    });

    test('投影没就绪(还没 load)不发写;锁着也不发', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      expect(
        await h.controller.finish(),
        ClubDirectorWriteResult.blocked,
        reason: 'loadState 还在 loading,连 requestId 都不该生成',
      );
      expect(h.gateway.submitted, isEmpty);
    });
  });

  group('写安全内核:unknown-write 锁 → 核对 / 重试', () {
    test('拿不到终态回执(连业务报错)→ 锁全部写;后续写一律 blocked', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();
      h.gateway.submitQueue.add(_networkDown());

      expect(await h.controller.finish(), ClubDirectorWriteResult.unknown);
      final ClubDirectorState locked = _state(h.container);
      expect(locked.writeState, ClubDirectorWriteState.unknownWrite);
      expect(locked.writeLocked, isTrue);
      expect(locked.writeMessage, '请求结果待核对，核对前已锁定全部写操作');
      expect(locked.canRetryUnknownWrite, isTrue);

      expect(
        await h.controller.prepare(),
        ClubDirectorWriteResult.blocked,
        reason: '上一笔还没收敛,任何新写都不许出发',
      );
      expect(h.gateway.submitted, hasLength(1), reason: 'blocked 不许真的再发');
    });

    test('待处理回执(pending)同样锁;pending 不是 applied', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();
      h.gateway.submitQueue.add(
        _terminal(
          requestId: 'whatever',
          action: 'FINISH',
          outcome: GameReceiptOutcome.pending,
        ),
      );

      expect(await h.controller.finish(), ClubDirectorWriteResult.unknown);
      expect(_state(h.container).writeMessage, '结果待核对，核对前已锁定全部写操作');
    });

    test('核对结果:用原 requestId 回读,绝不重发;APPLIED →「结果已确认」', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();
      h.gateway.submitQueue.add(_networkDown());
      await h.controller.finish();
      final String originalRequestId = h.gateway.submitted.single.requestId;

      expect(await h.controller.reconcile(), '结果已确认');
      expect(h.gateway.receiptReads.single, <String, String>{
        'requestId': originalRequestId,
        'expectedAction': 'FINISH',
      });
      expect(h.gateway.submitted, hasLength(1), reason: '核对 = 回读,不是重发');
      expect(_state(h.container).writeLocked, isFalse);
      expect(_state(h.container).writeState, ClubDirectorWriteState.idle);
      expect(_state(h.container).refreshTick, 0, reason: '核对收敛只重拉投影,不惊动宿主页');
    });

    test('核对回执是明确拒绝 →「操作未生效」,收敛回 idle', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();
      h.gateway.submitQueue.add(_networkDown());
      await h.controller.finish();
      h.gateway.receiptQueue.add(GameSessionRejectedException('这一场已经结束了'));

      expect(await h.controller.reconcile(), '操作未生效');
      expect(_state(h.container).writeState, ClubDirectorWriteState.idle);
      expect(_state(h.container).writeMessage, '');
    });

    test('核对还是读不到 → 继续锁,只换文案', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();
      h.gateway.submitQueue.add(_networkDown());
      await h.controller.finish();
      h.gateway.receiptQueue.add(
        const GameSessionContractException(
          '还在写',
          reasonCode: 'RECEIPT_PENDING',
        ),
      );

      expect(await h.controller.reconcile(), isNull);
      final ClubDirectorState stillLocked = _state(h.container);
      expect(stillLocked.writeLocked, isTrue);
      expect(stillLocked.writeMessage, '结果仍待核对，写操作继续锁定');
      expect(stillLocked.canRetryUnknownWrite, isTrue);
    });

    test('没锁定时 reconcile 是 no-op,不发任何请求', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();

      expect(await h.controller.reconcile(), isNull);
      expect(h.gateway.receiptReads, isEmpty);
    });

    test('重试原操作 = 同 requestId 同 payload 重放;服务端幂等收敛', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();
      h.gateway.submitQueue.add(_networkDown());
      await h.controller.finish();
      final GameSessionCommand original = h.gateway.submitted.single;

      expect(
        await h.controller.retryPending(),
        ClubDirectorWriteResult.confirmed,
      );
      final GameSessionCommand replayed = h.gateway.submitted.last;
      expect(replayed.requestId, original.requestId, reason: '重放必须用原请求号');
      expect(replayed.action, original.action);
      expect(replayed.payload, original.payload);
      expect(_state(h.container).writeLocked, isFalse);
    });

    test('重试还拿不到终态 → 继续锁,可再核对/再重试', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      await h.controller.load();
      h.gateway.submitQueue
        ..add(_networkDown())
        ..add(_networkDown());
      await h.controller.finish();
      expect(
        await h.controller.retryPending(),
        ClubDirectorWriteResult.unknown,
      );
      expect(_state(h.container).writeMessage, '重试结果仍待核对，写操作继续锁定');
      expect(_state(h.container).canRetryUnknownWrite, isTrue);
    });

    test('终态 FAILED 回执 → rejected:明确没生效,存根清掉、闸门放回', () async {
      final ClubDirectorPendingStore store = ClubDirectorPendingStore.memory();
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection(), store: store);
      await h.controller.load();
      h.gateway.submitQueue.add(
        _terminal(
          requestId: 'x',
          action: 'FINISH',
          outcome: GameReceiptOutcome.failed,
        ),
      );

      expect(await h.controller.finish(), ClubDirectorWriteResult.rejected);
      final ClubDirectorState after = _state(h.container);
      expect(after.writeState, ClubDirectorWriteState.idle);
      expect(after.writeMessage, '操作未生效，请刷新后重试');
      expect(after.writeLocked, isFalse);
      expect(await store.read(_activityId), isNull, reason: '终态回执后不许留存根');
    });

    test('存根落不下去 = 一条都不发:storageError 挡在提交之前', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection(), store: _BrokenWriteStore());
      await h.controller.load();

      expect(
        await h.controller.finish(),
        ClubDirectorWriteResult.blocked,
        reason: '发出去就没法核对的操作,宁可不发',
      );
      expect(h.gateway.submitted, isEmpty);
      final ClubDirectorState after = _state(h.container);
      expect(after.writeState, ClubDirectorWriteState.storageError);
      expect(after.writeMessage, '无法安全保存本次操作，请检查存储后重试');
      expect(after.canRetryUnknownWrite, isFalse);
    });

    test('重启恢复:load 先捞存根进锁定,投影就绪后自动核对收敛', () async {
      final ClubDirectorPendingStore store = ClubDirectorPendingStore.memory();
      const ClubDirectorPendingWrite orphan = ClubDirectorPendingWrite(
        activityId: _activityId,
        nodeId: null,
        requestId: 'gd-restore-fixed01',
        expectedRevision: 3,
        action: 'FINISH',
        payload: <String, dynamic>{},
      );
      await store.write(orphan);
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection(), store: store);

      await h.controller.load();

      expect(h.gateway.receiptReads.single, <String, String>{
        'requestId': 'gd-restore-fixed01',
        'expectedAction': 'FINISH',
      }, reason: '恢复的写用原请求号回读,不重发');
      expect(h.gateway.submitted, isEmpty, reason: '核对不是重试');
      expect(
        _state(h.container).writeLocked,
        isFalse,
        reason: '回执 APPLIED,收敛完成',
      );
      expect(await store.read(_activityId), isNull);
    });
  });

  group('D 档分支:真源 payload 闸', () {
    test('CLUB_STATION_PAUSE:带备用方案时 payload 齐;恢复时间 = now+30min 整分', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(
        projection: _projection(actions: <String>['CLUB_STATION_PAUSE']),
      );
      await h.controller.load();

      final ClubDirectorWriteResult result = await h.controller.stationPause(
        7,
        reason: '  商家设备故障  ',
        plan: const ClubDirectorFallbackPlan(planCode: 'PLAN_B', version: 2),
        now: DateTime(2026, 9, 19, 10, 5),
      );

      expect(result, ClubDirectorWriteResult.confirmed);
      final GameSessionCommand command = h.gateway.submitted.single;
      expect(command.action, 'CLUB_STATION_PAUSE');
      expect(command.nodeId, 7, reason: '暂停挂在具体站点上(俱乐部唯二带 nodeId 的动作)');
      expect(command.payload, <String, dynamic>{
        'reasonCode': 'ONSITE',
        'reason': '商家设备故障',
        'resumeEta': '2026-09-19 10:35:00',
        'fallbackPlanCode': 'PLAN_B',
        'fallbackPlanVersion': 2,
      });
    });

    test('CLUB_STATION_PAUSE 的闸:没动作 / 原因少于 2 字都不发', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(
        projection: _projection(actions: <String>['CLUB_STATION_PAUSE']),
      );
      await h.controller.load();
      expect(
        await h.controller.stationPause(7, reason: '忙'),
        ClubDirectorWriteResult.blocked,
      );
      expect(h.gateway.submitted, isEmpty);

      final ClubDirectorController noAction = await _readyHarness(
        _projection(actions: <String>['FINISH']),
      );
      expect(
        await noAction.stationPause(7, reason: '商家设备故障'),
        ClubDirectorWriteResult.blocked,
        reason: '服务端没给这个动作,按钮都不该亮',
      );
    });

    test(
      'CLUB_REJECT_SUBMISSION:驳回重交 payload 带 submissionId + ONSITE_REJECT',
      () async {
        final ({
          ProviderContainer container,
          _FakeDirectorGateway gateway,
          ClubDirectorController controller,
        })
        h = _harness(
          projection: _projection(actions: <String>['CLUB_REJECT_SUBMISSION']),
        );
        await h.controller.load();

        expect(
          await h.controller.rejectSubmission(submissionId: 88, reason: '重拍'),
          ClubDirectorWriteResult.confirmed,
        );
        final GameSessionCommand command = h.gateway.submitted.single;
        expect(command.action, 'CLUB_REJECT_SUBMISSION');
        expect(command.nodeId, isNull, reason: '驳回以整局为对象(不挂站点)');
        expect(command.payload, <String, dynamic>{
          'submissionId': 88,
          'reasonCode': 'ONSITE_REJECT',
          'reason': '重拍',
        });

        expect(
          await h.controller.rejectSubmission(submissionId: 89, reason: '差'),
          ClubDirectorWriteResult.blocked,
          reason: '真源同闸:理由至少 2 个字,玩家会看到',
        );
        expect(h.gateway.submitted, hasLength(1));
      },
    );

    test('BROADCAST:TEAM 档必须带 targetId,缺了命令构造就挡下不发', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection(actions: <String>['BROADCAST']));
      await h.controller.load();

      expect(
        await h.controller.broadcast(targetType: 'TEAM', content: '请到门口集合'),
        ClubDirectorWriteResult.blocked,
      );
      expect(h.gateway.submitted, isEmpty);

      expect(
        await h.controller.broadcast(
          targetType: 'TEAM',
          content: '请到门口集合',
          targetId: 5,
        ),
        ClubDirectorWriteResult.confirmed,
      );
      expect(h.gateway.submitted.single.payload, <String, dynamic>{
        'targetType': 'TEAM',
        'content': '请到门口集合',
        'targetId': 5,
      });
    });

    test('TAKEOVER_ROLE:来源未确认 / 目标已有角色 → blocked;合法对才发同队接管', () async {
      final ClubDirectorProjection withRoles = _projection(
        actions: <String>['TAKEOVER_ROLE'],
        club: <String, dynamic>{
          'readiness': <String, dynamic>{'requiredStations': 0},
          'roles': <Map<String, dynamic>>[
            <String, dynamic>{
              'teamId': 5,
              'memberId': 11,
              'roleCode': 'LEADER',
              'confirmationStatus': 'CONFIRMED',
            },
            <String, dynamic>{'teamId': 5, 'memberId': 12},
            <String, dynamic>{'teamId': 5, 'memberId': 13, 'roleCode': 'PHOTO'},
          ],
        },
      );
      expect(withRoles.takeoverCandidates.single.memberId, 11);
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: withRoles);
      await h.controller.load();

      expect(
        await h.controller.takeover(
          teamId: 5,
          sourceMemberId: 11,
          targetMemberId: 13,
          reason: '队长掉线',
        ),
        ClubDirectorWriteResult.blocked,
        reason: '13 已有角色,不是合法目标',
      );
      expect(
        await h.controller.takeover(
          teamId: 5,
          sourceMemberId: 12,
          targetMemberId: 11,
          reason: '队长掉线',
        ),
        ClubDirectorWriteResult.blocked,
        reason: '12 没确认角色,不能当来源',
      );

      expect(
        await h.controller.takeover(
          teamId: 5,
          sourceMemberId: 11,
          targetMemberId: 12,
          reason: '队长掉线',
        ),
        ClubDirectorWriteResult.confirmed,
      );
      expect(h.gateway.submitted.single.payload, <String, dynamic>{
        'teamId': 5,
        'sourceMemberId': 11,
        'targetMemberId': 12,
        'reason': '队长掉线',
      });
    });

    test(
      'ASSIGN_ROLES:没下发角色选项(roleOptions 空)就挡 —— canAssignRoles 不只是动作',
      () async {
        final ({
          ProviderContainer container,
          _FakeDirectorGateway gateway,
          ClubDirectorController controller,
        })
        h = _harness(
          projection: _projection(actions: <String>['ASSIGN_ROLES']),
        );
        await h.controller.load();
        expect(h.controller.state.projection?.canAssignRoles, isFalse);
        expect(
          await h.controller.assignRole(
            teamId: 5,
            memberId: 12,
            roleCode: 'LEADER',
          ),
          ClubDirectorWriteResult.blocked,
        );
        expect(h.gateway.submitted, isEmpty);
      },
    );

    test('UNLOCK_CHAPTER:候选闸 —— 不在 unlockChapterOptions 里的章节不发', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(
        projection: _projection(
          actions: <String>['UNLOCK_CHAPTER'],
          club: <String, dynamic>{
            'readiness': <String, dynamic>{'requiredStations': 0},
            'chapterOptions': <Map<String, dynamic>>[
              <String, dynamic>{'chapterId': 2, 'title': '第二章'},
            ],
          },
        ),
      );
      await h.controller.load();
      // 当前章节(=1)即便下发也在适配器闸之外被 unlockChapterOptions 排除。
      expect(
        await h.controller.unlockChapter(chapterId: 1, reason: '现场进度快'),
        ClubDirectorWriteResult.blocked,
      );
      expect(
        await h.controller.unlockChapter(chapterId: 2, reason: '现场进度快'),
        ClubDirectorWriteResult.confirmed,
      );
      expect(h.gateway.submitted.single.payload, <String, dynamic>{
        'chapterId': 2,
        'reason': '现场进度快',
      });
    });
  });

  group('投影读取分类', () {
    test('「局不存在」是空态不是报错;空态文案指路去开场', () async {
      final _FakeDirectorGateway gateway = _FakeDirectorGateway(_projection())
        ..loadError = const GameSessionContractException(
          '这一场还没开局',
          reasonCode: 'SESSION_NOT_FOUND',
        );
      final ProviderContainer container = ProviderContainer(
        overrides: [
      signedInAuthOverride(),
          clubDirectorApiProvider.overrideWithValue(gateway),
          clubDirectorPendingStoreProvider.overrideWith(
            (ref) => ClubDirectorPendingStore.memory(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final ClubDirectorController controller = container.read(
        clubDirectorProvider(_activityId).notifier,
      );

      await controller.load();

      final ClubDirectorState after = _state(container);
      expect(after.load, ClubDirectorLoadState.empty);
      expect(after.errorText, '这一场还没开局');
      expect(after.writeLocked, isFalse, reason: '空态不该带写锁');
    });

    test('传输失败 → networkError +「网络不可用」;其余信封错 → businessError', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      h.gateway.loadError = _networkDown();
      await h.controller.load();
      expect(_state(h.container).load, ClubDirectorLoadState.networkError);
      expect(_state(h.container).errorText, '网络不可用，请稍后重试');

      h.gateway.loadError = const GameSessionContractException(
        '没有权限',
        reasonCode: 'FORBIDDEN',
      );
      await h.controller.load();
      expect(_state(h.container).load, ClubDirectorLoadState.businessError);
      expect(_state(h.container).errorText, '没有权限');
    });

    // #258 同一口径:后端用 HTTP 401 表态「你没登录/登录过期」,既不是断网
    // 也不是没权限 —— 把它说成「暂时无法打开/查网络」是条按多少次都还是 401
    // 的死路。控制器要给出可判定的登录信号,页面据此挂登录引导。
    test('401(游客/登录过期)→ loginRequired 信号,不冒充网络错误', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      h.gateway.loadError = DioException(
        requestOptions: RequestOptions(path: '/api/game/session/view'),
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/game/session/view'),
          statusCode: 401,
          data: <String, dynamic>{'code': 401, 'msg': '登录状态已失效，请重新登录'},
        ),
      );
      await h.controller.load();
      final ClubDirectorState after = _state(h.container);
      expect(after.loginRequired, isTrue);
      expect(after.writeLocked, isFalse, reason: '读不过不该带写锁');

      // 登录成功后的回读要能把信号收回去。
      h.gateway.loadError = null;
      await h.controller.load();
      expect(_state(h.container).loginRequired, isFalse);
      expect(_state(h.container).load, ClubDirectorLoadState.ready);
    });

    test('真业务错/403(非 401)仍走原口径,不推登录', () async {
      final ({
        ProviderContainer container,
        _FakeDirectorGateway gateway,
        ClubDirectorController controller,
      })
      h = _harness(projection: _projection());
      h.gateway.loadError = const GameSessionContractException(
        '服务端拒绝了这次读取',
        reasonCode: 'OWNER_REQUIRED',
      );
      await h.controller.load();
      expect(_state(h.container).loginRequired, isFalse);
      expect(_state(h.container).load, ClubDirectorLoadState.businessError);
      expect(_state(h.container).errorText, '服务端拒绝了这次读取');

      h.gateway.loadError = DioException(
        requestOptions: RequestOptions(path: '/api/game/session/view'),
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/game/session/view'),
          statusCode: 403,
        ),
      );
      await h.controller.load();
      expect(_state(h.container).loginRequired, isFalse);

      h.gateway.loadError = _networkDown();
      await h.controller.load();
      expect(_state(h.container).loginRequired, isFalse);
      expect(_state(h.container).load, ClubDirectorLoadState.networkError);
    });
  });
}
