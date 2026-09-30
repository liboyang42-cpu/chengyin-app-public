// 字典驱动的选择器:**接口挂了也不能变成空选择器**。
//
// ★★★ 小程序在这条上栽过,它自己的注释原话:
//   「之前只回填了 listName(纯标签数组),**漏了 listName+'Data'**,
//    导致玩法难度接口失败时选择器 options 空数组、**点开没有可选项**」。
//   ⇒ 兜底必须是**能用的完整选项**,不是一个空壳。
//
// ⚠️ 后端注释:先读缓存、缓存没有再查库,**两条路都可能返回空列表** ——
//   那是「这个字典没有配项」不是错误。但空列表同样不能让选择器变空。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/feature/template/template_dict.dart';

class _FakeApi implements RegistrationApi {
  _FakeApi({this.rows, this.err});
  final List<Map<String, dynamic>>? rows;
  final Object? err;

  @override
  Future<List<Map<String, dynamic>>> dict(String dictType) async {
    if (err != null) throw err!;
    return rows ?? <Map<String, dynamic>>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<List<DictOption>> _read(_FakeApi api) async {
  final ProviderContainer c = ProviderContainer(overrides: <dynamic>[
    registrationApiProvider.overrideWithValue(api),
  ].cast());
  addTearDown(c.dispose);
  return c.read(dictProvider('app_template_difficulty').future);
}

void main() {
  test('★ 后端有配项就用后端的', () async {
    final List<DictOption> o = await _read(_FakeApi(rows: <Map<String, dynamic>>[
      <String, dynamic>{'dictValue': 'a', 'dictLabel': '轻松'},
      <String, dynamic>{'dictValue': 'b', 'dictLabel': '硬核'},
    ]));
    expect(o.map((DictOption e) => e.label), <String>['轻松', '硬核']);
  });

  test('★★★ 接口抛异常 ⇒ 落兜底,**不是空列表**', () async {
    final List<DictOption> o = await _read(_FakeApi(err: Exception('网络超时')));
    expect(o, isNotEmpty,
        reason: '空列表 = 点开没有可选项,小程序就是这么栽的');
    expect(o.map((DictOption e) => e.label), containsAll(<String>['简易', '一般', '困难']));
  });

  test('★★★ 后端返空列表(没配项)⇒ 同样落兜底', () async {
    final List<DictOption> o = await _read(_FakeApi(rows: <Map<String, dynamic>>[]));
    expect(o, isNotEmpty,
        reason: '「没配项」不是错误,但也不能让用户面对一个空选择器');
  });

  test('★★ 标签是空白的项要滤掉 —— 渲出来是个点不出所以然的空条目', () async {
    final List<DictOption> o = await _read(_FakeApi(rows: <Map<String, dynamic>>[
      <String, dynamic>{'dictValue': 'a', 'dictLabel': '轻松'},
      <String, dynamic>{'dictValue': 'b', 'dictLabel': '   '},
    ]));
    expect(o.length, 1);
  });

  test('★ 兜底选项本身要是有意义的三档,不是占位串', () {
    expect(kDictFallback['app_template_difficulty'], <String>['简易', '一般', '困难']);
  });
}
