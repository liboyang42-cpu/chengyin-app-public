import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import 'badge_detail_logic.dart';

/// 徽章详情(对齐小程序 subpackageP3/pages/badge-3d)。
/// 小程序是 3D 珐琅转台 / 波点引擎;App 侧为静态展示卡。
class BadgeDetailPage extends StatelessWidget {
  const BadgeDetailPage({super.key, required this.params});

  final BadgeDetailParams params;

  /// 五档稀有度色 = 小程序真源 `subpackageP3/pages/badge-wall/index/index.js`:
  /// 轨道配色 `CAT_META`(status-success / text-secondary / status-warning /
  /// text-tertiary)+ 神话档特判 `b.rarity === 4 ? status-danger`。
  /// 原先是 App 自造的 5 个 hex(灰/蓝/紫/橙/红),既不在 token 里,也对不上真源。
  static List<Color> _tierColors(CyPalette p) => <Color>[
    p.statusSuccess, // 普通
    p.textSecondary, // 稀有
    p.statusWarning, // 史诗
    p.textTertiary, // 传说
    p.statusDanger, // 神话
  ];

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Color tierColor = _tierColors(palette)[params.rarity];
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('徽章')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CyTokens.pageX),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 200,
                    height: 200,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: tierColor, width: 3),
                      color: palette.bgElevated,
                    ),
                    child: params.img.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              params.img,
                              width: 188,
                              height: 188,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _fallbackIcon(tierColor),
                            ),
                          )
                        : _fallbackIcon(tierColor),
                  ),
                  const SizedBox(height: CyTokens.space5),
                  Text(
                    params.name,
                    textAlign: TextAlign.center,
                    // 真源 .b3__name:34rpx(17) w700 → Headline 档;
                    // 原先落 title2(22) 是把小程序没有的「详情大标题」规格加高了一档。
                    style: CyType.headline.copyWith(color: palette.textPrimary),
                  ),
                  if (params.sub.isNotEmpty) ...<Widget>[
                    const SizedBox(height: CyTokens.space1_5),
                    Text(
                      params.sub,
                      textAlign: TextAlign.center,
                      // 真源 .b3__sub:23rpx(11.5)+ #919191 → caption1 + text-secondary。
                      style: CyType.caption1.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: CyTokens.space3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3,
                      vertical: CyTokens.space1_5,
                    ),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    ),
                    child: Text(
                      params.tierName,
                      style: CyType.footnote.copyWith(color: tierColor),
                    ),
                  ),
                  if (params.isEnamel) ...<Widget>[
                    const SizedBox(height: CyTokens.space2_5),
                    Text(
                      '珐琅样式',
                      style: CyType.footnote.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      '当前环境显示静态徽章预览',
                      textAlign: TextAlign.center,
                      style: CyType.caption1.copyWith(
                        color: palette.textDisabled,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon(Color tierColor) {
    return Icon(CupertinoIcons.rosette, size: 96, color: tierColor);
  }
}
