// 个性化推荐的解析。
//
// ★★ 与首页那个「推荐主题」不是一回事:
//   前者 `/api/recommendation/list`(按人算),后者 `topic/list?recommend=true`
//   (运营配的固定推荐位)。我一度把后者当成前者已接通,判成"这条不用做"。
//
// ⚠️ 后端返回形状**三种都可能**(裸数组 / rows / list),
//   id 与名字**各有三个候选键**。少认一个就会渲出一排「推荐路线」。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/feed/recommendation.dart';

void main() {
  test('★★ 三种返回形状都收', () {
    final List<Object> shapes = <Object>[
      <dynamic>[<String, dynamic>{'id': 1, 'name': 'A'}],
      <String, dynamic>{
        'rows': <dynamic>[<String, dynamic>{'id': 1, 'name': 'A'}]
      },
      <String, dynamic>{
        'list': <dynamic>[<String, dynamic>{'id': 1, 'name': 'A'}]
      },
    ];
    for (final Object s in shapes) {
      final List<RecommendedTopic> r = RecommendedTopic.parseAll(s);
      expect(r.length, 1, reason: '这种形状没收到:$s');
      expect(r.single.name, 'A');
    }
    expect(RecommendedTopic.parseAll(null), isEmpty);
    expect(RecommendedTopic.parseAll(<String, dynamic>{}), isEmpty);
  });

  test('★★ id 三个候选键都认', () {
    for (final String k in <String>['id', 'topicId', 'candidateId']) {
      final RecommendedTopic? t =
          RecommendedTopic.tryParse(<String, dynamic>{k: 7, 'name': 'X'});
      expect(t?.id, 7, reason: '「$k」没认出来');
    }
    // 字符串数字也认(后端偶尔发字符串 id)。
    expect(RecommendedTopic.tryParse(<String, dynamic>{'id': '7'})?.id, 7);
  });

  test('★★ 名字三个候选键都认', () {
    for (final String k in <String>['name', 'title', 'topicName']) {
      final RecommendedTopic? t =
          RecommendedTopic.tryParse(<String, dynamic>{'id': 1, k: '静安夜行'});
      expect(t?.name, '静安夜行', reason: '「$k」没认出来 —— 会渲成「推荐路线」');
    }
  });

  test('★★★ 认不出 id 的条目丢掉 —— 不留点不进去的卡片', () {
    expect(RecommendedTopic.tryParse(<String, dynamic>{'name': 'X'}), isNull);
    expect(RecommendedTopic.tryParse(<String, dynamic>{'id': 0}), isNull);
    expect(RecommendedTopic.tryParse(<String, dynamic>{'id': 'abc'}), isNull);
    expect(RecommendedTopic.tryParse('不是对象'), isNull);
    // 整批里混着坏条目时,好的照留。
    final List<RecommendedTopic> r = RecommendedTopic.parseAll(<dynamic>[
      <String, dynamic>{'id': 1, 'name': 'A'},
      <String, dynamic>{'name': '没有 id'},
      'garbage',
    ]);
    expect(r.length, 1);
  });

  test('★ 有 id 没名字才用兜底 —— 那时它至少点得进去', () {
    expect(RecommendedTopic.tryParse(<String, dynamic>{'id': 5})?.name,
        '推荐路线');
  });
}
