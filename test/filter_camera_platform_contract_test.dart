import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 相机与麦克风的**权限面**契约。
///
/// ★★ 2026-09-05 这份契约的两条断言被**有意改写**,改的理由必须留在这里:
///
///   原来它钉的是「RECORD_AUDIO 与 NSMicrophoneUsageDescription 一律不许出现」。
///   那条在当时是对的 —— camera_android_camerax 自带录音权限,而 App 里**没有任何
///   功能用麦克风**,一个用不到却要来的权限会在上架审核和用户信任上双输。
///
///   P2 的门店声音克隆让「有没有功能用麦克风」这个前提变了:商家要录五句话。
///   所以现在钉的不再是「不许有」,而是:
///     ① 麦克风权限**必须有真实使用方**(`lib/` 下真有代码在开录);
///     ② 旧版写存储权限**仍然一律移除**(那条的前提没变,至今没有功能用它);
///     ③ 滤镜相机**自己**仍然不录音(enableAudio: false)——
///        声音克隆用的是独立的录音页,与相机链路无关。
///
///   ⚠️ 只把断言删掉、不换成新断言,等于把这道闸拆了。
///      门禁的价值在于「权限面变化必须是一次显式决定」,而不是「永远不许变」。
void main() {
  test('滤镜相机自己不录音;旧版写存储权限仍一律移除', () {
    final String manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final String cameraSource = File(
      'lib/feature/play/filter_shot_camera.dart',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.CAMERA'));

    // ② 旧版写存储:前提没变(至今没有功能用它),仍必须显式移除。
    final RegExp storageRemoval = RegExp(
      '<uses-permission[^>]*android:name="android.permission.WRITE_EXTERNAL_STORAGE"'
      '[^>]*tools:node="remove"',
    );
    expect(
      storageRemoval.hasMatch(manifest),
      isTrue,
      reason: 'WRITE_EXTERNAL_STORAGE 必须显式从 camera 插件合并清单移除',
    );

    // ③ 相机链路自己不录音 —— 声音克隆走独立录音页,不该让相机也拿到麦克风。
    expect(cameraSource, contains('enableAudio: false'));
  });

  test('★ 麦克风权限必须有真实使用方 —— 声明了却没人用就该拿掉', () {
    final String manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final String info = File('ios/Runner/Info.plist').readAsStringSync();
    final bool androidDeclared = RegExp(
      '<uses-permission[^>]*android:name="android.permission.RECORD_AUDIO"'
      '(?![^>]*tools:node="remove")',
    ).hasMatch(manifest);
    final bool iosDeclared = info.contains('NSMicrophoneUsageDescription');

    // 两端要么都声明、要么都不声明。只有一端声明 = 另一端上真机时录不了音,
    // 而且是运行时才发现。
    expect(
      androidDeclared,
      iosDeclared,
      reason: '麦克风权限必须两端一致声明,否则会出现只有一个平台能录音',
    );

    if (!androidDeclared) return; // 没声明就没有「谁在用」要查。

    // ★★ 声明了就必须有真实使用方 —— 判据见 _filesThatRecord 上方的注释。
    final List<String> recorders = _filesThatRecord();
    expect(recorders, isNotEmpty, reason: '声明了麦克风权限,却没有一处代码真的开录');

    // 每个使用方与它在用途说明里那句话同进同退,判据见 _micUsers 上方的注释。
    _micUsers.forEach((String dir, String purpose) {
      expect(
        info.contains(purpose),
        recorders.any((String p) => p.contains(dir)),
        reason: '$dir 这个使用方与 iOS 用途说明「$purpose」必须同进同退',
      );
    });
  });

  test('iOS 相机用途覆盖实时滤镜，部署下限固定 13.0', () {
    final String info = File('ios/Runner/Info.plist').readAsStringSync();
    final String podfile = File('ios/Podfile').readAsStringSync();

    expect(info, contains('实时预览滤镜并拍照完成打卡'));
    expect(podfile, contains("platform :ios, '13.0'"));
  });
}

/// 麦克风的使用方:功能所在目录 ↔ iOS 用途说明里对应的那句话。
///
/// 两边必须同进同退:说明里写了却没人在录 = 白要权限;
/// 有人在录却没写进说明 = 说明之外的采集,审核会问,而且问得对。
///
/// ⚠️ 每一条都是**双条件**,不是「用途说明必须有这句」。整块功能连同它那句说明
/// 一起删掉时这道闸放行 —— 那时权限由另一个使用方撑着,说明也不再声称采集。
/// (2026-09-10:商家那条从无条件改成双条件,与玩家那条对齐。)
const Map<String, String> _micUsers = <String, String>{
  '/feature/merchant/': '生成本店 AI 形象的声音',
  '/play/free_explore/': '按住说话',
};

/// `lib/` 下**真的在开录**的文件 —— 判据是「配了一份录音参数」**并且**「真去调了
/// `start(`」,不是「import 了插件」也不是「叫这个名字」。
///
/// ⚠️ **判据是「有没有代码真的开录」,不是「有没有那个文件」**(2026-09-10 复审)。
/// 原来两条使用方各自绑死一个源文件路径:把文件挪个位置会红在**错的原因**上;
/// 反过来把文件留着、只删掉 `_recorder.start(RecordConfig(...))` 那一句,门禁照样
/// 绿 —— 而那时已经没人在录了。`contains('AudioRecorder')` 同理:import 还在就满足。
///
/// ⚠️ 两条分开判、不写成 `.start(RecordConfig` 一个正则:后者会被
/// 「把参数提到局部变量再传进去」这种纯重构误伤 —— 红在错的原因上和不红一样坏。
///
/// ⚠️ 返回路径只用来分辨「哪个功能」(按目录),不拿它当门禁的判据本身:
/// 文件在自己那个功能目录里怎么挪都不该让这道闸变色。
List<String> _filesThatRecord() {
  final RegExp startCall = RegExp(r'\.start\(');
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where((File f) {
        final String src = f.readAsStringSync();
        return src.contains('RecordConfig') && startCall.hasMatch(src);
      })
      .map((File f) => f.path)
      .toList();
}
