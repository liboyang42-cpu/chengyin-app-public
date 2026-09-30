// 活动发布的合作者。
//
// ⚠️⚠️ 后端字段名是 **collaborators**(复数、不带 Ids)——
//   专业发布那条接口叫 collaboratorIds,**两个接口不是一个名字**。
//   照抄另一条的名字,后端收不到,合作者静默丢失。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity_publish.dart';
import '../../support/source_text.dart';

void main() {
  test('★★ 字段名是 collaborators,不是 collaboratorIds', () {
    final Map<String, dynamic> j = const ActivityPublishForm(
      name: 'x',
      collaborators: <int>[7, 9],
    ).toJson();
    expect(j.containsKey('collaborators'), isTrue);
    expect(j.containsKey('collaboratorIds'), isFalse,
        reason: '那是专业发布那条接口的名字,这条收不到');
    expect(j['collaborators'], <int>[7, 9]);
  });

  test('★ 空列表也要发 —— 不发的话改不回「只有我」', () {
    final Map<String, dynamic> j =
        const ActivityPublishForm(name: 'x').toJson();
    expect(j.containsKey('collaborators'), isTrue);
    expect(j['collaborators'], isEmpty);
  });

  test('页面有添加与移除两个动作', () {
    final String src = codeOf('lib/feature/publish/publish_activity_page.dart');
    expect(src.contains("Key('activity-add-collaborator')"), isTrue);
    expect(src.contains("Key('collaborator-"), isTrue, reason: '每一条要能移除');
  });

  test('★ 名字随选随记,不为一行字再打一次后端', () {
    final String src = codeOf('lib/feature/publish/publish_activity_page.dart');
    expect(src.contains('_collaboratorNames'), isTrue);
    // 拿不到名字时用 #id 兜,不显示空行。
    expect(src.contains("'用户 #"), isTrue);
  });
}
