// 客户端兜底过滤器 matchesDatePriceFilter —— 口径 1:1 对齐小程序
// utils/discover-search.js 的 matchesFilters:后端 activity/topic list 不消费
// 日期/价格,取回后前端过滤。量程 0-1000、min>0 或 max<1000 才启用价格、
// 无日期/无票价放行、只对主题/活动生效。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/search/search_controller.dart';

void main() {
  group('matchesDatePriceFilter', () {
    test('俱乐部/商家类型原样放行(后端不收、列表无票价)', () {
      expect(
        matchesDatePriceFilter(
          appliesToType: false,
          rowDate: '2020-01-01',
          rowPrice: 9999,
          startBound: '2026-08-23',
          endBound: '2026-08-24',
          minPrice: 50,
          maxPrice: 300,
        ),
        isTrue,
      );
    });

    test('开始日期落区间内命中、越界剔除', () {
      bool hit(String? rowDate) => matchesDatePriceFilter(
        appliesToType: true,
        rowDate: rowDate,
        rowPrice: null,
        startBound: '2026-08-23',
        endBound: '2026-08-24',
      );
      expect(hit('2026-08-23 09:00:00'), isTrue, reason: '带时间前缀取 ymd');
      expect(hit('2026-08-24'), isTrue);
      expect(hit('2026-08-22'), isFalse, reason: '早于下界');
      expect(hit('2026-08-25'), isFalse, reason: '晚于上界');
      expect(hit(null), isTrue, reason: '无日期不可判 → 放行');
    });

    test('价格区间:min>0 或 max<1000 才启用,越界剔除', () {
      bool hit(double? price, {double? min, double? max}) =>
          matchesDatePriceFilter(
            appliesToType: true,
            rowDate: null,
            rowPrice: price,
            minPrice: min,
            maxPrice: max,
          );
      // 默认量程(0 / 1000)→ 不启用价格过滤
      expect(hit(5000, min: 0, max: 1000), isTrue);
      expect(hit(5000), isTrue, reason: '未传边界不启用');
      // min 生效
      expect(hit(30, min: 50), isFalse);
      expect(hit(80, min: 50), isTrue);
      // max 生效
      expect(hit(500, max: 300), isFalse);
      expect(hit(200, max: 300), isTrue);
      // 无票价放行
      expect(hit(null, min: 50, max: 300), isTrue);
    });

    test('日期 + 价格同时约束:两者都命中才留', () {
      bool hit(String? rowDate, double? price) => matchesDatePriceFilter(
        appliesToType: true,
        rowDate: rowDate,
        rowPrice: price,
        startBound: '2026-08-23',
        endBound: '2026-08-24',
        minPrice: 50,
        maxPrice: 300,
      );
      expect(hit('2026-08-23', 100), isTrue);
      expect(hit('2026-08-23', 999), isFalse, reason: '日期对、价超上界');
      expect(hit('2026-09-01', 100), isFalse, reason: '价对、日期越界');
    });
  });
}
