// 唤起外部地图的兜底链。
//
// ⚠️⚠️ 这块最容易出的事故是**静默失败**:iOS 上 canLaunchUrl 需要
//   Info.plist 声明 LSApplicationQueriesSchemes,漏声明恒 false ——
//   「导航」按钮点下去什么都不发生,还不报错。
//   所以设计成**必有兜底的链**,而不是「能不能打开」的判断。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/map/map_launcher.dart';

void main() {
  test('★★ 代码里用到的自定义 scheme,**两个平台**都必须声明', () {
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    final String code = File('lib/core/map/map_launcher.dart').readAsStringSync();
    // 从代码里抽出所有非 http(s) 的 scheme。
    final Set<String> used = <String>{
      for (final RegExpMatch m
          in RegExp(r"Uri\.parse\('([a-z][a-z0-9+.-]*)://").allMatches(code))
        m.group(1)!,
    };
    expect(used, isNotEmpty, reason: '一个 scheme 都没抽到 —— 断言写法失效了');
    // ⚠️ 只管 iOS 就是半边防线:Android 11+ 有包可见性限制,
    //   不在 <queries> 里声明同样会「点了什么都不发生且不报错」。
    //   两个平台是**同一个坑的两个版本**,门禁必须一起管。
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final String s in used) {
      if (s == 'http') continue; // 明文 http 不用,也不该声明
      if (s != 'https' && s != 'geo') {
        // 自定义 scheme:iOS 要 LSApplicationQueriesSchemes。
        expect(plist.contains('<string>' + s + '</string>'), isTrue,
            reason: '代码里用了 ' + s + ':// 但 Info.plist 没声明 —— '
                'canLaunchUrl 会恒返回 false,按钮点了什么都不发生且不报错');
      }
      // Android:自定义 scheme 与 geo/https 都要进 <queries>。
      expect(manifest.contains('android:scheme="' + s + '"'), isTrue,
          reason: '代码里用了 ' + s + ':// 但 AndroidManifest 的 <queries> 没声明 —— '
              'Android 11+ 上解析不到目标 App,同样是静默失败');
    }
  });

  group('★★ 坐标判据:0/0 视为没有', () {
    test('后端拿不到坐标时常下发 0 —— 导过去会把人送到几内亚湾', () {
      expect(hasCoordinates(0, 0), isFalse);
      expect(hasCoordinates(0, 121.4), isFalse);
      expect(hasCoordinates(31.2, 0), isFalse);
      expect(hasCoordinates(null, 121.4), isFalse);
      expect(hasCoordinates(31.2, 121.4), isTrue);
    });
    test('★★ NaN/Infinity 也算没有 —— 异常坐标喂进下游距离计算会「toInt」红屏', () {
      expect(hasCoordinates(double.parse('NaN'), 121.4), isFalse);
      expect(hasCoordinates(31.2, double.parse('NaN')), isFalse);
      expect(hasCoordinates(double.infinity, 121.4), isFalse);
      expect(hasCoordinates(31.2, double.negativeInfinity), isFalse);
    });
  });

  group('URI 拼装', () {
    test('名字要 URL 编码 —— 中文和空格不编码会截断整条 URI', () {
      expect(systemMapUri(lat: 1, lng: 2, name: '静安 咖啡', isIOS: true).toString(),
          isNot(contains('静安 咖啡')));
    });
    test('iOS 走苹果地图,Android 走 geo:', () {
      expect(systemMapUri(lat: 1, lng: 2, name: 'x', isIOS: true).host,
          'maps.apple.com');
      expect(systemMapUri(lat: 1, lng: 2, name: 'x', isIOS: false).scheme, 'geo');
    });
  });

  group('★★ 兜底链:任何一步走通都算成功,全不行也要留下地址', () {
    test('★ 第一档就是系统地图 —— 高德已随 Task 1.4 拆除,不该再被试', () async {
      final List<Uri> tried = <Uri>[];
      final MapLaunchResult r = await launchNavigation(
        lat: 31.2, lng: 121.4, name: 'x', isIOS: true,
        launcher: (Uri u) async { tried.add(u); return true; },
      );
      expect(r, MapLaunchResult.opened);
      expect(tried.single.host, 'maps.apple.com');
      expect(tried.map((Uri u) => u.scheme), isNot(contains('amapuri')));
    });

    test('Android 第一档是 geo:', () async {
      final List<Uri> tried = <Uri>[];
      final MapLaunchResult r = await launchNavigation(
        lat: 31.2, lng: 121.4, name: 'x', isIOS: false,
        launcher: (Uri u) async { tried.add(u); return true; },
      );
      expect(r, MapLaunchResult.opened);
      expect(tried.single.scheme, 'geo');
    });

    test('★★ 都打不开 ⇒ 复制地址,不留一个没反应的按钮', () async {
      String? copied;
      final MapLaunchResult r = await launchNavigation(
        lat: 31.2, lng: 121.4, name: '静安咖啡', address: '南京西路 1266 号',
        isIOS: true,
        launcher: (Uri _) async => false,
        copy: (String t) async => copied = t,
      );
      expect(r, MapLaunchResult.copied);
      expect(copied, contains('南京西路 1266 号'));
    });

    test('★ launcher 抛异常也不打断链 —— scheme 没声明就是会抛', () async {
      String? copied;
      final MapLaunchResult r = await launchNavigation(
        lat: 1, lng: 2, name: 'x', isIOS: true,
        launcher: (Uri _) async => throw Exception('scheme not declared'),
        copy: (String t) async => copied = t,
      );
      expect(r, MapLaunchResult.copied);
      expect(copied, isNotNull);
    });

    test('没地址时复制「名字 + 坐标」,总比什么都没有强', () async {
      String? copied;
      await launchNavigation(
        lat: 31.2, lng: 121.4, name: '静安咖啡', isIOS: false,
        launcher: (Uri _) async => false,
        copy: (String t) async => copied = t,
      );
      expect(copied, contains('31.2'));
    });

    test('★ 没坐标 ⇒ 直接 noCoordinates,一个 URI 都不试', () async {
      final List<Uri> tried = <Uri>[];
      final MapLaunchResult r = await launchNavigation(
        lat: 0, lng: 0, name: 'x', isIOS: false,
        launcher: (Uri u) async { tried.add(u); return true; },
      );
      expect(r, MapLaunchResult.noCoordinates);
      expect(tried, isEmpty);
    });
  });

  group('提示语', () {
    test('打开了就不提示', () {
      expect(mapLaunchMessage(MapLaunchResult.opened), isEmpty);
    });
    test('★ 只复制了要说清**为什么**,否则用户以为按钮坏了', () {
      expect(mapLaunchMessage(MapLaunchResult.copied), contains('没找到可用的地图应用'));
      expect(mapLaunchMessage(MapLaunchResult.copied), contains('已复制'));
    });
    test('★★ 没坐标是**数据没给**不是操作失败 —— 别说「请重试」', () {
      final String m = mapLaunchMessage(MapLaunchResult.noCoordinates);
      expect(m, contains('还没有坐标'));
      expect(m, isNot(contains('重试')), reason: '重试也没用,坐标不会因为再点一次就出现');
    });
  });
}

// ── iOS 声明 ────────────────────────────────────────────────────
//
// ⚠️⚠️ 这是本文件里**最容易腐烂**的一条:代码里加一个新 scheme 很容易,
//   而忘了在 Info.plist 里声明的话,canLaunchUrl 恒返回 false ——
//   按钮点了什么都不发生,**还不报错**。
//   兜底链能让用户至少拿到地址,但那已经是降级了。
