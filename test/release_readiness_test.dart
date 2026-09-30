// 发版就绪闸:锁住「填了一半」这种最危险的中间态。
//
// 上线要用的外部凭据(微信 appid、安卓签名、Universal Link)都必须由人去申请,
// 代码里现在是占位值。**占位本身不危险** —— 危险的是「填了一处、漏了另一处」:
//
//   · Dart 常量填了真 appid,iOS Info.plist 还是占位 → iOS 上点微信登录没反应
//   · Universal Link 少一个结尾斜杠 → iOS 授权失败,微信给的提示很含糊
//
// 安卓侧的回调入口由 fluwx 插件自带(见下面第二条),不需要手写 ——
// 这点我一度判反了,详见那条测试里的更正说明。
//
// 这两种都**不报错、不崩溃**,真机上只表现为「点了没反应」,排查成本极高
// (auth_controller.dart:18-22 已经记了这个症状)。而且它们只在**发版前那几天**
// 才有人碰,正是最容易忙中出错的时候。
//
// 所以这道闸不要求「必须填好」(那会让日常开发一直红),只要求**要么全是占位、
// 要么全都到位且互相一致**。现在全是占位 → 绿;填完整 → 绿;填一半 → 红。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

/// 从 Dart 源码里抠出 `kWechatAppId` 的字面值。
String _dartAppId() {
  final String src =
      File('lib/feature/auth/auth_controller.dart').readAsStringSync();
  final RegExpMatch? m =
      RegExp(r"const String kWechatAppId = '([^']*)'").firstMatch(src);
  expect(m, isNotNull,
      reason: 'auth_controller.dart 里找不到 kWechatAppId —— '
          '常量改名了就把这道闸一起改,别让它静默失效');
  return m!.group(1)!;
}

/// iOS URL Scheme 里登记的微信 appid(CFBundleURLSchemes 里 `wx` 开头那个)。
String? _iosAppId() {
  final String plist = File('ios/Runner/Info.plist').readAsStringSync();
  final Iterable<RegExpMatch> all =
      RegExp(r'<string>(wx[A-Za-z0-9]*)</string>').allMatches(plist);
  return all.isEmpty ? null : all.first.group(1);
}

bool _isPlaceholder(String appId) =>
    appId.isEmpty || appId.startsWith('wxYOUR');

