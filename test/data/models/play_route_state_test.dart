import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Map<String, dynamic> completeRouteState = <String, dynamic>{
    'routeMode': 'BRANCH_GRAPH',
    'sessionId': 91,
    'status': 'ACTIVE',
    'currentNodeId': 7,
    'recommendedNodeId': 8,
    'version': 4,
    'nodeStates': <String, dynamic>{
      '7': 'COMPLETED',
      '8': 'PLAYABLE',
      '9': 'DISCOVERED_LOCKED',
      '10': 'HIDDEN',
    },
    'decisionLog': <dynamic>[
      <String, dynamic>{
        'fromNodeId': 7,
        'outcomeCode': 'SUCCESS',
        'edgeId': 'edge-7-8',
        'toNodeId': 8,
        'reason': 'MATCHED',
        'at': '2026-09-09T12:00:00.000Z',
      },
    ],
  };

  test('完整 routeState 解析为强类型状态与 decision，并挂载到 nodes/reward', () {
    final PlayNodesResult nodes = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 3,
      'mode': 1,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      'nodes': <dynamic>[],
      'routeState': completeRouteState,
    });
    final CheckinReward reward = CheckinReward.fromJson(<String, dynamic>{
      'nodeId': 7,
      'firstTime': true,
      'done': 1,
      'total': 2,
      'completed': false,
      'newBadges': <dynamic>[],
      'routeState': completeRouteState,
    });

    expect(nodes.routeState?.routeMode, PlayRouteMode.branchGraph);
    expect(nodes.routeState?.sessionId, 91);
    expect(nodes.routeState?.version, 4);
    expect(nodes.routeState?.recommendedNodeId, 8);
    expect(nodes.routeState?.nodeStates, <int, PlayRouteNodeState>{
      7: PlayRouteNodeState.completed,
      8: PlayRouteNodeState.playable,
      9: PlayRouteNodeState.discoveredLocked,
      10: PlayRouteNodeState.hidden,
    });
    expect(reward.routeState?.version, 4);
    expect(reward.decision?.fromNodeId, 7);
    expect(reward.decision?.outcomeCode, 'SUCCESS');
    expect(reward.decision?.edgeId, 'edge-7-8');
    expect(reward.decision?.toNodeId, 8);
    expect(reward.decision?.reason, 'MATCHED');
    expect(reward.decision?.at, DateTime.utc(2026, 9, 9, 12));
  });

  test('routeState 缺失时 nodes/reward 保持 null，不把 LINEAR 猜出来', () {
    final PlayNodesResult nodes = PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 3,
      'mode': 1,
      'playable': true,
      'total': 0,
      'doneCount': 0,
      'nodes': <dynamic>[],
    });
    final CheckinReward reward = CheckinReward.fromJson(<String, dynamic>{
      'nodeId': 7,
      'newBadges': <dynamic>[],
    });

    expect(nodes.routeState, isNull);
    expect(reward.routeState, isNull);
    expect(reward.decision, isNull);
  });

  test('脏 routeState fail-closed；脏 nodeState/decision 项被过滤', () {
    expect(PlayRouteState.fromJson('not-a-map'), isNull);
    expect(
      PlayRouteState.fromJson(<String, dynamic>{
        'routeMode': 'BRANCH_GRAPH',
        'status': 'ACTIVE',
        'version': 'not-a-version',
      }),
      isNull,
    );
    expect(
      PlayRouteState.fromJson(<String, dynamic>{
        'routeMode': 'UNKNOWN',
        'status': 'ACTIVE',
        'version': 1,
      }),
      isNull,
    );
    expect(
      PlayRouteState.fromJson(<String, dynamic>{
        'routeMode': 'BRANCH_GRAPH',
        'status': 'ACTIVE',
        'version': 1,
      }),
      isNull,
      reason: 'BRANCH 没有真实 sessionId 时不能签发推进票据',
    );

    final PlayRouteState? mixed = PlayRouteState.fromJson(<String, dynamic>{
      ...completeRouteState,
      'nodeStates': <String, dynamic>{
        '8': 'PLAYABLE',
        'bad-id': 'COMPLETED',
        '9': 'UNKNOWN',
      },
      'decisionLog': <dynamic>[
        (completeRouteState['decisionLog']! as List<dynamic>).single,
        'dirty',
        <String, dynamic>{'fromNodeId': 'bad'},
      ],
    });

    expect(mixed?.nodeStates, <int, PlayRouteNodeState>{
      8: PlayRouteNodeState.playable,
    });
    expect(mixed?.decisionLog, hasLength(1));
  });
}
