import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/preference_play.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tiebreak does not complete; final submit completes once and accepts routeState',
    () async {
      final _PreferencePlayApi api = _PreferencePlayApi(_nodes(version: 1));
      final _Harness harness = await _harness(api);
      addTearDown(harness.dispose);
      final int initialFetchCount = api.fetchCount;
      bool routeStateAcceptedBeforeReload = false;
      api.onFetch = () {
        if (api.submitCount == 2) {
          routeStateAcceptedBeforeReload =
              harness.container
                  .read(harness.provider)
                  .value
                  ?.routeState
                  ?.version ==
              2;
        }
      };
      api.onSubmit =
          (
            Map<String, String> choices,
            RouteAdvanceToken? token,
            String? reuseTagCode,
          ) async {
            if (api.submitCount == 1) {
              return PreferenceSubmission.fromJson(<String, dynamic>{
                'needsTiebreak': true,
                'tiebreak': _step('final', '最后一票'),
                'choices': choices,
              });
            }
            api.nodes = _nodes(version: 2);
            return _completed(version: 2);
          };

      final PreferenceSubmission tie = await harness.notifier.submitPreference(
        17,
        const <String, String>{'space': 'A'},
      );
      expect(tie.needsTiebreak, isTrue);
      expect(api.fetchCount, initialFetchCount, reason: '并列取舍尚未完成节点');

      final PreferenceSubmission completed = await harness.notifier
          .submitPreference(17, const <String, String>{
            'space': 'A',
            'final': 'B',
          });

      expect(completed.needsTiebreak, isFalse);
      expect(completed.evaluation, isNotNull);
      expect(completed.progress, isNotNull);
      expect(api.submitTokens, hasLength(2));
      expect(api.submitTokens.first?.actionId, api.submitTokens.last?.actionId);
      expect(api.fetchCount, initialFetchCount + 1, reason: '最终成功只刷新一次权威节点');
      expect(routeStateAcceptedBeforeReload, isTrue);
      expect(
        harness.container.read(harness.provider).value?.routeState?.version,
        2,
      );
    },
  );

  test(
    'network retry retains the branch route token while explicit rejection clears it',
    () async {
      final _PreferencePlayApi api = _PreferencePlayApi(_nodes(version: 5));
      final _Harness harness = await _harness(api);
      addTearDown(harness.dispose);
      api.onSubmit = (_, _, _) async {
        if (api.submitCount == 1) throw _networkUnknown();
        if (api.submitCount == 2) throw PlayException('选项已失效');
        api.nodes = _nodes(version: 6);
        return _completed(version: 6);
      };

      await expectLater(
        harness.notifier.submitPreference(17, const <String, String>{
          'space': 'A',
        }),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        harness.notifier.submitPreference(17, const <String, String>{
          'space': 'A',
        }),
        throwsA(isA<PlayException>()),
      );
      await harness.notifier.submitPreference(17, const <String, String>{
        'space': 'A',
      });

      expect(api.submitTokens[0]?.actionId, api.submitTokens[1]?.actionId);
      expect(
        api.submitTokens[2]?.actionId,
        isNot(api.submitTokens[1]?.actionId),
      );
    },
  );

  test('LINEAR preference completion sends no route token', () async {
    final _PreferencePlayApi api = _PreferencePlayApi(_nodes(linear: true));
    final _Harness harness = await _harness(api);
    addTearDown(harness.dispose);
    api.onSubmit = (_, _, _) async => _completed(version: null);

    await harness.notifier.submitPreference(17, const <String, String>{
      'space': 'A',
    });

    expect(api.submitTokens.single, isNull);
  });

  test(
    'explicit inherited tag reuse keeps its route token through retry',
    () async {
      final _PreferencePlayApi api = _PreferencePlayApi(_nodes(version: 5));
      final _Harness harness = await _harness(api);
      addTearDown(harness.dispose);
      api.onSubmit = (_, _, String? reuseTagCode) async {
        if (api.submitCount == 1) throw _networkUnknown();
        api.nodes = _nodes(version: 6);
        return _completed(version: 6);
      };

      await expectLater(
        harness.notifier.submitPreference(
          17,
          const <String, String>{},
          reuseTagCode: 'space_constraints',
        ),
        throwsA(isA<DioException>()),
      );
      await harness.notifier.submitPreference(
        17,
        const <String, String>{},
        reuseTagCode: 'space_constraints',
      );

      expect(api.submitReuseCodes, <String?>[
        'space_constraints',
        'space_constraints',
      ]);
      expect(api.submitTokens[0]?.actionId, api.submitTokens[1]?.actionId);
    },
  );

  test(
    'preference route 409 fetches authority and retries once with new token',
    () async {
      final _PreferencePlayApi api = _PreferencePlayApi(_nodes(version: 5));
      final _Harness harness = await _harness(api);
      addTearDown(harness.dispose);
      api.recoveredRouteState = _routeState(version: 6);
      api.onSubmit = (_, _, _) async {
        if (api.submitCount == 1) {
          throw PlayException('路线状态已更新', code: 409);
        }
        api.nodes = _nodes(version: 7);
        return _completed(version: 7);
      };

      await harness.notifier.submitPreference(17, const <String, String>{
        'space': 'A',
      });

      expect(api.fetchRouteStateCount, 1);
      expect(api.submitTokens, hasLength(2), reason: '冲突只允许自动重试一次');
      expect(api.submitTokens[0]?.expectedRouteVersion, 5);
      expect(api.submitTokens[1]?.expectedRouteVersion, 6);
      expect(
        api.submitTokens[1]?.actionId,
        isNot(api.submitTokens[0]?.actionId),
      );
    },
  );

  test(
    'preference route 409 never resubmits or fabricates reward when node is done',
    () async {
      final _PreferencePlayApi api = _PreferencePlayApi(_nodes(version: 5));
      final _Harness harness = await _harness(api);
      addTearDown(harness.dispose);
      api.recoveredRouteState = _routeState(version: 6, completed: true);
      api.onSubmit = (_, _, _) async {
        throw PlayException('路线状态已更新', code: 409);
      };

      await expectLater(
        harness.notifier.submitPreference(17, const <String, String>{
          'space': 'A',
        }),
        throwsA(
          isA<PlayException>().having(
            (PlayException error) => error.message,
            'message',
            '该节点已完成,请刷新后重试',
          ),
        ),
      );

      expect(api.fetchRouteStateCount, 1);
      expect(api.submitCount, 1, reason: '权威状态已完成时不能再次提交或伪造结果');
    },
  );
}

