// 搜索历史本地存储:去重置顶、上限 10 条、一键清空。
// 对齐小程序 search2/index.js 的 loadHistory/saveHistory/onClearHistory。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/search/search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  SearchHistoryStore store() => SearchHistoryStore(const FlutterSecureStorage());

  test('首次 push 只有一词', () async {
    expect(await store().push('读书'), <String>['读书']);
  });

  test('新词置顶,旧词保留顺序', () async {
    final s = store();
    await s.push('读书');
    expect(await s.push('电影'), <String>['电影', '读书']);
  });

  test('重复词提到最前,不产生副本', () async {
    final s = store();
    await s.push('读书');
    await s.push('电影');
    expect(await s.push('读书'), <String>['读书', '电影']);
  });

  test('超过 10 条只留最近 10 条', () async {
    final s = store();
    for (var i = 1; i <= 12; i++) {
      await s.push('词$i');
    }
    final list = await s.read();
    expect(list.length, 10, reason: '上限 10 条');
    expect(list.first, '词12');
    expect(list.last, '词3');
  });

  test('clear 后读回空', () async {
    final s = store();
    await s.push('读书');
    await s.clear();
    expect(await s.read(), isEmpty);
  });

  test('存储损坏时读回空数组,不抛异常', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'search2_history': 'not-json',
    });
    expect(await store().read(), isEmpty);
  });
}