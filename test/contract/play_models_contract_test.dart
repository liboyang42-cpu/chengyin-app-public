// 契约测试:打卡闭环模型(PlayNode / PlayNodesResult / CheckinReward / PlayBadge)。
//
// 这些模型对齐冻结契约 contract/openapi-v1.json 的 /api/play/* 响应。
// 后端字段类型不稳(数字 int/long/String、bool true/1/"1"/"true"、字段缺失/null),
// 模型用 _asInt/_asDouble/_asBool/_asStr + _asOptions 容错。本文件覆盖:
//   - 正常 JSON 全字段解析
//   - 容错边界:数字传 String、bool 传 1 与 "true"、缺字段/null 给默认不抛
//   - options 为对象 / 缺失
//   - CheckinReward.doneCount 取自 'done' 字段
//   - CheckinReward 发分只认回执 xp/score 真值(xpReported 区分「报了 0」与「没报」);
//     medalRank/nightWarning/puzzleScore 等 F 段字段可空安全解析
//
// 后端字段一旦变了,这些断言就红,拦截破坏性变更。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';

void main() {
  group('PlayNode.fromJson', () {
    test('正常解析全字段(选项题 vm==3)', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 101,
        'name': '城隍庙',
        'address': '上海市黄浦区方浜中路',
        'sortId': 1,
        'longitude': 121.4912,
        'latitude': 31.2270,
        'imgUrl': 'https://cdn.example.com/n101.jpg',
        'description': '老城厢的中心',
        'merchantId': '7001',
        'arrived': 1,
        'selfReported': 'true',
        'validationMethod': 3,
        'needScan': false,
        'needAnswer': true,
        'needGps': false,
        'done': false,
        'question': '城隍庙供奉的城隍是谁?',
        'options': <String, dynamic>{
          'A': '秦裕伯',
          'B': '霍光',
          'C': '陈化成',
          'D': '黄道婆',
        },
      });

      expect(node.nodeId, 101);
      expect(node.name, '城隍庙');
      expect(node.address, '上海市黄浦区方浜中路');
      expect(node.sortId, 1);
      expect(node.longitude, 121.4912);
      expect(node.latitude, 31.2270);
      expect(node.imgUrl, 'https://cdn.example.com/n101.jpg');
      expect(node.description, '老城厢的中心');
      expect(node.merchantId, 7001);
      expect(node.arrived, true);
      expect(node.selfReported, true);
      expect(node.validationMethod, 3);
      expect(node.needScan, false);
      expect(node.needAnswer, true);
      expect(node.needGps, false);
      expect(node.done, false);
      expect(node.question, '城隍庙供奉的城隍是谁?');
      expect(node.options, <String, String>{
        'A': '秦裕伯',
        'B': '霍光',
        'C': '陈化成',
        'D': '黄道婆',
      });
    });

    test('容错:数字传 String,bool 传 1 与 "true",经纬度传 String', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': '101', // String -> int
        'name': '豫园',
        'address': '安仁街',
        'sortId': '2', // String -> int
        'longitude': '121.492', // String -> double
        'latitude': '31.227',
        'validationMethod': '4', // String -> int
        'needScan': 1, // 数字 1 -> true
        'needAnswer': 'true', // 字符串 "true" -> true
        'needGps': '1', // 字符串 "1" -> true
        'done': true,
      });

      expect(node.nodeId, 101);
      expect(node.sortId, 2);
      expect(node.longitude, closeTo(121.492, 1e-9));
      expect(node.latitude, closeTo(31.227, 1e-9));
      expect(node.validationMethod, 4);
      expect(node.needScan, true);
      expect(node.needAnswer, true);
      expect(node.needGps, true);
      expect(node.done, true);
    });

    test('缺字段/null:给默认值不抛(扫码节点,无 options/question)', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 5,
        'name': '外滩',
        // address 缺失 -> ''
        // sortId 缺失 -> 0
        // longitude/latitude 缺失 -> null
        'imgUrl': null,
        'description': null,
        'validationMethod': null, // 到店即可
        // needScan/needAnswer/needGps 缺失 -> false
        // done 缺失 -> false
        'question': null,
        // options 缺失 -> null
      });

      expect(node.nodeId, 5);
      expect(node.name, '外滩');
      expect(node.address, '');
      expect(node.sortId, 0);
      expect(node.longitude, isNull);
      expect(node.latitude, isNull);
      expect(node.imgUrl, isNull);
      expect(node.description, isNull);
      expect(node.merchantId, isNull);
      expect(node.arrived, false);
      expect(node.selfReported, false);
      expect(node.validationMethod, isNull);
      expect(node.needScan, false);
      expect(node.needAnswer, false);
      expect(node.needGps, false);
      expect(node.done, false);
      expect(node.question, isNull);
      expect(node.options, isNull);
    });

    test('question 为空串 -> null(模型把空字符串当无题面)', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 1,
        'name': 'n',
        'question': '',
      });
      expect(node.question, isNull);
    });

    test('options 为空对象 / 含 null 值 -> 过滤后为 null', () {
      final empty = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 1,
        'name': 'n',
        'options': <String, dynamic>{},
      });
      expect(empty.options, isNull);

      final allNull = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 1,
        'name': 'n',
        'options': <String, dynamic>{'A': null, 'B': ''},
      });
      expect(allNull.options, isNull);
    });

    test('options 数字值被 toString(后端混类型)', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 1,
        'name': 'n',
        'options': <String, dynamic>{'A': 1, 'B': 2.5},
      });
      expect(node.options, <String, String>{'A': '1', 'B': '2.5'});
    });

    test('vm=7 解析 App 传感器类型与配置', () {
      final PlayNode node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 7,
        'name': '静止挑战',
        'validationMethod': 7,
        'sensorType': 'still',
        'sensorConfig': <String, dynamic>{'durationSec': 20, 'tolerance': 0.08},
      });

      expect(node.validationMethod, 7);
      expect(node.sensorType, 'still');
      expect(node.sensorConfig, <String, dynamic>{
        'durationSec': 20,
        'tolerance': 0.08,
      });
    });

    test('vm=7 sensorConfig 兼容后端 JSON string', () {
      final PlayNode node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 7,
        'name': '静止挑战',
        'validationMethod': 7,
        'sensorType': 'still',
        'sensorConfig': '{"durationSec":30,"tolerance":0.12}',
      });

      expect(node.sensorConfig, <String, dynamic>{
        'durationSec': 30,
        'tolerance': 0.12,
      });
    });

    test('非传感器节点缺省 sensorType/sensorConfig 为 null', () {
      final PlayNode node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 2,
        'name': '滤镜拍摄',
        'validationMethod': 2,
      });

      expect(node.sensorType, isNull);
      expect(node.sensorConfig, isNull);
    });

    test('vm=2 filter_shot 解析公开滤镜契约', () {
      final PlayNode node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 9,
        'name': '异常观测',
        'validationMethod': 2,
        'sensorType': 'filter_shot',
        'sensorConfig': '{"filterStyle":"night_vision"}',
      });

      expect(node.isFilterShot, isTrue);
      expect(node.sensorConfig, <String, dynamic>{
        'filterStyle': 'night_vision',
      });
    });

    test('普通 vm=2 不会被误判为 filter_shot', () {
      const PlayNode node = PlayNode(
        nodeId: 10,
        name: '普通拍照',
        address: '',
        sortId: 1,
        done: false,
        validationMethod: 2,
      );

      expect(node.isFilterShot, isFalse);
      expect(node.hasUnsupportedPhotoSubtype, isFalse);
    });

    test('vm=2 非空未知子类 fail-closed', () {
      const PlayNode node = PlayNode(
        nodeId: 11,
        name: '错误子类',
        address: '',
        sortId: 1,
        done: false,
        validationMethod: 2,
        sensorType: 'filter-shot',
      );

      expect(node.isFilterShot, isFalse);
      expect(node.hasUnsupportedPhotoSubtype, isTrue);
    });

    test('奖励链字段:xp/puzzleScore/completionMode/勋章/券 全量解析', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 101,
        'name': '城隍庙',
        'address': '',
        'sortId': 1,
        'done': true,
        'xp': 20,
        'puzzleScore': 0,
        'completionMode': 'REVEALED',
        'medalName': '首阵勋章',
        'medalStyle': 'glow',
        'medalImg': 'https://cdn/m.png',
        'couponId': 5001,
      });
      expect(node.xp, 20);
      expect(node.puzzleScore, 0); // 真 0 分,不是「没计分」
      expect(node.completionMode, 'REVEALED');
      expect(node.medalName, '首阵勋章');
      expect(node.medalStyle, 'glow');
      expect(node.medalImg, 'https://cdn/m.png');
      expect(node.couponId, 5001);
    });

    test('奖励链字段缺省:null 不冒充实值;couponId=0 判「没配券」', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 101,
        'name': '城隍庙',
        'address': '',
        'sortId': 1,
        'done': false,
        'couponId': 0,
      });
      expect(node.xp, isNull);
      expect(node.puzzleScore, isNull);
      expect(node.completionMode, isNull);
      expect(node.medalName, isNull);
      expect(node.medalImg, isNull);
      expect(node.couponId, isNull);
    });

    test('withRoute 保留奖励链字段(路线覆盖不许把真值抹成 null)', () {
      final node = PlayNode.fromJson(<String, dynamic>{
        'nodeId': 101,
        'name': '城隍庙',
        'address': '',
        'sortId': 1,
        'done': false,
        'xp': 15,
        'puzzleScore': 88,
        'couponId': 7,
        'medalName': '首阵勋章',
      }).withRoute(state: 'PLAYABLE');
      expect(node.xp, 15);
      expect(node.puzzleScore, 88);
      expect(node.couponId, 7);
      expect(node.medalName, '首阵勋章');
      expect(node.routeNodeState, 'PLAYABLE');
    });
  });

  group('PlayNodesResult.fromJson', () {
    test('正常解析:进度字段 + 嵌套 nodes(mode 2 自由探索)', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 77,
        'mode': 2,
        'playable': true,
        'timeNote': null,
        'total': 3,
        'doneCount': 1,
        'nodes': <dynamic>[
          <String, dynamic>{'nodeId': 1, 'name': 'A', 'done': true},
          <String, dynamic>{'nodeId': 2, 'name': 'B', 'done': false},
          <String, dynamic>{'nodeId': 3, 'name': 'C', 'done': false},
        ],
      });

      expect(result.topicId, 77);
      expect(result.mode, 2);
      expect(result.playable, true);
      expect(result.timeNote, isNull);
      expect(result.total, 3);
      expect(result.doneCount, 1);
      expect(result.nodes.length, 3);
      expect(result.nodes.first.name, 'A');
      expect(result.nodes.first.done, true);
      expect(result.allDone, false);
    });

    test('容错:数字传 String,playable 传 "true",timeNote 给原因', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': '77',
        'mode': '1', // 线性
        'playable': 'true',
        'timeNote': '活动未开始',
        'total': '2',
        'doneCount': '0',
        'nodes': <dynamic>[],
      });

      expect(result.topicId, 77);
      expect(result.mode, 1);
      expect(result.playable, true);
      expect(result.timeNote, '活动未开始');
      expect(result.total, 2);
      expect(result.doneCount, 0);
      expect(result.nodes, isEmpty);
    });

    test('nodes 缺失 -> 空列表不抛;allDone 在 total==0 时为 false', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 1,
        'mode': 1,
        'playable': false,
        // total/doneCount/nodes 全缺
      });
      expect(result.total, 0);
      expect(result.doneCount, 0);
      expect(result.nodes, isEmpty);
      expect(result.allDone, false);
    });

    test('allDone:doneCount >= total 且 total>0 时为 true', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 1,
        'mode': 2,
        'playable': true,
        'total': 2,
        'doneCount': 2,
        'nodes': <dynamic>[],
      });
      expect(result.allDone, true);
    });

    test('finishXp:已完成节点 xp 之和(未完成节点不计)', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 1,
        'mode': 1,
        'playable': true,
        'total': 3,
        'doneCount': 2,
        'puzzlePersonalBest': 92,
        'nodes': <dynamic>[
          <String, dynamic>{'nodeId': 1, 'name': 'A', 'done': true, 'xp': 12},
          <String, dynamic>{'nodeId': 2, 'name': 'B', 'done': true, 'xp': 30},
          <String, dynamic>{'nodeId': 3, 'name': 'C', 'done': false, 'xp': 99},
        ],
      });
      expect(result.finishXp, 42);
      expect(result.puzzlePersonalBest, 92);
    });

    test('finishXp:任一已完成节点缺 xp -> null(未知),不估算', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 1,
        'mode': 1,
        'playable': true,
        'total': 2,
        'doneCount': 1,
        'nodes': <dynamic>[
          <String, dynamic>{'nodeId': 1, 'name': 'A', 'done': true, 'xp': 12},
          <String, dynamic>{'nodeId': 2, 'name': 'B', 'done': true},
        ],
      });
      expect(result.finishXp, isNull);
    });

    test('finishPuzzle:只累计已完成且带分的站,每题钳进 0..100', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 1,
        'mode': 1,
        'playable': true,
        'total': 4,
        'doneCount': 2,
        'nodes': <dynamic>[
          <String, dynamic>{
            'nodeId': 1,
            'name': 'A',
            'done': true,
            'puzzleScore': 80,
          },
          <String, dynamic>{
            'nodeId': 2,
            'name': 'B',
            'done': true,
            'puzzleScore': 150,
          },
          <String, dynamic>{
            'nodeId': 3,
            'name': 'C',
            'done': false,
            'puzzleScore': 60,
          },
          <String, dynamic>{'nodeId': 4, 'name': 'D', 'done': true},
        ],
      });
      final puzzle = result.finishPuzzle;
      expect(puzzle.score, 180); // 80 + min(150,100);C 未完成不加分;D 没计分不计数
      expect(puzzle.count, 2);
    });

    test('puzzlePersonalBest 缺字段 -> null(没记录,不是 0 分)', () {
      final result = PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 1,
        'mode': 2,
        'playable': true,
        'total': 0,
        'doneCount': 0,
        'nodes': <dynamic>[],
      });
      expect(result.puzzlePersonalBest, isNull);
      expect(result.finishXp, 0); // 一站都没完成,真零
    });
  });

  group('PlayBadge.fromJson', () {
    test('正常解析三字段', () {
      final badge = PlayBadge.fromJson(<String, dynamic>{
        'code': 'FIRST_CHECKIN',
        'name': '初次打卡',
        'iconUrl': 'https://cdn.example.com/b.png',
      });
      expect(badge.code, 'FIRST_CHECKIN');
      expect(badge.name, '初次打卡');
      expect(badge.iconUrl, 'https://cdn.example.com/b.png');
    });

    test('缺字段/null -> 空串不抛', () {
      final badge = PlayBadge.fromJson(<String, dynamic>{'code': null});
      expect(badge.code, '');
      expect(badge.name, '');
      expect(badge.iconUrl, '');
    });
  });

  group('CheckinReward.fromJson', () {
    test('正常解析:doneCount 取自 "done" 字段 + 嵌套 newBadges', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 101,
        'firstTime': true,
        'done': 2, // -> doneCount
        'total': 5,
        'completed': false,
        'newBadges': <dynamic>[
          <String, dynamic>{
            'code': 'B1',
            'name': '徽章一',
            'iconUrl': 'https://cdn/x.png',
          },
        ],
      });

      expect(reward.nodeId, 101);
      expect(reward.firstTime, true);
      expect(reward.doneCount, 2); // 来自 'done'
      expect(reward.total, 5);
      expect(reward.completed, false);
      expect(reward.newBadges.length, 1);
      expect(reward.newBadges.first.code, 'B1');
    });

    test('容错:nodeId/done/total 传 String,bool 传 1 与 "true"', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': '101',
        'firstTime': 1,
        'done': '3',
        'total': '5',
        'completed': 'true',
      });
      expect(reward.nodeId, 101);
      expect(reward.firstTime, true);
      expect(reward.doneCount, 3);
      expect(reward.total, 5);
      expect(reward.completed, true);
    });

    test('newBadges 缺失/null -> 空列表不抛', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': false,
        'done': 0,
        'total': 0,
        'completed': false,
      });
      expect(reward.newBadges, isEmpty);
    });

    test('pointsAwarded = 回执 xp 真值,不再是 12/13 估算', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 5,
        'total': 5,
        'completed': true,
        'xp': 40, // 后端把节点探索值+掉落翻倍+通关加成一并算好
      });
      expect(reward.xpAwarded, 40);
      expect(reward.xpReported, true);
      expect(reward.pointsAwarded, 40);
    });

    test('xp 报 0 就是 0:不许补成任何估算值', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': false,
        'done': 2,
        'total': 5,
        'completed': false,
        'xp': 0,
      });
      expect(reward.xpReported, true);
      expect(reward.pointsAwarded, 0);
    });

    test('xp 缺字段 -> xpReported=false(展示层走未知态),计数为 0 不抛', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 1,
        'total': 5,
        'completed': false,
      });
      expect(reward.xpReported, false);
      expect(reward.xpAwarded, 0);
    });

    test('旧键兼容:无 xp 有 score 时读 score(真源 index.js:4389 双键)', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 1,
        'total': 5,
        'completed': false,
        'score': '18',
      });
      expect(reward.xpReported, true);
      expect(reward.xpAwarded, 18);
    });

    test('medalRank 有名次:数字与数字串都认', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 1,
        'total': 5,
        'completed': false,
        'xp': 12,
        'medalRank': 2,
      });
      expect(reward.medalRank, 2);
      final stringRank = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 1,
        'total': 5,
        'completed': false,
        'medalRank': '3',
      });
      expect(stringRank.medalRank, 3);
    });

    test('medalRank 无名次:null/0/缺字段都判「没抢到」,不是第 0 名', () {
      for (final Object? raw in <Object?>[null, 0, -1]) {
        final reward = CheckinReward.fromJson(<String, dynamic>{
          'nodeId': 1,
          'firstTime': true,
          'done': 1,
          'total': 5,
          'completed': false,
          'medalRank': raw,
        });
        expect(reward.medalRank, isNull, reason: 'medalRank=$raw');
      }
    });

    test('nightWarning:只在后端报 true 时为真,缺字段不误报', () {
      final night = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 1,
        'total': 5,
        'completed': false,
        'nightWarning': true,
      });
      expect(night.nightWarning, true);
      final day = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 1,
        'total': 5,
        'completed': false,
      });
      expect(day.nightWarning, false);
    });

    test('puzzleScore/completionMode/puzzlePersonalBest 可空解析不抛', () {
      final reward = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 5,
        'total': 5,
        'completed': true,
        'puzzleScore': 0,
        'completionMode': 'REVEALED',
        'puzzlePersonalBest': 87,
      });
      expect(reward.puzzleScore, 0); // 0 是真得分,与「没计分」的 null 分开
      expect(reward.completionMode, 'REVEALED');
      expect(reward.puzzlePersonalBest, 87);
      final plain = CheckinReward.fromJson(<String, dynamic>{
        'nodeId': 1,
        'firstTime': true,
        'done': 1,
        'total': 5,
        'completed': false,
      });
      expect(plain.puzzleScore, isNull);
      expect(plain.completionMode, isNull);
      expect(plain.puzzlePersonalBest, isNull);
    });
  });
}
