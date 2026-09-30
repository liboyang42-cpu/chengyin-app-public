import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/p3/badges/badge_detail_logic.dart';

void main() {
  group('badgeDetailParams:坏参数全部兜底,不崩', () {
    test('正常参数透传', () {
      final p = badgeDetailParams(const <String, String>{
        'name': '城墙勋章',
        'sub': '城墙线',
        'img': 'https://cdn/x.png',
        'style': 'enamel',
        'rarity': '2',
      });
      expect(p.name, '城墙勋章');
      expect(p.sub, '城墙线');
      expect(p.img, 'https://cdn/x.png');
      expect(p.isEnamel, isTrue);
      expect(p.rarity, 2);
      expect(p.tierName, '史诗');
    });

    test('★ rarity 越界夹回 0..4,不是放行负数/7', () {
      expect(
        badgeDetailParams(const <String, String>{'rarity': '7'}).rarity,
        4,
      );
      expect(
        badgeDetailParams(const <String, String>{'rarity': '-1'}).rarity,
        0,
      );
      expect(
        badgeDetailParams(const <String, String>{'rarity': 'abc'}).rarity,
        0,
      );
    });

    test('img 只接受 http(s),相对路径一律空串(不让坏参数变黑面)', () {
      expect(
        badgeDetailParams(const <String, String>{'img': '/assets/x.png'}).img,
        '',
      );
      expect(
        badgeDetailParams(const <String, String>{'img': 'ftp://x'}).img,
        '',
      );
      expect(
        badgeDetailParams(const <String, String>{'img': 'HTTPS://x.png'}).img,
        '',
      );
    });

    test('style 只认 glow,其余归 enamel(缺省方向=珐琅,badge-3d/index.js:50)', () {
      expect(
        badgeDetailParams(const <String, String>{'style': 'glow'}).style,
        'glow',
      );
      expect(
        badgeDetailParams(const <String, String>{'style': 'xxx'}).style,
        'enamel',
      );
      expect(
        badgeDetailParams(const <String, String>{}).style,
        'enamel',
        reason: '无参进页默认珐琅,与真源同方向',
      );
    });

    test('名字空 → 徽章兜底', () {
      final p = badgeDetailParams(const <String, String>{'name': '   '});
      expect(p.name, '徽章');
    });
  });
}
