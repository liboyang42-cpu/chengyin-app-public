import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_decor.dart';

void main() {
  group('★ 精选是一对,只给一个是无效状态', () {
    test('都有 → 自洽', () {
      const d = MerchantDecor(featuredType: 1, featuredId: 9);
      expect(d.featuredConsistent, isTrue);
    });
    test('都没有 → 也自洽', () {
      expect(const MerchantDecor().featuredConsistent, isTrue);
    });
    test('只有类型 → 不自洽', () {
      expect(
        const MerchantDecor(featuredType: 1).featuredConsistent,
        isFalse,
        reason: '后端会存下一条指向空的精选,首页展示时是个空位',
      );
    });
    test('只有 id / id 为 0 → 不自洽', () {
      expect(const MerchantDecor(featuredId: 9).featuredConsistent, isFalse);
      expect(
        const MerchantDecor(featuredType: 1, featuredId: 0).featuredConsistent,
        isFalse,
      );
    });
  });

  group('★ 清精选:copyWith 做不到', () {
    const d = MerchantDecor(slogan: 'x', featuredType: 1, featuredId: 9);
    test('withoutFeatured 同时清两个', () {
      final n = d.withoutFeatured();
      expect(n.featuredType, isNull);
      expect(n.featuredId, isNull);
      expect(n.slogan, 'x', reason: '别把别的字段一起清了');
    });
    test('copyWith 是反例 —— 它把 null 当"不改"', () {
      expect(d.copyWith(featuredId: null).featuredId, 9);
    });
  });

  group('★ 全空不该提交', () {
    test('什么都没填 → 挡住', () {
      expect(const MerchantDecor().hasAnything, isFalse);
      expect(
        const MerchantDecor().blocker,
        '至少填一项再保存',
        reason: '空提交会白白触发一次内容安全审核',
      );
    });
    test('全是空白字符也算没填', () {
      expect(
        const MerchantDecor(slogan: '  ', storyTitle: '  ').hasAnything,
        isFalse,
      );
    });
    test('填了任一项就能提交', () {
      expect(const MerchantDecor(slogan: '一杯咖啡的城市').blocker, isNull);
      expect(const MerchantDecor(gallery: <String>['a.jpg']).blocker, isNull);
    });
  });

  group('★ 保存统一写 canonical JSON', () {
    test('删光相册后能真的删掉', () {
      const d = MerchantDecor(slogan: 'x');
      expect(
        d.toJson()['gallery'],
        '[]',
        reason: '发 null 后端会当"不改",用户删光相册就删不掉了',
      );
      expect(d.toJson()['tags'], '[]');
    });
    test('有内容时写 JSON 数组', () {
      const d = MerchantDecor(gallery: <String>['a.jpg', 'b.jpg']);
      expect(jsonDecode(d.toJson()['gallery']! as String), <String>[
        'a.jpg',
        'b.jpg',
      ]);
    });
  });

  group('解析', () {
    test('分号切开并去空', () {
      final d = MerchantDecor.fromJson(<String, dynamic>{
        'gallery': 'a.jpg; ;b.jpg;',
        'tags': '咖啡;;甜点',
      });
      expect(d.gallery, <String>['a.jpg', 'b.jpg']);
      expect(d.tags, <String>['咖啡', '甜点']);
    });
    test('小程序 JSON 数组字符串与直接数组都能读', () {
      final fromStrings = MerchantDecor.fromJson(<String, dynamic>{
        'gallery': '["a.jpg", "b.jpg"]',
        'tags': '["安静", "适合工作"]',
      });
      expect(fromStrings.gallery, <String>['a.jpg', 'b.jpg']);
      expect(fromStrings.tags, <String>['安静', '适合工作']);

      final fromArrays = MerchantDecor.fromJson(<String, dynamic>{
        'gallery': <String>['c.jpg'],
        'tags': <String>['夜间开放'],
      });
      expect(fromArrays.gallery, <String>['c.jpg']);
      expect(fromArrays.tags, <String>['夜间开放']);
    });
    test('缺字段给空表,不抛', () {
      final d = MerchantDecor.fromJson(<String, dynamic>{});
      expect(d.gallery, isEmpty);
      expect(d.tags, isEmpty);
    });
    test('展示层真源字段不丢失', () {
      final d = MerchantDecor.fromJson(<String, dynamic>{
        'categoryId': 3,
        'featuredType': 1,
        'featuredId': 9,
        'serviceTag': '免费',
        'serviceText': '咖啡体验',
        'locationLat': 31.2,
        'locationLng': 121.4,
        'locationVerified': 1,
      });
      expect(d.toJson(), containsPair('categoryId', 3));
      expect(d.toJson(), containsPair('featuredType', 1));
      expect(d.toJson(), containsPair('featuredId', 9));
      expect(d.toJson(), containsPair('serviceTag', '免费'));
      expect(d.toJson(), containsPair('serviceText', '咖啡体验'));
      expect(d.toJson(), containsPair('locationLat', 31.2));
      expect(d.toJson(), containsPair('locationLng', 121.4));
      expect(d.toJson(), containsPair('locationVerified', 1));
    });
  });
}
