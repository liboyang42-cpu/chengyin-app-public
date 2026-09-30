// 发布能力快照(`/api/publish/home`)。
//
// ★★★ 三条判据,每条写反都会让人卡住:
//   ① **身份缺省 fail-closed**:认不出的 role 一律按 player。
//      小程序组件注释原话:「role 缺省按 player(**fail-closed 锁**)」。
//   ② **null ≠ 0**:maxThemes / themesRemaining 为 null 是「不限或未知」,
//      兜 0 会把「不限」显示成「一个都不能发」。
//   ③ **「拿不到配额」≠「配额满」**:只有明确拿到 0 才算满 ——
//      拿不到就锁入口,等于用一次网络抖动废掉发布功能。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/my_project_api.dart';
import 'package:chengyin_app/feature/publish/publish_capability.dart';

class _FakeApi implements MyProjectApi {
  _FakeApi({this.data, this.err});
  final Map<String, dynamic>? data;
  final Object? err;

  @override
  Future<Map<String, dynamic>> publishHome() async {
    if (err != null) throw err!;
    return data ?? <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<PublishCapability> _read(_FakeApi api) {
  final ProviderContainer c = ProviderContainer(
    overrides: <dynamic>[myProjectApiProvider.overrideWithValue(api)].cast(),
  );
  addTearDown(c.dispose);
  return c.read(publishCapabilityProvider.future);
}

PublishCapability _cap(Map<String, dynamic> j) => PublishCapability.fromJson(j);

void main() {
  test('主题创建权限只在后端明确 false 时关闭', () {
    final PublishCapability missing = PublishCapability.fromJson(
      <String, dynamic>{},
    );
    expect(missing.canSimplePublish, isTrue);
    expect(missing.canProPublish, isTrue);

    final PublishCapability denied = PublishCapability.fromJson(
      <String, dynamic>{
        'permission': <String, dynamic>{
          'canSimplePublish': false,
          'canProPublish': false,
        },
      },
    );
    expect(denied.canSimplePublish, isFalse);
    expect(denied.canProPublish, isFalse);
  });

  test('商家卡解锁只认 role=merchant，不依赖冗余 isMerchant 字段', () {
    final PublishCapability merchant = PublishCapability.fromJson(
      <String, dynamic>{'role': 'merchant'},
    );
    expect(merchant.isMerchant, isTrue);
  });

  test('★★★ ① 身份缺省 fail-closed:认不出一律按 player', () {
    expect(_cap(<String, dynamic>{'role': 'club'}).isClubLeader, isTrue);
    for (final Object? r in <Object?>[null, '', 'admin', 'CLUB', 123]) {
      expect(
        _cap(<String, dynamic>{if (r != null) 'role': r}).role,
        'player',
        reason: '「$r」被当成了别的身份 —— 缺省必须是最小权限',
      );
    }
  });

  test('★★★ ② null ≠ 0:不限 vs 一个都不能发', () {
    final PublishCapability unlimited = _cap(<String, dynamic>{
      'quota': <String, dynamic>{'themesOnline': 3},
    });
    expect(unlimited.maxThemes, isNull);
    expect(unlimited.themesRemaining, isNull);
    expect(
      unlimited.quotaExhausted,
      isFalse,
      reason: '拿不到剩余数被当成 0 = 把不限显示成一个都不能发',
    );
    expect(unlimited.quotaText, isNull, reason: '拿不到就不说,别编一个数');
  });

  test('★★★ ③ 只有明确拿到 0 才算满', () {
    final PublishCapability full = _cap(<String, dynamic>{
      'quota': <String, dynamic>{
        'maxThemes': 3,
        'themesOnline': 3,
        'themesRemaining': 0,
      },
    });
    expect(full.quotaExhausted, isTrue);
    // 说清怎么才能再发,不是只说不行。
    expect(full.quotaText, contains('下架一个'));

    final PublishCapability some = _cap(<String, dynamic>{
      'quota': <String, dynamic>{'themesRemaining': 2},
    });
    expect(some.quotaExhausted, isFalse);
    expect(some.quotaText, '还能发 2 个');
  });

  test('★★ 接口挂了落最小权限,不抛错让整页变错误页', () async {
    final PublishCapability c = await _read(_FakeApi(err: Exception('超时')));
    expect(c.role, 'player');
    expect(c.quotaExhausted, isFalse, reason: '拿不到就锁入口 = 用一次网络抖动废掉发布功能');
  });

  test('★ 正常返回照实解析', () async {
    final PublishCapability c = await _read(
      _FakeApi(
        data: <String, dynamic>{
          'role': 'club',
          'isMerchant': true,
          'quota': <String, dynamic>{
            'maxThemes': 5,
            'themesOnline': 2,
            'themesRemaining': 3,
          },
        },
      ),
    );
    expect(c.isClubLeader, isTrue);
    expect(c.isMerchant, isTrue);
    expect(c.themesRemaining, 3);
  });
}
