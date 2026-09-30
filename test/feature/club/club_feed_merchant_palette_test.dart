import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 俱乐部根页商家视角(AppTheme.merchantLight 作用域)会复用 ClubPostTile。
/// 卡面取色必须随主题走 CyPalette —— 静态 CyTokens 暗色常量在商家浅底上
/// 就是一张黑卡(a5-ios27-club-2 复核漏网,V3/C4)。
void main() {
  Future<void> pumpTile(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          home: Theme(
            data: brightness == Brightness.light
                ? AppTheme.merchantLight()
                : AppTheme.dark(),
            child: CupertinoPageScaffold(
              child: ClubPostTile(post: const ClubPost(id: 1, nickname: '主理人')),
            ),
          ),
        ),
      ),
    );
  }

  Color tileSurface(WidgetTester tester) {
    final containers = tester.widgetList<Container>(find.byType(Container));
    for (final c in containers) {
      final dec = c.decoration;
      if (dec is BoxDecoration && dec.color != null) return dec.color!;
    }
    throw StateError('帖卡容器未渲染');
  }

  testWidgets('商家浅色作用域下帖卡底色/描边用浅色 palette,不是恒暗常量',
      (tester) async {
    await pumpTile(tester, Brightness.light);
    final surface = tileSurface(tester);
    expect(surface, CyPalette.light.bgSurface);
    expect(surface, isNot(CyTokens.bgSurface));
  });

  testWidgets('玩家恒暗作用域下帖卡底色不变(暗值与 CyTokens 同值)',
      (tester) async {
    await pumpTile(tester, Brightness.dark);
    expect(tileSurface(tester), CyPalette.dark.bgSurface);
    expect(tileSurface(tester), CyTokens.bgSurface);
  });
}
