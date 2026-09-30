import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 安卓正式签名配置门禁。
///
/// ★ 为什么需要:工信部 App 备案登记的是**公钥与证书 MD5 指纹**,
///   它必须与真正上架的安装包签名一致。Flutter 模板默认
///   `signingConfig = signingConfigs.getByName("debug")`,
///   用它打出来的包既上不了应用商店,也和备案信息对不上。
///
///   而这件事**不会以任何方式报错** —— `flutter build apk --release` 照常成功,
///   包也能装。直到提交应用商店或备案核查才发现。所以要门禁盯着。
void main() {
  final gradle = File('android/app/build.gradle.kts');

  test('release 不再无条件用 debug 签名', () {
    final src = gradle.readAsStringSync();
    // 允许「没有 key.properties 时回退 debug」,但不允许写死。
    expect(
      src.contains('// TODO: Add your own signing config'),
      isFalse,
      reason: 'Flutter 模板的 TODO 还在 = 正式签名从没配过',
    );
    expect(
      src.contains('hasReleaseKey'),
      isTrue,
      reason: 'release 必须能读到独立的正式签名配置',
    );
  });

  test('密钥文件不进仓库', () {
    final ignore = File('android/.gitignore').readAsStringSync();
    for (final String pat in <String>['key.properties', '*.keystore', '*.jks']) {
      expect(ignore.contains(pat), isTrue,
          reason: '$pat 必须被忽略 —— 签名密钥泄露等于别人可以冒名发布你的 App,'
              '且这个密钥一旦用于上架就换不了');
    }
  });

  test('包名与备案登记一致', () {
    final src = gradle.readAsStringSync();
    expect(src.contains('applicationId = "com.chengyinhub.chengyin_app"'), isTrue,
        reason: '包名是工信部 App 备案「特征信息」里登记的值,'
            '改了就必须去备案系统同步变更');
  });

  test('iOS 与安卓包名不同,别混用', () {
    // iOS: com.chengyinhub.chengyinApp(驼峰)
    // 安卓: com.chengyinhub.chengyin_app(下划线)
    // 两处备案条目分别登记,填混了核查不过。
    final gradleSrc = gradle.readAsStringSync();
    expect(gradleSrc.contains('chengyinApp'), isFalse,
        reason: '安卓的包名是 chengyin_app(下划线),别写成 iOS 的 chengyinApp');
  });
}
