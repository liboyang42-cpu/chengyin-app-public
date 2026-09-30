// 参与商家数:拿不到时**整栏不显示**,不兜 0。
//
// ★★ 「还没有商家承接」和「这个数没算出来」是两回事。
//   对一条正在招商的路线,写死 0 会**劝退本来想报名的商家** ——
//   他看到「0 家」会以为没人看好这条路线,而其实只是这个字段没返回。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/topic.dart';

TopicDetail _d(Map<String, dynamic> extra) => TopicDetail.fromJson(
      <String, dynamic>{'id': 1, 'name': '静安夜行', ...extra},
    );

void main() {
  test('后端给了就解析出来', () {
    expect(_d(<String, dynamic>{'registrationMerchantCount': 4}).merchantCount, 4);
  });

  test('★★ 后端没给 ⇒ null(整栏不显示),不是 0', () {
    expect(_d(const <String, dynamic>{}).merchantCount, isNull);
  });

  test('★ 真的是 0 就显示 0 —— 和「没给」区分开', () {
    expect(_d(<String, dynamic>{'registrationMerchantCount': 0}).merchantCount, 0);
  });

  test('非数字的脏值当成没给,不崩', () {
    expect(_d(<String, dynamic>{'registrationMerchantCount': 'abc'}).merchantCount,
        isNull);
  });
}
