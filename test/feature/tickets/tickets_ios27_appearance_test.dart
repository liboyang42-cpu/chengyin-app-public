// 票夹 / 核销码域 A5 iOS 27 外观复核的回归钉(a5-ios27-tickets)。
// 钉的是「外观偏差被修好且不再回来」:核销码倒计时的语义色、
// 以及本域**不读暗色编译期常量**这条口径。
// 真源:`components/cy/qr-voucher/index.wxss` · `style/tokens.wxss`(码卡物理浅色 ds-ok 豁免)。
// (原「分段控件取色/动态字号」三钉随 P2-1 删 tab 一并撤下 —— 控件本体已不存在。)
import 'dart:io';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/tickets/explore_completion_section.dart';
import 'package:chengyin_app/feature/tickets/pass_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design/scan_support.dart';
import '../../support/fixed_auth.dart';

const List<String> _ticketsSources = <String>[
  'lib/feature/tickets/tickets_page.dart',
  'lib/feature/tickets/pass_page.dart',
  'lib/feature/tickets/ticket_detail_page.dart',
  'lib/feature/tickets/explore_completion_section.dart',
];

/// 手册 §3.6:新代码一律 `CyPalette.of(context)`;`CyTokens.*` 颜色常量与
/// `AppColors` 是暗色编译期常量/冻结别名层,在浅色外观上直接错值。
final RegExp _staticColor = RegExp(
  r'AppColors\.|CyTokens\.(bg|text|border|status|brand|state|overlay|input)\w',
);

void main() {
  test('本域取色一律 CyPalette,不读暗色编译期常量与旧别名层', () {
    for (final String path in _ticketsSources) {
      final List<String> hits = _hitsIn(path);
      expect(hits, isEmpty, reason: '$path 仍在取静态色');
    }
  });

  test('负控:上述口径真能红(合成源码里的违规必须被扫到)', () {
    expect(_hitsOf('color: AppColors.bgPage,'), isNotEmpty);
    expect(_hitsOf('color: CyTokens.textTertiary,'), isNotEmpty);
    // 注释里的反例不算违规(剥注释口径同 test/design)。
    expect(_hitsOf('// color: AppColors.bgPage'), isEmpty);
  });

  test('码卡是物理浅色:字面量只许集中在带真源出处的豁免常量里', () {
    // 去空白再扫:`dart format` 会把长声明折行,逐行匹配会漏掉折行的字面量。
    final String passPage = _codeWithoutWhitespace(_passPagePath);
    expect(
      _colorLiterals.allMatches(passPage).length,
      4,
      reason: '本域色字面量只豁免在码卡这一处',
    );
    expect(
      RegExp(r'constColor_kQrCard\w+=Color\(0x').allMatches(passPage).length,
      4,
      reason: '每个字面量都必须挂在具名 _kQrCard* 常量上,不许散落成行内色',
    );
    for (final String path in _ticketsSources) {
      if (path == _passPagePath) continue;
      expect(
        _colorLiterals.allMatches(_codeWithoutWhitespace(path)).length,
        0,
        reason: '$path 不在物理浅色豁免内,不许出现色字面量',
      );
    }
  });

  _ticketsRound2Pins();
}

const String _passPagePath = 'lib/feature/tickets/pass_page.dart';

// ── 本轮(a5-ios27-tickets-2)补差的回归钉 ────────────────────────────────

/// 倒计时每秒重算 `DateTime.now()`,测试里钉死才拿得到稳定断言。
class _FixedDynCode extends DynCode {
  _FixedDynCode({
    required super.code,
    required super.expiresAt,
    super.qrcodeUrl,
  });

  @override
  Duration remaining() => const Duration(minutes: 5);
}

class _FakeActivityApi extends ActivityApi {
  _FakeActivityApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<DynCode> issueDynamicCode(int registrationId) async => _FixedDynCode(
    code: 'CY.9001.activity.aB3xQ7',
    expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
    qrcodeUrl: null, // 无图 → 直接进回落态,一并把回落排版钉住
  );
}

class _FakeRegistrationApi implements RegistrationApi {
  @override
  Future<Map<String, dynamic>> exploreCompletion(int id) async =>
      <String, dynamic>{
        'completed': true,
        'requiredChapterCount': 1,
        'redeemedChapterCount': 1,
        'awards': <String, dynamic>{
          'credited': true,
          'items': <dynamic>[
            <String, dynamic>{'kind': 'POINTS', 'title': '积分', 'amount': 120},
          ],
        },
      };

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void _ticketsRound2Pins() {
  testWidgets(
    '出示核销码页字级逐值 = 真源:指令 16/600、倒计时 caption 11/400、回落码 page-title 29',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signedInAuthOverride(),
            activityApiProvider.overrideWithValue(_FakeActivityApi()),
          ],
          child: const MaterialApp(home: PassPage(registrationId: 9001)),
        ),
      );
      await tester.pump();
      await tester.pump();

      final TextStyle instruction = tester
          .widget<Text>(find.text('请把此码交给商家核销'))
          .style!;
      expect(
        instruction.fontSize,
        16,
        reason: '真源 .qr__title = subtitle 档 32rpx',
      );
      expect(instruction.fontWeight, FontWeight.w600);

      final TextStyle count = tester
          .widget<Text>(find.textContaining('后过期'))
          .style!;
      expect(
        count.fontSize,
        11,
        reason: '真源 .qr__count = caption 档 22rpx(HIG 下限档)',
      );
      expect(count.fontWeight, FontWeight.w400, reason: '真源该档不自带中粗');

      // SelectableText 渲染落点是 EditableText,样式挂在它身上。
      final TextStyle codeText = tester
          .widget<EditableText>(find.byType(EditableText))
          .style;
      expect(
        codeText.fontSize,
        29,
        reason: '真源 .qr__code-text = --cy-font-page-title 58rpx',
      );
      expect(codeText.fontWeight, FontWeight.w600);
      expect(codeText.letterSpacing, 4, reason: '真源 letter-spacing 8rpx');
      // 大字号必须仍被码区宽度消化(定宽换行,不是整列缩没):
      // 回落列宽 ≤ 220,渲染不出溢出。
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('完局面奖励金额取 brand 档(真源 .award-amount),不是自增的 success 绿', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          registrationApiProvider.overrideWithValue(_FakeRegistrationApi()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExploreCompletionSection(registrationId: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final TextStyle amount = tester.widget<Text>(find.text('+120')).style!;
    final CyPalette palette = CyPalette.dark;
    expect(amount.color, palette.brand);
    expect(amount.color, isNot(palette.statusSuccess), reason: '负控:回到旧偏差必须红');
  });
}

final RegExp _colorLiterals = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}');

/// 剥注释 + 压平空白(压平后 `const Color _kX = Color(0x…)` 恒等于一行)。
String _codeWithoutWhitespace(String path) =>
    codeOfFile(path).replaceAll(RegExp(r'\s+'), '');

List<String> _hitsOf(String source) {
  return _staticColor
      .allMatches(stripComments(source))
      .map((RegExpMatch m) => m.group(0)!)
      .toList();
}

List<String> _hitsIn(String path) => _hitsOf(File(path).readAsStringSync());