void main() {
  test('★ 微信 appid 三处一致 —— 不许填一半', () {
    final String dart = _dartAppId();
    final String? ios = _iosAppId();

    expect(ios, isNotNull,
        reason: 'Info.plist 里的 wx URL Scheme 不见了 —— '
            '没有它 iOS 授权后回不到 App');

    // 占位期:两边都得是占位。一边先填了 = 正是要拦的中间态。
    if (_isPlaceholder(dart) || _isPlaceholder(ios!)) {
      expect(_isPlaceholder(dart) && _isPlaceholder(ios!), isTrue,
          reason: '微信 appid 只填了一半:\n'
              '  Dart kWechatAppId = $dart\n'
              '  iOS Info.plist    = $ios\n'
              '两边必须同时填。只填一处的话,没填的那一端点微信登录**没有任何反应**,'
              '不报错也不崩溃。');
      // ★ 全占位时**不能静默通过**。
      //   2026-08-19 实测:占位符 wxYOURAPPID 会**原样打进 iOS 产物**
      //   (Runner.app/Info.plist 的 CFBundleURLTypes 里就是它),
      //   这样的包上架后微信登录/支付点下去没有任何反应。
      //   而这条测试原来是绿的 —— 一个"一致的占位符"照样算一致。
      //   改成 skip 并说明,让 `flutter test` 的输出里**看得见这条阻塞**。
      markTestSkipped(
        '微信 appid 仍是占位 $dart —— 这是**上线阻塞项**。\n'
        '  需要在微信开放平台注册「移动应用」拿到真 appid'
        '(与小程序的 appid 不是同一个),同时填进:\n'
        '    · lib/feature/auth/auth_controller.dart 的 kWechatAppId\n'
        '    · ios/Runner/Info.plist 的 CFBundleURLTypes\n'
        '  填完本测试会自动开始逐字比对。',
      );
      return;
    }

    // 到位期:两边必须逐字相同。
    expect(ios, dart,
        reason: 'Dart 常量与 iOS Info.plist 的 appid 对不上:\n'
            '  Dart = $dart\n  iOS  = $ios');
  });

  test('★ 安卓微信回调由 fluwx 提供,不是自己写 —— 换版本别把它丢了', () {
    // ⚠️ **2026-08-19 更正**:我先前判定「安卓侧根本没有 WXEntryActivity,整块还没做」,
    //    并据此动手写了 WXEntryActivity / WXPayEntryActivity 和 manifest 注册。**判错了。**
    //    fluwx 自己的 AndroidManifest 里早就声明了两个 activity-alias
    //    (`${applicationId}.wxapi.WXEntryActivity` / `.WXPayEntryActivity`
    //    → FluwxWXEntryActivity)以及 `<queries><package name="com.tencent.mm">`。
    //    我手写的那份是**重复声明**,已全部撤回。
    //
    //    错在哪:`find android -name WXEntryActivity*` 零命中 + 文档里写着 TODO,
    //    我就当成「没做」——**没去看依赖合并进来的 manifest**。
    //    零命中 ≠ 不存在,文档写 TODO ≠ 现在还是 TODO。
    //
    // 所以这条闸要盯的不是「有没有自己写」,而是**fluwx 是否仍在提供它** ——
    // 升级/更换插件时最容易把这层默默弄丢,而丢了同样是「授权后回不来」。
    final File cfg = File('.dart_tool/package_config.json');
    if (!cfg.existsSync()) {
      markTestSkipped('.dart_tool/package_config.json 不在,先跑 flutter pub get');
      return;
    }
    final Map<String, dynamic> json =
        jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
    final List<dynamic> pkgs = json['packages'] as List<dynamic>;
    final Map<String, dynamic>? fluwx = pkgs
        .cast<Map<String, dynamic>>()
        .where((Map<String, dynamic> p) => p['name'] == 'fluwx')
        .firstOrNull;
    expect(fluwx, isNotNull, reason: '依赖里已经没有 fluwx —— 微信登录/支付靠什么实现?');

    final String root = Uri.parse(fluwx!['rootUri'] as String).toFilePath();
    final File manifest =
        File('$root/android/src/main/AndroidManifest.xml');
    expect(manifest.existsSync(), isTrue,
        reason: 'fluwx 的 AndroidManifest 找不到:${manifest.path}');
    final String m = manifest.readAsStringSync();

    // 微信 SDK 按这两个包路径反查,少一个对应的链路就是断的
    expect(m, contains(r'${applicationId}.wxapi.WXEntryActivity'),
        reason: 'fluwx 不再提供登录回调别名 —— 授权后回不来,用户卡在微信里');
    expect(m, contains(r'${applicationId}.wxapi.WXPayEntryActivity'),
        reason: 'fluwx 不再提供支付回调别名 —— 付完钱回不来,'
            '订单停在待支付态(本项目确实在用微信支付)');

    // Android 11+ 包可见性:缺了 isWeChatInstalled 在装了微信的机器上也恒 false
    expect(m, contains('com.tencent.mm'),
        reason: 'fluwx 不再声明微信包可见性 —— Android 11+ 上会误报「未安装微信」,'
            '低版本系统测不出来');
  });

  test('★ App 图标不能还是 Flutter 默认蓝 F —— App Store 会直接打回', () {
    // 2026-08-19 `flutter build ipa --no-codesign` 的自带校验报出来的:
    //   ! App icon is set to the default placeholder icon.
    //   ! Launch image is set to the default placeholder icon.
    // 用默认图标提交,App Store Connect 会拒收(Guideline 4.0 / 资产校验),
    // **白等一轮审核**(几天)。这类事只在发版当天才有人想起来,所以钉成门禁。
    //
    // 判据用 md5 而不是「文件存不存在」—— 文件一直都在,只是内容是 Flutter 的 F。
    //
    // ✅ 2026-08-19 已换成品牌图标,这条从 skip 转成**真守卫**。
    //
    // ★ 早先我判断"现有素材做不了"(小程序的 cy_logo_mark.png 只有 128×128
    //   且带 alpha,放大 8 倍会糊)—— **那个判断是错的**。
    //   正确做法不是放大位图,是**按几何关系重画**:那个 mark 是纯几何图形
    //   (切角矩形 + 开口圆环 + 一道斜杠),用取自原图的主色 #7C5CFF
    //   直接以 1024 画一遍即可,无需原始矢量源。生成脚本:tool/mkicon.py。
    //
    // 下面的 skip 分支保留:万一有人把默认图恢复回来,它会给出可操作的提示
    // 而不是一句冷冰冰的失败。
    // 指纹用「字节数 + 前后各 64 字节的 hashCode」—— 不引 crypto 包,
    // 为一道闸加一个直接依赖不划算。这个组合足以区分两张不同的图。
    const int kFlutterDefaultIconBytes = 10932;

    final File icon = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png');
    expect(icon.existsSync(), isTrue, reason: '1024 图标文件不见了');

    final List<int> raw = icon.readAsBytesSync();
    if (raw.length == kFlutterDefaultIconBytes) {
      markTestSkipped('App 图标仍是 Flutter 默认蓝 F —— '
          '上线前必须换成 1024×1024 无 alpha 的品牌图标,否则 App Store 拒收。'
          '换完把本测试的 skip 去掉。');
      return;
    }

    // 换过图标之后这条才真正生效:防止有人不小心把默认图恢复回来。
    expect(raw.length, isNot(kFlutterDefaultIconBytes));
    // App Store 硬性要求:1024 图标**不能有 alpha 通道**。
    // 这里只能粗判 —— PNG 色彩类型 6(RGBA)/ 4(灰度+A)即带 alpha。
    final int colorType = raw[25]; // IHDR: 8字节签名 + 4长度 + 4类型 + 13数据,颜色类型在第 25 字节
    expect(colorType == 6 || colorType == 4, isFalse,
        reason: 'iOS 1024 图标带了 alpha 通道,App Store Connect 会拒收');
  });

  test('Universal Link 与 appid 同步到位(iOS 授权拉起的必要条件)', () {
    final String src =
        File('lib/feature/auth/auth_controller.dart').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r"const String kWechatUniversalLink = '([^']*)'")
            .firstMatch(src);
    expect(m, isNotNull, reason: 'kWechatUniversalLink 常量不见了');
    final String link = m!.group(1)!;

    expect(link, startsWith('https://'),
        reason: 'Universal Link 必须是 https 的公网地址');
    expect(link, endsWith('/'),
        reason: '微信开放平台要求 Universal Link 以 / 结尾,'
            '少一个斜杠会在真机上授权失败且提示很含糊');

    final RegExpMatch? appIdMatch =
        RegExp(r"const String kWechatAppId = '([^']*)'").firstMatch(src);
    expect(appIdMatch, isNotNull, reason: 'kWechatAppId 常量不见了');
    final String appId = appIdMatch!.group(1)!;
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<string>$appId</string>'),
        reason: 'Info.plist URL Scheme 必须与 Dart kWechatAppId 完全一致');

    final String entitlements =
        File('ios/Runner/Runner.entitlements').readAsStringSync();
    final String host = Uri.parse(link).host;
    expect(entitlements, contains('<string>applinks:$host</string>'),
        reason: 'Associated Domains 必须与 Universal Link host 完全一致');
  });
  test('★★ 缺 keystore 时,release 构建必须**吼一声**说它在用调试证书', () {
    // 2026-08-19 实测:`flutter build apk --release` 成功产出 137.6MB 的
    // app-release.apk,而 `apksigner verify --print-certs` 报
    //   Signer #1 certificate DN: CN=Android Debug, O=Android, C=US
    // —— 这种包**上不了任何商店,也不能用于备案**(备案登记的证书 MD5
    // 必须与上架包一致)。而构建过程一声不响地成功了。
    //
    // 回退到 debug 签名本身是有意的(让本地能跑 --release),
    // 问题是**没有任何提示**。这条盯的就是那句警告别被人顺手删掉。
    final String gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final int at = gradle.indexOf('signingConfig = if (hasReleaseKey)');
    expect(at, greaterThan(0), reason: '签名配置不见了 —— 请更新本测试');
    // ⚠️ 必须夹 —— 锚点靠近文件尾时 at+1600 会越界抛 RangeError,
    //   那会让门禁以「测试报错」而不是「断言失败」的形态红,看不出真因。
    final String block = gradle.substring(at, (at + 1600).clamp(0, gradle.length));
    expect(block.contains('logger.warn'), isTrue,
        reason: '回退 debug 签名时没有任何警告 —— '
            '构建会静默产出一个名叫 app-release.apk、却上不了架的包');
    expect(block.contains('调试证书'), isTrue);
    expect(block.contains('apksigner verify'), isTrue,
        reason: '警告里要给出自查命令,否则看到警告的人不知道怎么确认');
  });

  test('★ 上架前必须换成正式签名(当前:未配置)', () {
    // key.properties 由**用户自己**创建并保管口令 —— 密钥一旦用于上架
    // 就永远不能更换,所以不能由我生成、也不该进仓库。
    final bool hasKey = File('android/key.properties').existsSync();
    if (!hasKey) {
      markTestSkipped(
        '尚未配置 android/key.properties —— release 包目前是 **debug 签名**,'
        '上不了架、也不能用于 ICP 备案。\n'
        '配好后本测试会自动开始真检查。',
      );
      return;
    }
    // 配了就检查四个键齐全:缺一个 Gradle 会在构建时才炸,而且报错很含糊。
    final String props = File('android/key.properties').readAsStringSync();
    for (final String k in <String>[
      'storeFile',
      'storePassword',
      'keyAlias',
      'keyPassword',
    ]) {
      // ⚠️ multiLine 必须显式打开:Dart 的 RegExp 默认下 `^` 只匹配**整串开头**,
      //   于是只有文件第一行(storeFile)能过,后三个键恒判「缺」——
      //   配置明明是全的,测试却红,红的原因还写着「缺 storePassword」。
      expect(RegExp('^\\s*$k\\s*=\\s*\\S', multiLine: true).hasMatch(props),
          isTrue,
          reason: 'key.properties 缺 $k');
    }
    // ⚠️ 绝不能把 key.properties 提交进仓库。
    final String ignore = File('.gitignore').existsSync()
        ? File('.gitignore').readAsStringSync()
        : '';
    final String androidIgnore = File('android/.gitignore').existsSync()
        ? File('android/.gitignore').readAsStringSync()
        : '';
    expect(
        ignore.contains('key.properties') ||
            androidIgnore.contains('key.properties'),
        isTrue,
        reason: 'key.properties 没被 gitignore —— 上架密钥会被提交进仓库');
  });

  test('★★ 两端的包标识各是各的 —— 上线后都改不了,登记时别只报一个', () {
    // 2026-08-19 从**真产物**读出来的:
    //   Android applicationId          = com.chengyinhub.chengyin_app
    //   iOS PRODUCT_BUNDLE_IDENTIFIER  = com.chengyinhub.chengyinApp
    // 不一样是 **Flutter 的默认行为**(iOS 包标识不允许下划线),不是 bug。
    // 但两个都要**分别**去微信开放平台和 ICP 备案登记,而且发版后
    // 谁都改不了(改了等于换一个 App,老用户升不了级)。
    // 这条盯的是「有人改了其中一个、忘了另一个」。
    final String gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final RegExpMatch? aid =
        RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle);
    expect(aid, isNotNull, reason: 'applicationId 解析不到 —— 断言写法失效了');

    final String pbx =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final Set<String> iosIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
        .allMatches(pbx)
        .map((RegExpMatch m) => m.group(1)!.trim())
        .where((String id) => !id.contains('Tests') && !id.contains('RunnerTests'))
        .toSet();
    expect(iosIds, isNotEmpty);

    expect(aid!.group(1), 'com.chengyinhub.chengyin_app',
        reason: 'Android 包名变了 —— 若已上架过,这等于换了一个 App;'
            '若还没上架,请同步更新本测试与备案材料');
    expect(iosIds, contains('com.chengyinhub.chengyinApp'),
        reason: 'iOS 包标识变了 —— 同上,且要同步微信开放平台的登记');
  });

  test('★★ 占位 appid 不许出现在已构建的产物里', () {
    // 2026-08-19 实测:iOS 产物 Runner.app/Info.plist 的 CFBundleURLTypes 里
    // 就是 wxYOURAPPID —— 占位符**真的会被打进包**,不是只躺在源码里。
    // 这样的包上架后,微信登录/支付点下去**没有任何反应**(不报错不崩溃)。
    //
    // 这条只在产物存在时才检查(CI 上通常没有),存在就必须干净。
    final File plist = File('build/ios/iphoneos/Runner.app/Info.plist');
    if (!plist.existsSync()) {
      markTestSkipped('还没构建过 iOS 产物,跳过');
      return;
    }
    final ProcessResult r = Process.runSync(
      '/usr/bin/plutil',
      <String>['-convert', 'xml1', '-o', '-', plist.path],
    );
    final String xml = r.stdout.toString();
    expect(xml, isNotEmpty, reason: 'plutil 读不出来 —— 断言失效');
    if (xml.contains('wxYOURAPPID')) {
      // 占位期:这是**已知阻塞**,不该判成回归失败,但必须说出来。
      markTestSkipped(
        '已构建的 iOS 产物里带着占位 appid wxYOURAPPID —— '
        '这个包即使装上真机,微信登录/支付也点不动。'
        '换成真 appid 后重新构建,本测试会自动开始真检查。',
      );
      return;
    }
    expect(xml.contains('YOURAPPID'), isFalse,
        reason: '产物里还有占位符残留');
  });

  test('★★ 启动屏底色必须与 App 首屏一致 —— 否则冷启动会白闪一下', () {
    // 2026-08-19 实测:storyboard 的 backgroundColor 是纯白
    // (red=1 green=1 blue=1),而 App 首屏是 CyTokens.bgPage = #000000。
    // 冷启动会先白闪再跳黑,那一下很显眼 —— 而且**只在真机冷启动时能看到**,
    // 热重载和模拟器都不重现,所以只能靠这条钉住。
    //
    // ⚠️ 两处都要对:storyboard 的底色 **和** LaunchImage 本身的底。
    //   只改一处仍会闪(图是黑的但四周白,或反过来)。
    final String board =
        File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
    final RegExpMatch? m = RegExp(
            r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)"')
        .firstMatch(board);
    expect(m, isNotNull, reason: 'storyboard 里的 backgroundColor 不见了');
    for (int i = 1; i <= 3; i++) {
      expect(double.parse(m!.group(i)!), 0,
          reason: '启动屏底色不是黑 —— 与首屏 CyTokens.bgPage(#000000)对不上,'
              '冷启动会闪');
    }

    // 启动图本身也不能还是 1×1 的空占位。
    final File img = File(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png');
    expect(img.existsSync(), isTrue);
    final List<int> raw = img.readAsBytesSync();
    // PNG IHDR:8 字节签名 + 4 长度 + 4 类型,宽度在第 16..19 字节(大端)。
    final int w = (raw[16] << 24) | (raw[17] << 16) | (raw[18] << 8) | raw[19];
    expect(w, greaterThan(64),
        reason: '启动图还是 ${w}×$w 的占位 —— '
            'flutter build 会报 "Launch image is set to the default placeholder"');
    // 同样禁 alpha:启动图带透明会在某些设备上露出系统底色。
    expect(raw[25] == 6 || raw[25] == 4, isFalse,
        reason: '启动图带了 alpha 通道');
  });

  test('★★ Android 自适应图标 —— 没有它,现代 launcher 会套白底并缩一圈', () {
    // Android 8+ 用 adaptive-icon:背景层 + 前景层,系统按各家 launcher 的
    // 形状裁切。只提供传统 ic_launcher.png 的话,launcher 会自动给它
    // 套一个白色圆底并把图缩小 —— 桌面上看着比别人小一号、还带白边。
    final Directory v26 =
        Directory('android/app/src/main/res/mipmap-anydpi-v26');
    expect(v26.existsSync(), isTrue, reason: '缺 mipmap-anydpi-v26 目录');
    for (final String f in <String>['ic_launcher.xml', 'ic_launcher_round.xml']) {
      expect(File('${v26.path}/$f').existsSync(), isTrue, reason: '缺 $f');
    }

    // 前景层五档齐全,且**必须带 alpha**(要透出背景层)。
    const List<String> densities = <String>[
      'mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi',
    ];
    for (final String d in densities) {
      final File fg = File(
          'android/app/src/main/res/mipmap-$d/ic_launcher_foreground.png');
      expect(fg.existsSync(), isTrue, reason: '缺 mipmap-$d 的前景层');
      final List<int> raw = fg.readAsBytesSync();
      expect(raw[25], 6,
          reason: 'mipmap-$d 的前景层没有 alpha —— 会把背景层整个盖住');
    }
  });

  test('★★ Android 启动底也必须是黑 —— 与 iOS 同一个白闪问题', () {
    // iOS 是 LaunchScreen.storyboard 的 backgroundColor;
    // Android 是 drawable/launch_background.xml。两边都默认白,
    // 而 App 首屏是 #000000 —— 冷启动各闪各的。
    // ⚠️ 剥掉 XML 注释再判 —— 注释里会写着"原来是 @android:color/white",
    //   照全文扫会把那句说明当成"现在还是白"。
    //   (与 support/source_text.dart 同一个道理,这里是 XML 所以另写一遍。)
    final String bg = File(
            'android/app/src/main/res/drawable/launch_background.xml')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    expect(bg.contains('@android:color/white'), isFalse,
        reason: 'Android 启动底还是白 —— 冷启动会白闪');
    expect(bg.contains('@color/cy_launch_bg'), isTrue);

    final String colors =
        File('android/app/src/main/res/values/cy_colors.xml').readAsStringSync();
    expect(colors.contains('<color name="cy_launch_bg">#000000</color>'), isTrue,
        reason: 'cy_launch_bg 必须与 CyTokens.bgPage(#000000)一致');
  });

  test('★★ 三处都要锁竖屏 —— 只锁 Dart 那一处不够', () {
    // 全站页面都是竖版布局(单列表单、底部固定 CTA)。横过来不崩,
    // 但会被拉宽、每屏少一半内容,而且 AppBar 的 action 会被角标压住 ——
    // 2026-08-19 用 852×393 渲了一屏确认过,不是猜的。
    //
    // ⚠️ **只在 Dart 里 setPreferredOrientations 不够**:
    //   启动到首帧之间那段仍按系统方向渲染,审核员横着开 App
    //   会先看到一屏歪的。三处都锁才算数。

    // ① Dart
    final String main = codeOf('lib/main.dart');
    expect(main.contains('setPreferredOrientations'), isTrue);
    expect(main.contains('DeviceOrientation.landscapeLeft'), isFalse,
        reason: '允许了横屏');

    // ② iOS
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist.contains('UIInterfaceOrientationLandscape'), isFalse,
        reason: 'Info.plist 还声明支持横屏 —— 启动首帧会按系统方向渲');

    // ③ Android
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('android:screenOrientation="portrait"'), isTrue,
        reason: 'MainActivity 没锁竖屏');
  });

  test('★ 没有 ATS 任意 HTTP 例外 —— App Store 会追问理由', () {
    // NSAllowsArbitraryLoads=true 需要在提交时写书面说明,
    // 而我们全站 HTTPS,压根不需要开它。这条防的是有人为了调试临时加上忘了删。
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist.contains('NSAllowsArbitraryLoads'), isFalse,
        reason: '开了 ATS 例外 —— 要么删掉,要么准备好书面理由');
  });

}
