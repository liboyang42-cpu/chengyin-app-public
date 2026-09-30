// 核验方式(validationMethod)文案的唯一真源。
//
// ★★ 这一条曾经在 App 里裂成四套:template.dart 把码 1 错标「扫码核销」、
//   码 4–7 全塌成「其他」;city_node_detail 说「文字暗号」;city_node_poi 说
//   「答题打卡」;商家表单又说「扫张贴码 / 走到就算」。
//   同一条后端码,四个页面四个叫法 —— 用户在小程序、App 两处看到的对不上。
//
// 真源与小程序 `chengyinhub-xcx/utils/validation-method-labels.js` 同口径,
// 跨端一致性由 validation_method_parity_test.dart 读那份文件对账。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/city_node_poi.dart';
import 'package:chengyin_app/data/models/node_template.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/data/models/validation_method_labels.dart';

/// 独立于实现的一份期望(来自真源码表),用来证明实现没跑偏。
const Map<int, String> kCanonical = <int, String>{
  0: '无需验证',
  1: '文字作答',
  2: '拍照打卡',
  3: '选项问答',
  4: '到店扫码',
  5: 'GPS 到达',
  6: '偏好题组',
  7: '传感器挑战',
};

void main() {
  PlayTemplate tpl(int? v) => PlayTemplate.fromJson(<String, dynamic>{
    'id': 1,
    'title': '找猫',
    'validationMethod': v,
  });
  CityNodeDetail det(int? v) => CityNodeDetail.fromJson(<String, dynamic>{
    'poiId': 1,
    'validationMethod': v,
  });
  CityNodePoi poi(int? v) => CityNodePoi.fromJson(<String, dynamic>{
    'poiId': 1,
    'name': 'X',
    'validationMethod': v,
  });

  group('共享 helper', () {
    test('码 0–7 全部认', () {
      for (final MapEntry<int, String> e in kCanonical.entries) {
        expect(validationMethodLabel(e.key), e.value, reason: '码 ${e.key}');
      }
    });

    test('null 保持空语义(不是「无需验证」)', () {
      expect(validationMethodLabel(null), isNull);
    });

    test('未知码明确回落「其他」,不编名字', () {
      expect(validationMethodLabel(99), '其他');
      expect(validationMethodLabel(-1), '其他');
    });
  });

  group('同一 App 不再多套文案', () {
    test('★ 码 0–7 三处展示完全一致', () {
      for (final MapEntry<int, String> e in kCanonical.entries) {
        expect(
          tpl(e.key).validationText,
          e.value,
          reason: 'template 码 ${e.key}',
        );
        expect(det(e.key).methodLabel, e.value, reason: 'detail 码 ${e.key}');
        expect(poi(e.key).interactionText, e.value, reason: 'poi 码 ${e.key}');
      }
    });

    test('★ 码 1 不再错标「扫码核销」', () {
      expect(tpl(1).validationText, '文字作答');
      expect(tpl(1).validationText, isNot('扫码核销'));
    });

    test('★ 码 4–7 不再塌缩成「其他」', () {
      for (final int v in <int>[4, 5, 6, 7]) {
        expect(tpl(v).validationText, isNot('其他'), reason: '码 $v 塌了');
        expect(det(v).methodLabel, isNot('其他'), reason: 'detail 码 $v 塌了');
        expect(poi(v).interactionText, isNot('其他'), reason: 'poi 码 $v 塌了');
      }
    });

    test('null 各守原语义,未知码统一「其他」', () {
      expect(tpl(null).validationText, isNull);
      expect(det(null).methodLabel, '到店完成');
      expect(poi(null).interactionText, '到点打卡');
      expect(tpl(99).validationText, '其他');
      expect(det(99).methodLabel, '其他');
      expect(poi(99).interactionText, '其他');
    });

    test('商家表单枚举与码表一致,且不开放 6/7', () {
      for (final NodeValidationMethod m in NodeValidationMethod.values) {
        expect(m.label, kCanonical[m.wire], reason: '枚举 wire=${m.wire}');
      }
      expect(NodeValidationMethod.values.length, 5, reason: '本批只统一文案,不新增可创作方式');
      expect(NodeValidationMethod.fromWire(6), isNull);
      expect(NodeValidationMethod.fromWire(7), isNull);
    });
  });
}
