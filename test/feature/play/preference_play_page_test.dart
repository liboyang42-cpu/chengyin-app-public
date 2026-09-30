import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/data/models/preference_play.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'vm=6 uses server questions, validates required answers and retains choices on retry',
    (WidgetTester tester) async {
      final _PreferenceApi api = _PreferenceApi(
        questionnaire: PreferenceQuestionnaire.fromJson(<String, dynamic>{
          'nodeId': 17,
          'steps': <dynamic>[
            _step('space', '你更喜欢哪种空间？', '紧凑', '通透'),
            _step('discard', '必须舍弃一项', '收纳', '采光', type: 'discard'),
          ],
          'inheritedTags': <dynamic>[],
        }),
      );
      api.onSubmit = (Map<String, String> choices, String? reuseTagCode) async {
        if (api.submitChoices.length == 1) throw _networkUnknown();
        if (api.submitChoices.length == 2) {
          throw PlayException('路线状态已更新');
        }
        return _completed();
      };
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpPage(tester, api);

      expect(find.text('偏好题组'), findsOneWidget);
      await tester.tap(find.text('偏好校准'));
      await tester.pumpAndSettle();

      expect(find.text('你更喜欢哪种空间？'), findsOneWidget);
      expect(find.text('紧凑'), findsOneWidget, reason: '选项必须来自服务端题面');
      await tester.tap(find.text('下一题'));
      await tester.pump();
      expect(find.text('请选择一个答案'), findsOneWidget);

      await tester.tap(find.text('紧凑'));
      expect(
        tester
            .getSize(find.byKey(const Key('preference-option-space-A')))
            .height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('下一题'));
      await tester.pump();
      expect(find.text('必须舍弃一项'), findsOneWidget);
      await tester.tap(find.text('采光'));
      await tester.tap(find.text('生成我的结果'));
      await tester.pumpAndSettle();

      expect(find.text('网络连接失败，请重试'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const Key('preference-option-discard-B')),
        ),
        matchesSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          isSelected: true,
          label: '采光',
        ),
      );
      await tester.tap(find.text('上一题'));
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(const Key('preference-option-space-A'))),
        matchesSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          isSelected: true,
          label: '紧凑',
        ),
      );
      await tester.tap(find.text('下一题'));
      await tester.pump();

      await tester.tap(find.text('生成我的结果'));
      await tester.pumpAndSettle();
      expect(find.text('路线状态已更新'), findsOneWidget);

      await tester.tap(find.text('生成我的结果'));
      await tester.pumpAndSettle();

      expect(api.submitChoices, <Map<String, String>>[
        <String, String>{'space': 'A', 'discard': 'B'},
        <String, String>{'space': 'A', 'discard': 'B'},
        <String, String>{'space': 'A', 'discard': 'B'},
      ]);
      expect(find.text('小空间先减负'), findsOneWidget);
      expect(find.text('清掉一层柜子'), findsOneWidget);
      expect(api.fetchNodesCount, greaterThan(1), reason: '成功后已回拉权威节点');
      semantics.dispose();
    },
  );

  testWidgets(
    'duplicate taps submit once and server tiebreak extends the same choices',
    (WidgetTester tester) async {
      final Completer<PreferenceSubmission> first =
          Completer<PreferenceSubmission>();
      final _PreferenceApi api = _PreferenceApi(
        questionnaire: PreferenceQuestionnaire.fromJson(<String, dynamic>{
          'nodeId': 17,
          'steps': <dynamic>[_step('space', '选择空间', '紧凑', '通透')],
          'inheritedTags': <dynamic>[],
        }),
      );
      api.onSubmit = (Map<String, String> choices, String? reuseTagCode) =>
          api.submitChoices.length == 1
          ? first.future
          : Future.value(_completed());
      await _pumpPage(tester, api);
      await tester.tap(find.text('偏好校准'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('紧凑'));
      await tester.tap(find.text('生成我的结果'));
      await tester.pump();
      await tester.tap(find.text('正在生成'));
      await tester.pump();
      expect(api.submitChoices, hasLength(1));

      first.complete(
        PreferenceSubmission.fromJson(<String, dynamic>{
          'needsTiebreak': true,
          'tiebreak': _step('final', '最后一票', '收纳', '通透'),
          'choices': <String, dynamic>{'space': 'A'},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('最后一票'), findsOneWidget);
      await tester.tap(find.text('通透'));
      await tester.tap(find.text('生成我的结果'));
      await tester.pumpAndSettle();

      expect(api.submitChoices.last, <String, String>{
        'space': 'A',
        'final': 'B',
      });
      expect(find.text('小空间先减负'), findsOneWidget);
    },
  );

  testWidgets(
    'missing or empty server questions fail closed with a retry action',
    (WidgetTester tester) async {
      final _PreferenceApi api = _PreferenceApi(
        questionnaire: const PreferenceQuestionnaire(
          nodeId: 17,
          steps: <PreferenceStep>[],
          inheritedTags: <PreferenceInheritedTag>[],
        ),
      );
      await _pumpPage(tester, api);
      await tester.tap(find.text('偏好校准'));
      await tester.pumpAndSettle();

      expect(find.text('偏好题暂无可用题目，请联系活动方'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(api.submitChoices, isEmpty);
    },
  );

  testWidgets(
    'multiple inherited tags require selection and confirmation; cancel and retry retain it',
    (WidgetTester tester) async {
      final _PreferenceApi api = _PreferenceApi(
        questionnaire: PreferenceQuestionnaire.fromJson(<String, dynamic>{
          'nodeId': 17,
          'steps': <dynamic>[_step('space', '选择空间', '紧凑', '通透')],
          'inheritedTags': <dynamic>[
            <String, dynamic>{
              'id': 23,
              'tagCode': 'space_constraints',
              'tagValue': 'compact',
            },
            <String, dynamic>{
              'id': 24,
              'tagCode': 'light_preference',
              'tagValue': 'bright',
            },
          ],
        }),
      );
      api.onSubmit = (_, _) async {
        if (api.submitChoices.length == 1) throw _networkUnknown();
        return _completed();
      };
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpPage(tester, api);
      await tester.tap(find.text('偏好校准'));
      await tester.pumpAndSettle();

      expect(find.text('沿用你确认过的条件'), findsOneWidget);
      expect(find.text('space_constraints · compact'), findsOneWidget);
      expect(find.text('light_preference · bright'), findsOneWidget);
      expect(api.submitChoices, isEmpty, reason: '展示继承标签不能触发提交');

      await tester.tap(find.text('light_preference · bright'));
      await tester.pump();
      expect(api.submitChoices, isEmpty, reason: '选择标签也不能隐式提交');
      expect(
        tester.getSemantics(
          find.byKey(const Key('preference-inherited-tag-24')),
        ),
        matchesSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          isSelected: true,
          label: 'light_preference · bright',
        ),
      );

      await tester.tap(find.text('确认沿用，生成本站建议'));
      await tester.pumpAndSettle();
      expect(find.text('确认沿用这个条件？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.submitChoices, isEmpty, reason: '取消确认不能提交 reuseTagCode');

      await tester.tap(find.text('确认沿用，生成本站建议'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认沿用'));
      await tester.pumpAndSettle();
      expect(find.text('网络连接失败，请重试'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const Key('preference-inherited-tag-24')),
        ),
        matchesSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          isSelected: true,
          label: 'light_preference · bright',
        ),
      );

      await tester.tap(find.text('确认沿用，生成本站建议'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认沿用'));
      await tester.pumpAndSettle();

      expect(api.submitReuseCodes, <String?>[
        'light_preference',
        'light_preference',
      ]);
      expect(api.submitChoices, <Map<String, String>>[
        <String, String>{},
        <String, String>{},
      ]);
      expect(find.text('小空间先减负'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'pending tag shows disclosure and uses server correction and confirmation',
    (WidgetTester tester) async {
      final _PreferenceApi api = _PreferenceApi(
        questionnaire: PreferenceQuestionnaire.fromJson(<String, dynamic>{
          'nodeId': 17,
          'steps': <dynamic>[_step('space', '选择空间', '紧凑', '通透')],
          'inheritedTags': <dynamic>[],
        }),
      );
      api.onSubmit = (_, _) async => _completedWithPendingTag();
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpPage(tester, api);
      await tester.tap(find.text('偏好校准'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('紧凑'));
      await tester.tap(find.text('生成我的结果'));
      await tester.pumpAndSettle();

      expect(find.text('保存为我的主题标签?'), findsOneWidget);
      expect(find.text('space_constraints · compact'), findsOneWidget);
      expect(find.text('用于后续站点复用已确认的居住条件'), findsOneWidget);
      expect(find.text('传给：本主题后续站点'), findsOneWidget);
      expect(find.text('保存后仍可在完局页随时撤回。'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('preference-result-icon'))),
        matchesSemantics(label: '偏好结果已生成', isImage: true),
      );

      await tester.tap(find.text('结果不准？改一下标签档位'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(api.correctedTagValues, <String>['open']);
      expect(find.text('space_constraints · open'), findsOneWidget);

      await tester.tap(find.text('确认保存'));
      await tester.pumpAndSettle();
      expect(api.confirmedTagIds, <int>[23]);
      expect(find.text('已确认'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('missing tag disclosure blocks saving and skip stays local', (
    WidgetTester tester,
  ) async {
    final _PreferenceApi api = _PreferenceApi(
      questionnaire: PreferenceQuestionnaire.fromJson(<String, dynamic>{
        'nodeId': 17,
        'steps': <dynamic>[_step('space', '选择空间', '紧凑', '通透')],
        'inheritedTags': <dynamic>[],
      }),
    );
    api.onSubmit = (_, _) async =>
        _completedWithPendingTag(includeDisclosure: false);
    await _pumpPage(tester, api);
    await tester.tap(find.text('偏好校准'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('紧凑'));
    await tester.tap(find.text('生成我的结果'));
    await tester.pumpAndSettle();

    expect(find.text('标签用途说明不可用，暂不保存'), findsOneWidget);
    expect(find.text('确认保存'), findsNothing);
    expect(find.text('结果不准？改一下标签档位'), findsNothing);
    await tester.tap(find.text('先不保存'));
    await tester.pump();
    expect(find.text('保存为我的主题标签?'), findsNothing);
    expect(api.confirmedTagIds, isEmpty);
    expect(api.correctedTagValues, isEmpty);
  });
}

Future<void> _pumpPage(WidgetTester tester, _PreferenceApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(api),
        aiNpcApiProvider.overrideWithValue(_EmptyAiNpcApi()),
      ].cast(),
      child: const MaterialApp(home: PlaySessionPage(activityId: 41)),
    ),
  );
  await tester.pumpAndSettle();
}

class _PreferenceApi implements PlayApi {
  _PreferenceApi({required this.questionnaire});

  final PreferenceQuestionnaire questionnaire;
  int fetchNodesCount = 0;
  final List<Map<String, String>> submitChoices = <Map<String, String>>[];
  final List<String?> submitReuseCodes = <String?>[];
  final List<int> confirmedTagIds = <int>[];
  final List<String> correctedTagValues = <String>[];
  Future<PreferenceSubmission> Function(
    Map<String, String> choices,
    String? reuseTagCode,
  )?
  onSubmit;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    fetchNodesCount += 1;
    return PlayNodesResult(
      topicId: 71,
      mode: 1,
      playable: true,
      total: 1,
      doneCount: fetchNodesCount > 1 ? 1 : 0,
      nodes: <PlayNode>[
        PlayNode(
          nodeId: 17,
          name: '偏好校准',
          address: '测试地点',
          sortId: 1,
          done: fetchNodesCount > 1,
          validationMethod: 6,
        ),
      ],
      routeState: PlayRouteState.fromJson(<String, dynamic>{
        'routeMode': 'BRANCH_GRAPH',
        'sessionId': 91,
        'status': fetchNodesCount > 1 ? 'COMPLETED' : 'ACTIVE',
        'currentNodeId': fetchNodesCount > 1 ? null : 17,
        'recommendedNodeId': fetchNodesCount > 1 ? null : 17,
        'version': fetchNodesCount > 1 ? 2 : 1,
        'nodeStates': <String, dynamic>{
          '17': fetchNodesCount > 1 ? 'COMPLETED' : 'PLAYABLE',
        },
        'decisionLog': <dynamic>[],
      }),
    );
  }

  @override
  Future<PreferenceQuestionnaire> fetchPreference({
    int? activityId,
    int? topicId,
    required int nodeId,
  }) async => questionnaire;

  @override
  Future<PreferenceSubmission> submitPreference({
    int? activityId,
    int? topicId,
    required int nodeId,
    required Map<String, String> choices,
    String? reuseTagCode,
    RouteAdvanceToken? routeAdvance,
  }) async {
    submitChoices.add(Map<String, String>.from(choices));
    submitReuseCodes.add(reuseTagCode);
    return onSubmit!(choices, reuseTagCode);
  }

  @override
  Future<PreferenceInheritedTag> confirmPreferenceTag(int tagId) async {
    confirmedTagIds.add(tagId);
    return const PreferenceInheritedTag(
      id: 23,
      tagCode: 'space_constraints',
      tagValue: 'open',
      status: 1,
    );
  }

  @override
  Future<PreferenceInheritedTag> correctPreferenceTag(
    int tagId,
    String tagValue,
  ) async {
    correctedTagValues.add(tagValue);
    return PreferenceInheritedTag(
      id: tagId,
      tagCode: 'space_constraints',
      tagValue: tagValue,
      status: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyAiNpcApi implements AiNpcApi {
  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async => const <NpcProfile>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _step(
  String key,
  String title,
  String first,
  String second, {
  String type = 'single',
}) => <String, dynamic>{
  'key': key,
  'type': type,
  'title': title,
  'options': <dynamic>[
    <String, dynamic>{'key': 'A', 'text': first},
    <String, dynamic>{'key': 'B', 'text': second},
  ],
};

PreferenceSubmission _completed() =>
    PreferenceSubmission.fromJson(<String, dynamic>{
      'evaluation': <String, dynamic>{
        'resultCode': 'compact',
        'title': '小空间先减负',
        'body': '因为你选择了紧凑',
        'nextStep': '清掉一层柜子',
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
        'routeState': <String, dynamic>{
          'routeMode': 'BRANCH_GRAPH',
          'sessionId': 91,
          'status': 'COMPLETED',
          'currentNodeId': null,
          'recommendedNodeId': null,
          'version': 2,
          'nodeStates': <String, dynamic>{'17': 'COMPLETED'},
          'decisionLog': <dynamic>[],
        },
      },
    });

PreferenceSubmission _completedWithPendingTag({
  bool includeDisclosure = true,
}) => PreferenceSubmission.fromJson(<String, dynamic>{
  'evaluation': <String, dynamic>{
    'resultCode': 'compact',
    'title': '小空间先减负',
    'body': '因为你选择了紧凑',
    'nextStep': '清掉一层柜子',
    'nextStepDays': 7,
    'choices': <dynamic>['紧凑'],
  },
  'pendingTag': <String, dynamic>{
    'id': 23,
    'tagCode': 'space_constraints',
    'tagValue': 'compact',
    'status': 0,
  },
  if (includeDisclosure)
    'tagDisclosure': <String, dynamic>{
      'purpose': '用于后续站点复用已确认的居住条件',
      'recipientLabel': '本主题后续站点',
      'revocable': true,
    },
  'availableTagValues': <dynamic>['compact', 'open'],
  'progress': <String, dynamic>{
    'nodeId': 17,
    'firstTime': true,
    'done': 1,
    'total': 1,
    'completed': true,
    'newBadges': <dynamic>[],
    'routeState': <String, dynamic>{
      'routeMode': 'BRANCH_GRAPH',
      'sessionId': 91,
      'status': 'COMPLETED',
      'currentNodeId': null,
      'recommendedNodeId': null,
      'version': 2,
      'nodeStates': <String, dynamic>{'17': 'COMPLETED'},
      'decisionLog': <dynamic>[],
    },
  },
});

DioException _networkUnknown() => DioException(
  requestOptions: RequestOptions(path: '/api/play/preference/17/submit'),
  type: DioExceptionType.connectionError,
);
