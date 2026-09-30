import 'dart:io';

import 'package:chengyin_app/feature/roam/roam_poi_detail_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('据点文字与选项互动使用 Apple 系统弹层', () {
    expect(const RoamPoiDetailPage(poiId: 7).poiId, 7);
    final String source = File(
      'lib/feature/roam/roam_poi_detail_page.dart',
    ).readAsStringSync();

    expect(source, contains('showCySystemTextInputAlert'));
    expect(source, contains('keyboardKind: CySystemKeyboardKind.text'));
    expect(source, contains('CupertinoActionSheet'));
    expect(source, contains('CupertinoActionSheetAction'));
    expect(source, isNot(contains('AlertDialog(')));
    expect(source, isNot(contains('showModalBottomSheet<String>')));
  });

  test('足迹卡工作流使用 Cupertino sheet 与共用层确认弹窗', () {
    final String source = File(
      'lib/feature/roam/roam_session_page.dart',
    ).readAsStringSync();

    expect(source, contains('showCupertinoSheet<void>'));
    expect(source, contains('CupertinoPageScaffold'));
    // 相册用途确认走共用层 cyConfirm(iOS 26+ 真系统 alert,旧系统回退
    // CupertinoAlertDialog)—— 不再自写裸弹窗(手册 S4)。
    expect(source, contains('cyConfirm('));
    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, isNot(contains('AlertDialog.adaptive')));
  });

  test('原生弹层保留小程序文案与提交值', () {
    final String poiSource = File(
      'lib/feature/roam/roam_poi_detail_page.dart',
    ).readAsStringSync();
    final String sessionSource = File(
      'lib/feature/roam/roam_session_page.dart',
    ).readAsStringSync();

    expect(poiSource, contains('完成互动'));
    expect(poiSource, contains('输入答案 / 暗号'));
    expect(poiSource, contains('Navigator.pop(ctx, c.letter)'));
    expect(sessionSource, contains('分享足迹卡'));
    expect(sessionSource, contains('保存足迹卡到相册'));
    expect(sessionSource, contains('返回本次漫游'));
  });

  test('漫游主操作使用 Liquid Glass 与 Cupertino 按钮', () {
    final String source = <String>[
      'lib/feature/roam/roam_live_page.dart',
      'lib/feature/roam/roam_poi_detail_page.dart',
    ].map((String path) => File(path).readAsStringSync()).join('\n');

    expect(source, contains('CyNativeButton('));
    expect(source, contains('CupertinoButton('));
    for (final String materialControl in <String>[
      'FilledButton(',
      'OutlinedButton(',
      'TextButton(',
      'IconButton(',
    ]) {
      expect(source, isNot(contains(materialControl)), reason: materialControl);
    }
  });
}
