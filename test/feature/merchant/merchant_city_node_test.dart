import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_city_node.dart';

void main() {
  group('★ 配额', () {
    test('用满 → 认领入口该禁用', () {
      const h = CityNodeHome(used: 3, max: 3);
      expect(h.quotaExhausted, isTrue, reason: '不禁用的话商家挑完地点才被后端拒,白走一遍');
    });
    test('没用满 → 可认领', () {
      expect(const CityNodeHome(used: 1, max: 3).quotaExhausted, isFalse);
    });
    test('超额也算用满(数据异常时别放行)', () {
      expect(const CityNodeHome(used: 5, max: 3).quotaExhausted, isTrue);
    });
    test('★ max 为 0 = 后端没下发上限,不是"一个都不能建"', () {
      const h = CityNodeHome(used: 0, max: 0);
      expect(h.quotaExhausted, isFalse, reason: '没下发上限不该把人挡住');
      expect(h.quotaText, isNull, reason: '显示「0/0」会让商家以为一个都不能建');
    });
    test('有上限才显示配额', () {
      expect(const CityNodeHome(used: 2, max: 5).quotaText, '2 / 5');
    });
  });

  group('★ 驳回必须说原因', () {
    CityNodeApplication a(int? s, [String? reason]) =>
        CityNodeApplication.fromJson(<String, dynamic>{
          'poiName': 'X',
          'status': s,
          'rejectReason': reason,
        });
    test('驳回带原因', () {
      expect(a(2, '地址与营业执照不符').statusText, '已驳回:地址与营业执照不符');
    });
    test('驳回没给原因时兜底,不显示空冒号', () {
      expect(a(2).statusText, '已驳回');
      expect(a(2, '').statusText, '已驳回');
    });
    test('其余两态', () {
      expect(a(1).statusText, '已通过');
      expect(a(0).statusText, '审核中');
      expect(a(null).statusText, '审核中');
    });
  });

  group('解析健壮性', () {
    test('小程序真源字段 poiId / auditStatus / auditReason 不丢', () {
      expect(
        CityNode.fromJson(<String, dynamic>{'poiId': 73, 'name': 'A'}).id,
        73,
      );
      final CityNodeApplication application = CityNodeApplication.fromJson(
        <String, dynamic>{
          'id': 9,
          'name': '据点申请',
          'auditStatus': 2,
          'auditReason': '地址与执照不符',
        },
      );
      expect(application.poiName, '据点申请');
      expect(application.statusText, '已驳回:地址与执照不符');
    });

    test('缺名字兜底,不渲染空白行', () {
      expect(CityNode.fromJson(<String, dynamic>{}).name, '未命名据点');
      expect(
        CityNodeApplication.fromJson(<String, dynamic>{}).poiName,
        '未命名地点',
      );
    });
    test('申请的名字两种命名都收', () {
      expect(
        CityNodeApplication.fromJson(<String, dynamic>{'name': 'A'}).poiName,
        'A',
      );
      expect(
        CityNodeApplication.fromJson(<String, dynamic>{'poiName': 'B'}).poiName,
        'B',
      );
    });
    test('列表字段缺失时给空表,不抛', () {
      final h = CityNodeHome.fromJson(<String, dynamic>{});
      expect(h.nodes, isEmpty);
      expect(h.applications, isEmpty);
    });
  });
}