typedef _Harness = ({
  ProviderContainer container,
  PlaySessionController notifier,
  dynamic provider,
  void Function() dispose,
});

Future<_Harness> _harness(_PreferencePlayApi api) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
  );
  final provider = playSessionProvider((activityId: 41, topicId: null));
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  final PlaySessionController notifier = container.read(provider.notifier);
  await notifier.load();
  await Future<void>.delayed(Duration.zero);
  return (
    container: container,
    notifier: notifier,
    provider: provider,
    dispose: () {
      subscription.close();
      container.dispose();
    },
  );
}

class _PreferencePlayApi implements PlayApi {
  _PreferencePlayApi(this.nodes);

  PlayNodesResult nodes;
  int fetchCount = 0;
  int submitCount = 0;
  int fetchRouteStateCount = 0;
  PlayRouteState? recoveredRouteState;
  void Function()? onFetch;
  Future<PreferenceSubmission> Function(
    Map<String, String> choices,
    RouteAdvanceToken? token,
    String? reuseTagCode,
  )?
  onSubmit;
  final List<RouteAdvanceToken?> submitTokens = <RouteAdvanceToken?>[];
  final List<String?> submitReuseCodes = <String?>[];

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    fetchCount += 1;
    onFetch?.call();
    return nodes;
  }

  @override
  Future<PreferenceSubmission> submitPreference({
    int? activityId,
    int? topicId,
    required int nodeId,
    required Map<String, String> choices,
    String? reuseTagCode,
    RouteAdvanceToken? routeAdvance,
  }) async {
    submitCount += 1;
    submitTokens.add(routeAdvance);
    submitReuseCodes.add(reuseTagCode);
    return onSubmit!(choices, routeAdvance, reuseTagCode);
  }

  @override
  Future<PlayRouteState> fetchRouteState({
    int? activityId,
    int? topicId,
  }) async {
    fetchRouteStateCount += 1;
    return recoveredRouteState!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlayNodesResult _nodes({bool linear = false, int version = 1}) =>
    PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 71,
      'mode': 1,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      'nodes': <dynamic>[],
      'routeState': <String, dynamic>{
        'routeMode': linear ? 'LINEAR' : 'BRANCH_GRAPH',
        'sessionId': linear ? null : 91,
        'status': 'ACTIVE',
        'currentNodeId': 17,
        'recommendedNodeId': 17,
        'version': version,
        'nodeStates': <String, dynamic>{'17': 'PLAYABLE'},
        'decisionLog': <dynamic>[],
      },
    });

PlayRouteState _routeState({required int version, bool completed = false}) =>
    PlayRouteState.fromJson(<String, dynamic>{
      'routeMode': 'BRANCH_GRAPH',
      'sessionId': 91,
      'status': completed ? 'COMPLETED' : 'ACTIVE',
      'currentNodeId': completed ? null : 17,
      'recommendedNodeId': completed ? null : 17,
      'version': version,
      'nodeStates': <String, dynamic>{
        '17': completed ? 'COMPLETED' : 'PLAYABLE',
      },
      'decisionLog': <dynamic>[],
    })!;

PreferenceSubmission _completed({required int? version}) =>
    PreferenceSubmission.fromJson(<String, dynamic>{
      'evaluation': <String, dynamic>{
        'resultCode': 'compact',
        'title': '先减负',
        'body': '你选择了紧凑',
        'nextStep': '清理一层柜子',
        'nextStepDays': 7,
        'choices': <dynamic>['紧凑'],
      },
      'progress': <String, dynamic>{
        'nodeId': 17,
        'firstTime': true,
        'done': 1,
        'total': 1,
        'completed': true,
        'newBadges': <dynamic>[],
        if (version != null)
          'routeState': <String, dynamic>{
            'routeMode': 'BRANCH_GRAPH',
            'sessionId': 91,
            'status': 'COMPLETED',
            'currentNodeId': null,
            'recommendedNodeId': null,
            'version': version,
            'nodeStates': <String, dynamic>{'17': 'COMPLETED'},
            'decisionLog': <dynamic>[],
          },
      },
    });

Map<String, dynamic> _step(String key, String title) => <String, dynamic>{
  'key': key,
  'type': 'single',
  'title': title,
  'options': <dynamic>[
    <String, dynamic>{'key': 'A', 'text': '紧凑'},
    <String, dynamic>{'key': 'B', 'text': '通透'},
  ],
};

DioException _networkUnknown() => DioException(
  requestOptions: RequestOptions(path: '/api/play/preference/17/submit'),
  type: DioExceptionType.connectionError,
);
