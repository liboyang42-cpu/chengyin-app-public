import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/feature/roam/city_node_voucher_logic.dart';
import 'package:chengyin_app/feature/roam/roam_poi_interaction_logic.dart';
import 'package:chengyin_app/data/models/roam_merchant_info.dart';

void main() {
  group('据点核销码页状态机', () {
    test('缺参 → missing,而且不给重试这条路', () {
      expect(voucherInitialPhase(poiId: null), CityNodeVoucherPhase.missing);
      expect(voucherInitialPhase(poiId: 0), CityNodeVoucherPhase.missing);
      expect(voucherInitialPhase(poiId: -3), CityNodeVoucherPhase.missing);
    });
    test('有参 → loading', () {
      expect(voucherInitialPhase(poiId: 7), CityNodeVoucherPhase.loading);
    });
    test('★ 判据是 code 在不在,不是 qrcodeUrl', () {
      // 后端二维码生成失败时仍带 code 返回 —— 码文本可用,不能报成出码失败。
      expect(
        voucherPhaseFromIssue(const CityNodeVoucher(code: 'X', qrcodeUrl: '')),
        CityNodeVoucherPhase.ready,
      );
      expect(
        voucherPhaseFromIssue(
          const CityNodeVoucher(code: '', qrcodeUrl: 'http'),
        ),
        CityNodeVoucherPhase.error,
      );
    });
    test('倒计时到 0 返回 null(触发自动重出码),不渲染负倒计时', () {
      expect(nextVoucherCountdown(5), 4);
      expect(nextVoucherCountdown(1), isNull);
      expect(nextVoucherCountdown(0), isNull);
    });
    test('出码失败文案:网络与业务分开说', () {
      expect(voucherErrorMessage(Exception('x')), contains('暂时无法生成核销码'));
    });
  });

  group('据点互动逻辑', () {
    test('验证方式分派:空/5/其它都归 GPS,客户端不造第六档', () {
      expect(interactionKindFor(null), RoamInteractionKind.gps);
      expect(interactionKindFor(0), RoamInteractionKind.gps);
      expect(interactionKindFor(5), RoamInteractionKind.gps);
      expect(interactionKindFor(9), RoamInteractionKind.gps);
      expect(interactionKindFor(1), RoamInteractionKind.text);
      expect(interactionKindFor(2), RoamInteractionKind.photo);
      expect(interactionKindFor(3), RoamInteractionKind.choice);
      expect(interactionKindFor(4), RoamInteractionKind.scan);
    });

    test('按钮文案三态', () {
      expect(interactButtonLabel(completed: true, completing: false), '已完成');
      expect(interactButtonLabel(completed: false, completing: true), '处理中…');
      expect(interactButtonLabel(completed: false, completing: false), '开始互动');
      // 已完成优先于处理中(不会出现,但要定义好优先级)。
      expect(interactButtonLabel(completed: true, completing: true), '已完成');
    });

    test('meta 行:有券才带「完成领券」', () {
      expect(nodeMetaText(_node(vm: 5, coupon: null)), 'GPS 到达');
      expect(nodeMetaText(_node(vm: 1, coupon: 9)), '文字作答 · 完成领券');
    });

    test('定位异常分流:权限/服务 → 去设置;取消 → 静默', () {
      expect(isLocationPermissionFailure('Permission denied'), isTrue);
      expect(
        isLocationPermissionFailure('Location service is disabled'),
        isTrue,
      );
      expect(isLocationPermissionFailure('Timed out'), isFalse);
      expect(isLocationCancel('User cancelled'), isTrue);
      expect(isLocationCancel('Permission denied'), isFalse);
    });

    test('canInteract:下线/已完成/缺坐标都禁用,别点下去撞后端', () {
      expect(_node(status: 1).canInteract, isTrue);
      expect(_node(status: 0).canInteract, isFalse);
      expect(_node(status: null).canInteract, isFalse);
      expect(_node(status: 1, completed: true).canInteract, isFalse);
      expect(_node(status: 1, lat: null).canInteract, isFalse);
      expect(_node(status: 1, lng: null).canInteract, isFalse);
    });

    test('选项问答:空选项/坏选项不算数,全空时互动该禁用', () {
      expect(
        _node(vm: 3, a: 'A项', b: '', c: null, d: ' ').choices,
        hasLength(1),
      );
      expect(_node(vm: 3, a: null, b: '', c: ' ', d: null).choices, isEmpty);
      expect(_node(vm: 3).choicesNotConfigured, isTrue);
      expect(_node(vm: 3, a: '有').choicesNotConfigured, isFalse);
      // 非问答玩法永远不算「没配好」。
      expect(_node(vm: 1).choicesNotConfigured, isFalse);
    });
  });

  group('商家公开信息解析', () {
    test('gallery 是 JSON 字符串时解析', () {
      expect(RoamMerchantInfo.parseStringList('["a","b"]'), <String>['a', 'b']);
    });
    test('gallery 是数组时直通,坏 JSON 空数组兜底', () {
      expect(RoamMerchantInfo.parseStringList(<dynamic>['a', 'b']), <String>[
        'a',
        'b',
      ]);
      expect(RoamMerchantInfo.parseStringList('{bad'), isEmpty);
      expect(RoamMerchantInfo.parseStringList(null), isEmpty);
      expect(RoamMerchantInfo.parseStringList(123), isEmpty);
    });
    test('收费方式:只有 1 是收费承接', () {
      RoamMerchantInfo f(int? c) =>
          RoamMerchantInfo.fromJson(<String, dynamic>{'chargeType': c});
      expect(f(1).chargeText, '收费承接');
      expect(f(0).chargeText, '免费承接');
      expect(f(null).chargeText, '免费承接');
    });
    test('合作方档案字段与坐标按真实值解析，null 不兜成 0', () {
      final RoamMerchantInfo full = RoamMerchantInfo.fromJson(<String, dynamic>{
        'capacity': 36,
        'suitActivityTypes': 'CityWalk · 咖啡路线',
        'availableTime': '周二至周日 10:00-18:00',
        'demand': '希望获得稳定客流',
        'businessTime': '09:30-21:00',
        'latitude': '31.2101',
        'longitude': 121.4321,
      });
      expect(full.capacity, 36);
      expect(full.suitActivityTypes, 'CityWalk · 咖啡路线');
      expect(full.availableTime, '周二至周日 10:00-18:00');
      expect(full.demand, '希望获得稳定客流');
      expect(full.businessTime, '09:30-21:00');
      expect(full.latitude, 31.2101);
      expect(full.longitude, 121.4321);

      final RoamMerchantInfo unknown = RoamMerchantInfo.fromJson(
        <String, dynamic>{
          'capacity': null,
          'latitude': '',
          'longitude': 'not-a-coordinate',
        },
      );
      expect(unknown.capacity, isNull);
      expect(unknown.latitude, isNull);
      expect(unknown.longitude, isNull);
    });
  });
}

CityNodeDetail _node({
  int? vm,
  int? status = 1,
  int? coupon,
  bool completed = false,
  double? lat = 30.2,
  double? lng = 120.1,
  String? a,
  String? b,
  String? c,
  String? d,
}) {
  return CityNodeDetail(
    poiId: 1,
    name: 'n',
    status: status,
    validationMethod: vm,
    couponId: coupon,
    completed: completed,
    lat: lat,
    lng: lng,
    questionA: a,
    questionB: b,
    questionC: c,
    questionD: d,
  );
}
