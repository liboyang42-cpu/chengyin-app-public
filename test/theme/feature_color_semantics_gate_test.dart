import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _appearanceLockedColors(String source) {
  final RegExp fixedColor = RegExp(
    r'Colors\.(?:black|black54|black87|white|white24)\b',
  );
  return fixedColor.allMatches(source).map((match) => match.group(0)!).toList();
}

void main() {
  test('可切换外观的订单和模板页只使用上下文语义色', () {
    final String orders = File(
      'lib/feature/orders/orders_page.dart',
    ).readAsStringSync();
    final String template = File(
      'lib/feature/template/template_edit_page.dart',
    ).readAsStringSync();

    expect(orders, isNot(contains('AppColors.textSecondary')));
    expect(orders, isNot(contains('CyTokens.textTertiary')));
    expect(template, isNot(contains('Colors.black54')));
    expect(orders, contains('CyPalette.of(context)'));
    expect(template, contains('CyPalette.of(context)'));
  });

  test('相机沉浸层沿用小程序语义 token，不散落黑白字面值', () {
    final String source = File(
      'lib/feature/roam/stamp_camera_page.dart',
    ).readAsStringSync();

    expect(
      _appearanceLockedColors(source),
      isEmpty,
      reason: '相机黑白 chrome 应映射小程序 token，由 token 保留对比语义',
    );
    expect(source, contains('CyTokens.overlay'));
    expect(source, contains('CyTokens.actionPrimaryBg'));
    expect(source, contains('CyTokens.actionPrimaryFg'));
  });

  test('商家 AI 指标卡的页面私有色逐项保持小程序真源', () {
    final String source = File(
      'lib/feature/merchant/merchant_ai_insight_page.dart',
    ).readAsStringSync();
    const List<String> miniProgramPrivateTokens = <String>[
      '0xFF2A2A47',
      '0xFF243039',
      '0xFFA5A6E8',
      '0xFF93A9B9',
      '0xFFF2F0EA',
      '0x8CF2F0EA',
      '0x59000000',
      '0x40FFFFFF',
    ];

    for (final String token in miniProgramPrivateTokens) {
      expect(source, contains(token), reason: '小程序页面私有 token $token 被改色');
    }
  });

  test('负控：硬编码黑白值必须能让相机门禁变红', () {
    const String mutation = '''
      color: Colors.black,
      foregroundColor: Colors.white,
      overlay: Colors.black87,
    ''';

    expect(_appearanceLockedColors(mutation), <String>[
      'Colors.black',
      'Colors.white',
      'Colors.black87',
    ]);
    expect(_appearanceLockedColors('color: Colors.transparent'), isEmpty);
  });
}
