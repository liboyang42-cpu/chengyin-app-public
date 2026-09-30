// 探店日完局面的四条判据。
//
// 全部抄自小程序 components/cy/scene-member-order-detail 的同一处逻辑,
// 每一条如果自己从头写都容易写反:
//   ① amount 为 null ≠ 0 —— 后端无流水时不下发这一项,兜成 0 会在屏幕上
//      造出「+0 积分」这个不存在的事实
//   ② requiredChapterCount 为 0 时不显示进度 ——「已集齐 0/0」不是事实
//   ③ 未到账要分「还没走完」和「走完了在发放中」——合并成"暂无奖励"
//      会让已完成的用户以为白跑了
//   ④ 没有 clubLeaderMemberId 就不给关注钮 —— 关注接口要的是 member id

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/explore_completion.dart';

void main() {
  test('★★★ amount 为 null 不许兜成 0', () {
    final ExploreCompletion c = ExploreCompletion.fromJson(<String, dynamic>{
      'completed': true,
      'awards': <String, dynamic>{
        'credited': true,
        'items': <dynamic>[
          <String, dynamic>{'kind': 'BADGE', 'title': '静安夜行徽章'},
          <String, dynamic>{'kind': 'POINTS', 'title': '积分', 'amount': 120},
        ],
      },
    });
    expect(c.awards[0].amountText, isNull, reason: '一枚勋章没有"数量",显示 +0 是编出来的事实');
    expect(c.awards[1].amountText, '+120');
  });

  test('★★ credited=true 但一条奖励都没有 ⇒ 仍算未到账', () {
    final ExploreCompletion c = ExploreCompletion.fromJson(<String, dynamic>{
      'completed': true,
      'awards': <String, dynamic>{'credited': true, 'items': <dynamic>[]},
    });
    expect(c.awardsCredited, isFalse, reason: '屏幕上没东西可显示,不能说"已到账"');
    expect(c.awardsEmptyText, contains('发放中'));
  });

  test('★★ 未到账要分两种说法', () {
    final ExploreCompletion notDone = ExploreCompletion.fromJson(
      <String, dynamic>{'completed': false, 'requiredChapterCount': 4},
    );
    expect(notDone.awardsEmptyText, '走完全部 4 家店后发放');

    final ExploreCompletion done = ExploreCompletion.fromJson(<String, dynamic>{
      'completed': true,
      'requiredChapterCount': 4,
    });
    expect(
      done.awardsEmptyText,
      contains('发放中'),
      reason: '走完了却被告知"走完后发放",用户会以为白跑了',
    );
  });

  test('★★ requiredChapterCount=0 时不显示「已集齐 0/0」', () {
    expect(
      ExploreCompletion.fromJson(<String, dynamic>{}).stampProgressText,
      isNull,
    );
    expect(
      ExploreCompletion.fromJson(<String, dynamic>{
        'requiredChapterCount': 4,
        'redeemedChapterCount': 2,
      }).stampProgressText,
      '已集齐 2/4',
    );
  });

  test('★★ 没有 clubLeaderMemberId 就不给关注钮', () {
    final ExploreCompletion c = ExploreCompletion.fromJson(<String, dynamic>{
      'revisit': <String, dynamic>{'clubId': 7, 'clubName': '夜骑俱乐部'},
    });
    expect(c.revisit, isNotNull);
    expect(c.revisit!.canFollow, isFalse, reason: '关注接口要 member id,没有它点下去必然失败');

    final ExploreCompletion c2 = ExploreCompletion.fromJson(<String, dynamic>{
      'revisit': <String, dynamic>{'clubId': 7, 'clubLeaderMemberId': 42},
    });
    expect(c2.revisit!.canFollow, isTrue);
    expect(c2.revisit!.clubName, '主办俱乐部', reason: '没给名字要兜底,不留空行');
  });

  test('★ 没有主办俱乐部就没有回访块', () {
    expect(ExploreCompletion.fromJson(<String, dynamic>{}).revisit, isNull);
    expect(
      ExploreCompletion.fromJson(<String, dynamic>{
        'revisit': <String, dynamic>{'clubName': '有名字但没 id'},
      }).revisit,
      isNull,
      reason: 'clubId 才是这块存在与否的开关',
    );
  });

  test('★ canJoin=!joined(真源):入过团就不再给加入钮', () {
    final ExploreRevisit r = ExploreCompletion.fromJson(<String, dynamic>{
      'revisit': <String, dynamic>{'clubId': 7},
    }).revisit!;
    expect(r.canJoin, isTrue);
    final ExploreRevisit joined = ExploreCompletion.fromJson(<String, dynamic>{
      'revisit': <String, dynamic>{'clubId': 7, 'joined': true},
    }).revisit!;
    expect(joined.canJoin, isFalse);
  });

  test('★ nextEditionText 逐字真源:名字 · MM-DD 开场;没下期占行说「下一期开售后会在这里出现」', () {
    ExploreRevisit revisitWith(Map<String, dynamic> next) =>
        ExploreCompletion.fromJson(<String, dynamic>{
          'revisit': <String, dynamic>{'clubId': 7, 'nextEdition': next},
        }).revisit!;
    expect(
      revisitWith(<String, dynamic>{
        'topicId': 88,
        'name': '静安探店日 · 第二期',
        'startDate': '2026-10-01 14:00:00',
      }).nextEditionText,
      '静安探店日 · 第二期 · 10-01 开场',
    );
    // 没给名字兜「下一期」(slice 5..10 同 JS:短日期串不硬切)。
    expect(
      revisitWith(<String, dynamic>{'topicId': 88}).nextEditionText,
      '下一期 ·  开场',
      reason: '真源就是 name 兜底 + 空日期,不藏这行',
    );
    // topicId 缺失 ⇒ hasNextEdition=false(JS 的 !!next.topicId 同判)。
    final ExploreRevisit noNext = revisitWith(<String, dynamic>{
      'name': '有名字但没 id',
    });
    expect(noNext.hasNextEdition, isFalse);
    expect(noNext.nextEditionText, '下一期开售后会在这里出现');
    expect(
      ExploreCompletion.fromJson(<String, dynamic>{
        'revisit': <String, dynamic>{'clubId': 7},
      }).revisit!.nextEditionText,
      '下一期开售后会在这里出现',
    );
  });

  test('★ 章节没给标题时用章节号兜底', () {
    final ExploreCompletion c = ExploreCompletion.fromJson(<String, dynamic>{
      'stamps': <dynamic>[
        <String, dynamic>{'chapterId': 3, 'collected': true},
      ],
    });
    expect(c.stamps.single.title, '章节 3');
    expect(c.stamps.single.collected, isTrue);
  });
}
