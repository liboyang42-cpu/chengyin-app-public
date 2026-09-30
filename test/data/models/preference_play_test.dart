import 'package:chengyin_app/data/models/preference_play.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loads server-authored single/discard steps and filters malformed entries',
    () {
      final PreferenceQuestionnaire questionnaire =
          PreferenceQuestionnaire.fromJson(<String, dynamic>{
            'nodeId': '17',
            'steps': <dynamic>[
              <String, dynamic>{
                'key': 'space',
                'type': 'single',
                'title': '你更喜欢哪种空间？',
                'options': <dynamic>[
                  <String, dynamic>{'key': 'A', 'text': '紧凑'},
                  <String, dynamic>{'key': 'B', 'text': '通透'},
                ],
              },
              <String, dynamic>{
                'key': 'tradeoff',
                'type': 'discard',
                'title': '必须舍弃一项',
                'options': <dynamic>[
                  <String, dynamic>{'key': 'A', 'text': '收纳'},
                  <String, dynamic>{'key': 'B', 'text': '采光'},
                ],
              },
              <String, dynamic>{
                'key': 'empty',
                'type': 'single',
                'title': '空选项',
                'options': <dynamic>[],
              },
            ],
            'inheritedTags': <dynamic>[
              <String, dynamic>{
                'id': 9,
                'tagCode': 'space_constraints',
                'tagValue': 'compact',
              },
              'bad',
            ],
          });

      expect(questionnaire.nodeId, 17);
      expect(questionnaire.steps, hasLength(2));
      expect(questionnaire.steps.first.type, PreferenceStepType.single);
      expect(questionnaire.steps.last.type, PreferenceStepType.discard);
      expect(questionnaire.steps.last.options.last.text, '采光');
      expect(questionnaire.inheritedTags.single.tagCode, 'space_constraints');
    },
  );

  test(
    'malformed or absent questions remain empty instead of inventing content',
    () {
      for (final Object? rawSteps in <Object?>[null, 'bad', <dynamic>[]]) {
        final PreferenceQuestionnaire questionnaire =
            PreferenceQuestionnaire.fromJson(<String, dynamic>{
              'nodeId': 17,
              'steps': rawSteps,
            });
        expect(questionnaire.steps, isEmpty);
      }
    },
  );

  test(
    'submit response distinguishes tiebreak from server completion progress',
    () {
      final PreferenceSubmission tiebreak = PreferenceSubmission.fromJson(
        <String, dynamic>{
          'needsTiebreak': true,
          'tiebreak': <String, dynamic>{
            'key': 'final',
            'type': 'single',
            'title': '最后一票',
            'options': <dynamic>[
              <String, dynamic>{'key': 'A', 'text': '收纳'},
              <String, dynamic>{'key': 'B', 'text': '通透'},
            ],
          },
          'choices': <String, dynamic>{'space': 'A'},
        },
      );
      expect(tiebreak.needsTiebreak, isTrue);
      expect(tiebreak.tiebreak?.key, 'final');
      expect(tiebreak.progress, isNull);

      final PreferenceSubmission completed = PreferenceSubmission.fromJson(
        <String, dynamic>{
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
            'total': 2,
            'completed': false,
            'newBadges': <dynamic>[],
            'routeState': <String, dynamic>{
              'routeMode': 'BRANCH_GRAPH',
              'sessionId': 91,
              'status': 'ACTIVE',
              'currentNodeId': 18,
              'recommendedNodeId': 18,
              'version': 3,
              'nodeStates': <String, dynamic>{
                '17': 'COMPLETED',
                '18': 'PLAYABLE',
              },
              'decisionLog': <dynamic>[],
            },
          },
        },
      );
      expect(completed.needsTiebreak, isFalse);
      expect(completed.evaluation?.title, '小空间先减负');
      expect(completed.progress?.nodeId, 17);
      expect(completed.progress?.routeState?.version, 3);
    },
  );

  test('submit response exposes only server-authored pending tag consent', () {
    final PreferenceSubmission submission = PreferenceSubmission.fromJson(
      <String, dynamic>{
        'evaluation': <String, dynamic>{
          'resultCode': 'compact',
          'title': '小空间先减负',
          'body': '因为你选择了紧凑',
        },
        'pendingTag': <String, dynamic>{
          'id': 23,
          'tagCode': 'space_constraints',
          'tagValue': 'compact',
          'status': 0,
        },
        'tagDisclosure': <String, dynamic>{
          'purpose': '用于后续站点复用已确认的居住条件',
          'recipientLabel': '本主题后续站点',
          'revocable': true,
        },
        'availableTagValues': <dynamic>['compact', '', 'open'],
      },
    );

    expect(submission.pendingTag?.id, 23);
    expect(submission.pendingTag?.status, 0);
    expect(submission.tagDisclosure?.purpose, '用于后续站点复用已确认的居住条件');
    expect(submission.tagDisclosure?.recipientLabel, '本主题后续站点');
    expect(submission.tagDisclosure?.revocable, isTrue);
    expect(submission.availableTagValues, <String>['compact', 'open']);
  });
}
