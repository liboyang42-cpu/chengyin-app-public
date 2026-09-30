// 契约测试:现有核心模型(Product / Topic / TopicDetail / PointsRecord / GrowthCenter)。
//
// 这些模型对齐冻结契约 contract/openapi-v1.json 的 /api/product/*、/api/topic/*、
// /api/user/points/list、/api/growth/center 响应。每个模型:1 个正常解析用例
// + 至少 1 个容错/边界用例。后端字段一旦改名/改结构,断言就红。
//
// 这些模型的 fromJson 现在用 lib/core/util/json_parse.dart 的容错函数
// (asInt/asDouble/asBool/asStr),后端把数字字段返成 String("100")也不崩,
// 与 contract/README.md 声明的"数字可能 int/long/String"一致。因此边界用例
// 同时覆盖「字段缺失/null 给默认」「字段改名兜底」与「数字传 String」。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/product.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/data/models/points_record.dart';
import 'package:chengyin_app/data/models/growth.dart';

void main() {
  group('Product.fromJson (/api/product/list 的 rows[])', () {
    test('正常解析:商品价格就是积分，不除以 100', () {
      final p = Product.fromJson(<String, dynamic>{
        'id': 9001,
        'productName': '城瘾联名帆布袋',
        'pic': 'https://cdn/p.jpg',
        'albumPics': 'https://cdn/a1.jpg,https://cdn/a2.jpg',
        'price': 3990, // 积分
        'originalPrice': 4990,
        'stock': 100,
        'unit': '个',
        'merchantId': 12,
        'publishStatus': 1, // 列表里有但模型不取,确保多余字段不报错
        'sortId': 5,
      });

      expect(p.id, 9001);
      expect(p.productName, '城瘾联名帆布袋');
      expect(p.pic, 'https://cdn/p.jpg');
      expect(p.price, 3990);
      expect(p.pricePoints, 3990);
      expect(p.originalPrice, 4990);
      expect(p.originalPricePoints, 4990);
      expect(p.stock, 100);
      expect(p.unit, '个');
      expect(p.merchantId, 12);
      expect(p.albumList, <String>['https://cdn/a1.jpg', 'https://cdn/a2.jpg']);
      expect(p.skuList, isEmpty);
    });

    test('边界:缺字段/null 给默认;originalPrice==0 -> originalPricePoints 为 null', () {
      final p = Product.fromJson(<String, dynamic>{
        'id': 1,
        'productName': '简装商品',
        'price': 0,
        'originalPrice': 0,
        // pic/albumPics/stock/unit/merchantId/skuList 全缺
      });
      expect(p.id, 1);
      expect(p.price, 0);
      expect(p.pricePoints, 0);
      expect(p.originalPricePoints, isNull); // 0 视为无原价
      expect(p.stock, 0);
      expect(p.pic, isNull);
      expect(p.albumList, isEmpty);
      expect(p.skuList, isEmpty);
    });

    test('详情接口:skuList 的 BigDecimal price 也是积分', () {
      final p = Product.fromJson(<String, dynamic>{
        'id': 1,
        'productName': '带规格',
        'price': 1000,
        'skuList': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'skuName': '红/M',
            'price': 10.5,
            'stock': 3,
          },
          <String, dynamic>{'id': 2, 'skuName': '蓝/L', 'price': 12, 'stock': 0},
        ],
      });
      expect(p.skuList.length, 2);
      expect(p.skuList.first.skuName, '红/M');
      expect(p.skuList.first.price, 10.5);
      expect(p.skuList[1].price, 12.0);
    });

    test('容错:数字字段传 String 不抛,解析成对应数值', () {
      final p = Product.fromJson(<String, dynamic>{
        'id': '1000',
        'productName': '字符串数字商品',
        'price': '3123', // 分,String 形态
        'originalPrice': '4990',
        'stock': '88',
        'merchantId': '12',
        'skuList': <dynamic>[
          <String, dynamic>{
            'id': '7',
            'skuName': '默认',
            'price': '10.5',
            'stock': '3',
          },
        ],
      });
      expect(p.id, 1000);
      expect(p.price, 3123);
      expect(p.pricePoints, 3123);
      expect(p.originalPrice, 4990);
      expect(p.stock, 88);
      expect(p.merchantId, 12);
      expect(p.skuList.first.id, 7);
      expect(p.skuList.first.price, 10.5);
      expect(p.skuList.first.stock, 3);
    });

    test('积分展示不带人民币符号，整数不补无意义小数', () {
      expect(formatPoints(3990), '3990 积分');
      expect(formatPoints(10.5), '10.5 积分');
      expect(formatPoints(null), '积分待确认');
    });
  });

  group('Topic.fromJson (/api/topic/list)', () {
    test('正常解析:后端真实字段 imgUrl/description 映射到 picUrl/introduction', () {
      final t = Topic.fromJson(<String, dynamic>{
        'id': 50,
        'name': '老城厢漫步',
        'imgUrl': 'https://cdn/t.jpg', // 后端 CmsTopic 用 imgUrl
        'description': '探索上海老城厢', // 后端用 description
        'isRecommend': 1,
        'isLike': 1,
        'likeNum': 42,
      });
      expect(t.id, 50);
      expect(t.name, '老城厢漫步');
      expect(t.picUrl, 'https://cdn/t.jpg');
      expect(t.introduction, '探索上海老城厢');
      expect(t.isRecommend, 1);
      expect(t.isLike, 1);
      expect(t.likeNum, 42);
    });

    test('边界:走 picUrl/introduction 兜底键 + 缺字段给默认', () {
      final t = Topic.fromJson(<String, dynamic>{
        'id': 1,
        'name': '兜底主题',
        'picUrl': 'https://cdn/fallback.jpg', // 无 imgUrl 时用 picUrl
        'introduction': '兜底简介', // 无 description/subtitle 时用 introduction
        // isRecommend/isLike/likeNum 缺 -> 0
      });
      expect(t.picUrl, 'https://cdn/fallback.jpg');
      expect(t.introduction, '兜底简介');
      expect(t.isRecommend, 0);
      expect(t.isLike, 0);
      expect(t.likeNum, 0);
    });

    test('容错:id/likeNum 等数字传 String 不抛,解析成对应数值', () {
      final t = Topic.fromJson(<String, dynamic>{
        'id': '50',
        'name': '字符串数字主题',
        'imgUrl': 'https://cdn/t.jpg',
        'description': '简介',
        'isRecommend': '1',
        'isLike': '1',
        'likeNum': '42',
      });
      expect(t.id, 50);
      expect(t.isRecommend, 1);
      expect(t.isLike, 1);
      expect(t.likeNum, 42);
    });
  });

  group('TopicDetail.fromJson (/api/topic/info 的 TopicInfoVO)', () {
    test('正常解析:chaptersList -> chapters -> nodes 三层嵌套', () {
      final d = TopicDetail.fromJson(<String, dynamic>{
        'id': 50,
        'name': '老城厢漫步',
        'description': '简介',
        'imgUrl': 'https://cdn/t.jpg',
        'chaptersList': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'title': '第一章',
            'nodes': <dynamic>[
              <String, dynamic>{'id': 11, 'name': '城隍庙'},
              <String, dynamic>{
                'id': 12,
                'nodeName': '豫园',
              }, // name 兜底用 nodeName
            ],
          },
        ],
      });
      expect(d.id, 50);
      expect(d.name, '老城厢漫步');
      expect(d.introduction, '简介');
      expect(d.picUrl, 'https://cdn/t.jpg');
      expect(d.chapters.length, 1);
      expect(d.chapters.first.title, '第一章');
      expect(d.chapters.first.nodes.length, 2);
      expect(d.chapters.first.nodes.first.name, '城隍庙');
      expect(d.chapters.first.nodes[1].name, '豫园'); // nodeName 兜底
    });

    test('边界:chaptersList 缺失 -> 空列表不抛', () {
      final d = TopicDetail.fromJson(<String, dynamic>{'id': 1, 'name': '空主题'});
      expect(d.chapters, isEmpty);
      expect(d.introduction, isNull);
      expect(d.picUrl, isNull);
    });

    test('容错:章节/节点 id 传 String 不抛,解析成对应数值', () {
      final d = TopicDetail.fromJson(<String, dynamic>{
        'id': '50',
        'name': '字符串数字详情',
        'chaptersList': <dynamic>[
          <String, dynamic>{
            'id': '1',
            'title': '第一章',
            'nodes': <dynamic>[
              <String, dynamic>{'id': '11', 'name': '城隍庙'},
            ],
          },
        ],
      });
      expect(d.id, 50);
      expect(d.chapters.first.id, 1);
      expect(d.chapters.first.nodes.first.id, 11);
    });
  });

  group('PointsRecord.fromJson (/api/user/points/list)', () {
    test('正常解析 + isIncome/title 派生', () {
      final r = PointsRecord.fromJson(<String, dynamic>{
        'id': 7,
        'changePoints': 12,
        'afterPoints': 112,
        'changeReason': '完成节点打卡',
        'eventType': 3,
        'changeType': 1, // 收入
        'createTime': '2026-06-23 10:00:00',
      });
      expect(r.id, 7);
      expect(r.changePoints, 12);
      expect(r.afterPoints, 112);
      expect(r.changeReason, '完成节点打卡');
      expect(r.eventType, 3);
      expect(r.changeType, 1);
      expect(r.isIncome, true);
      expect(r.title, '完成节点打卡');
      expect(r.createTime, '2026-06-23 10:00:00');
    });

    test('边界:changeReason 缺 -> title 按 eventType 兜底;changeType!=1 非收入', () {
      final r = PointsRecord.fromJson(<String, dynamic>{
        'id': 1,
        'changePoints': 50,
        'eventType': 1, // 注册
        'changeType': 2, // 支出
        // changeReason/afterPoints/createTime 缺
      });
      expect(r.afterPoints, isNull);
      expect(r.isIncome, false);
      expect(r.title, '注册账号'); // eventType==1 兜底文案
    });

    test('容错:分值/类型等数字传 String 不抛,解析成对应数值', () {
      final r = PointsRecord.fromJson(<String, dynamic>{
        'id': '7',
        'changePoints': '12',
        'afterPoints': '112',
        'eventType': '3',
        'changeType': '1', // 收入
      });
      expect(r.id, 7);
      expect(r.changePoints, 12);
      expect(r.afterPoints, 112);
      expect(r.eventType, 3);
      expect(r.changeType, 1);
      expect(r.isIncome, true);
    });
  });

  group('GrowthCenter.fromJson (/api/growth/center)', () {
    test('正常解析:growth 子对象 + badges/missions 列表', () {
      final g = GrowthCenter.fromJson(<String, dynamic>{
        'growth': <String, dynamic>{'levelNo': 3, 'expValue': 280},
        'points': 1500,
        'badges': <dynamic>[
          <String, dynamic>{
            'badgeName': '城市探索者',
            'iconUrl': 'https://cdn/badge.png',
            'badgeCode': 'EXPLORER',
          },
        ],
        'missions': <dynamic>[
          <String, dynamic>{
            'missionName': '首次打卡',
            'missionDesc': '完成任意节点',
            'expReward': 20,
          },
        ],
      });
      expect(g.levelNo, 3);
      expect(g.expValue, 280);
      expect(g.points, 1500);
      expect(g.badges.length, 1);
      expect(g.badges.first.badgeName, '城市探索者');
      expect(g.badges.first.badgeCode, 'EXPLORER');
      expect(g.missions.length, 1);
      expect(g.missions.first.missionName, '首次打卡');
      expect(g.missions.first.expReward, 20);
    });

    test('边界:growth 缺失 -> levelNo 默认 1 / expValue 0;列表缺失 -> 空', () {
      final g = GrowthCenter.fromJson(<String, dynamic>{
        // growth/points/badges/missions 全缺
      });
      expect(g.levelNo, 1); // 默认从 1 级起
      expect(g.expValue, 0);
      expect(g.points, 0);
      expect(g.badges, isEmpty);
      expect(g.missions, isEmpty);
    });

    test('容错:growth 子对象/points/expReward 数字传 String 不抛', () {
      final g = GrowthCenter.fromJson(<String, dynamic>{
        'growth': <String, dynamic>{'levelNo': '3', 'expValue': '280'},
        'points': '1500',
        'missions': <dynamic>[
          <String, dynamic>{
            'missionName': '首次打卡',
            'missionDesc': '完成任意节点',
            'expReward': '20',
          },
        ],
      });
      expect(g.levelNo, 3);
      expect(g.expValue, 280);
      expect(g.points, 1500);
      expect(g.missions.first.expReward, 20);
    });
  });
}
