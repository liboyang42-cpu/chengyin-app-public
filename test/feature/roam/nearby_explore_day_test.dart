// 附近的探店日推荐。
//
// ★★ 后端**没有合适的时返回 `success(null)`** —— 那是**正常态**(附近没活动),
//   不是错误。整条链路一律「没有就没有」,不弹错误、不占位。
//
// ★★ activityId 必须是**正整数**才算数(小程序同判据)。
//   拿 0 或 null 去跳转,用户会落到一个不存在的活动页。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/roam/nearby_explore_day.dart';

void main() {
  test('★★★ activityId 不是正整数就丢掉', () {
    for (final Object? id in <Object?>[null, 0, -1, 'abc', '']) {
      expect(
        NearbyExploreDay.tryParse(<String, dynamic>{
          if (id != null) 'activityId': id,
          'title': '静安探店日',
        }),
        isNull,
        reason: '「$id」被放行了 —— 点进去是个不存在的活动页',
      );
    }
    expect(
      NearbyExploreDay.tryParse(
          <String, dynamic>{'activityId': 9, 'title': '静安探店日'})?.activityId,
      9,
    );
  });

  test('★★ 没名字的候选也丢掉 —— 点进去也不知道是什么', () {
    expect(
      NearbyExploreDay.tryParse(
          <String, dynamic>{'activityId': 9, 'title': '  '}),
      isNull,
    );
  });

  test('★★★ 距离拿不到就不说 —— 兜 0 会变成「就在脚下」', () {
    final NearbyExploreDay? none = NearbyExploreDay.tryParse(
        <String, dynamic>{'activityId': 9, 'title': 'X'});
    expect(none!.distanceM, isNull);
    expect(none.distanceText, isNull,
        reason: '「距离 0 米」是"就在脚下",不是"不知道"');

    expect(
      NearbyExploreDay.tryParse(<String, dynamic>{
        'activityId': 9,
        'title': 'X',
        'distanceM': 0,
      })!.distanceText,
      '0 米',
      reason: '真的是 0 就照实说',
    );
  });

  test('★ 距离单位:1 公里以内用米', () {
    String? d(int m) => NearbyExploreDay.tryParse(<String, dynamic>{
          'activityId': 9,
          'title': 'X',
          'distanceM': m,
        })!.distanceText;
    expect(d(320), '320 米');
    expect(d(1200), '1.2 公里');
  });

  test('★ null 返回体(附近没活动)是正常态', () {
    expect(NearbyExploreDay.tryParse(null), isNull);
  });
}
