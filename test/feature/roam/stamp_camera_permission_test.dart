// 相机/相册权限被拒时的出路。
//
// ★★ `_pick` 原来**没有 try** —— image_picker 在权限被拒时会抛,
//   于是用户点了「拍照」什么都不发生、也没有任何提示,
//   而他并不知道是自己拒过相机权限。
//   这正是本项目最高频的那类问题:按钮在,点了没反应,不报错。

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  final String src = codeOf('lib/feature/roam/stamp_camera_page.dart');

  test('★★ availableCameras 必须包 try —— 权限被拒时它会抛', () {
    final int at = src.indexOf('availableCameras()');
    expect(at, greaterThan(0), reason: '断言写法失效了');
    final String around = src.substring(
      (at - 200).clamp(0, src.length),
      (at + 200).clamp(0, src.length),
    );
    expect(around.contains('try'), isTrue, reason: '没包 try:权限被拒时点了什么都不发生,还不报错');
  });

  test('★★ 权限问题才给「去设置」—— 其它失败给这个钮解决不了问题', () {
    expect(src.contains('_permissionDenied'), isTrue);
    expect(src.contains("Key('stamp-open-settings')"), isTrue);
    // 按钮必须在 _permissionDenied 分支里,不是无条件渲染。
    final int btn = src.indexOf("Key('stamp-open-settings')");
    final String before = src.substring((btn - 300).clamp(0, src.length), btn);
    expect(
      before.contains('if (_permissionDenied)'),
      isTrue,
      reason: '无条件给「去设置」= 把普通故障导向一个解决不了问题的地方',
    );
  });

  test('★ 说了「去设置」就得能一键过去', () {
    expect(
      src.contains('openAppSettings'),
      isTrue,
      reason: '只写字不给入口,等于告诉用户「自己找找看」',
    );
  });

  test('★★ 认不出的错误按「不是权限」处理', () {
    // image_picker 各平台错误码不统一,只能按关键字认。
    // 误判成权限问题会把一次普通故障导向设置页。
    expect(src.contains('_looksLikePermissionDenied'), isTrue);
    for (final String kw in <String>['permission', 'denied']) {
      expect(src.contains(kw), isTrue, reason: '少了关键字 $kw');
    }
  });

  test('★ 权限文案明确指向相机', () {
    expect(src.contains('没有相机权限'), isTrue);
  });

  test('★★ 首次访问先说明用途，用户确认后才请求系统相机权限', () {
    expect(src.contains("Key('stamp-camera-purpose')"), isTrue);
    expect(src.contains('用于拍摄城市邮票并裁切后存入你的集邮册'), isTrue);
    expect(src.contains('_purposeAccepted'), isTrue);
    expect(
      src.contains('if (!_purposeAccepted || _initializing'),
      isTrue,
      reason: '系统权限请求必须被用途说明确认门禁挡住',
    );
  });

  test('★★ 相机初始化必须有生命周期 epoch，后台回调不能重新占用相机', () {
    expect(src.contains('_cameraEpoch'), isTrue);
    expect(src.contains('_cameraActive'), isTrue);
    expect(src.contains('epoch != _cameraEpoch'), isTrue);
    for (final String state in <String>[
      'inactive',
      'paused',
      'hidden',
      'detached',
    ]) {
      expect(src.contains('AppLifecycleState.$state'), isTrue);
    }
  });

  test('★★ 原图和裁切临时文件在重拍、保存成功及退出时都会清理', () {
    expect(src.contains('_deleteOwnedFile'), isTrue);
    expect(src.contains('await _deleteOwnedFile(raw)'), isTrue);
    expect(src.contains('await _discardShot()'), isTrue);
    expect(src.contains('unawaited(_deleteOwnedFile(_shot))'), isTrue);
  });
}
