import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/pricing.dart';
import '../auth/login_gate.dart';

/// 确认终价并开售。对齐小程序 `pages/topic/pricing`。
///
/// ★ 资金路径:确认之后主题就开售了。所以
///   ① 地板算不出来就整页挡住,不给一个「看起来能用」的界面;
///   ② 「确认」按钮的判据只有一个 —— 终价不低于成本地板。
///
/// ★ 恒浅(D6③ + 小程序真源):`pages/topic/pricing/index.wxml` 根节点是
///   `theme-merchant`(index.wxss 第 1 行 `@import merchant-light.wxss`),
///   路由侧由 `_merchantLight` 包着(app_router.dart)。所以本页的颜色**一律**
///   走 `CyPalette.of(context)` —— `CyTokens.*` 是暗色编译期常量,在这页会是
///   「白底黑卡」。门禁:`light_pages_no_static_colors_test.dart`。
class TopicPricingPage extends ConsumerStatefulWidget {
  const TopicPricingPage({super.key, required this.topicId});

  final int topicId;

  @override
  ConsumerState<TopicPricingPage> createState() => _TopicPricingPageState();
}

/// 失败原因 → 用户可读的短句。**分档**与小程序 `pages/topic/pricing/index.js` 一致:
/// 后端业务拒绝(HTTP 200 + code≠200 的 msg、[PricingIncompleteException])说的是
/// 用户能懂的一句中文,照原话放行;承载层异常([DioException])只说场景兜底 ——
/// 它的 toString 里是英文堆栈 + MDN 链接,画到屏幕上就是 b1-sim-topic 的 tp-03。
///
/// 只放行「像业务文案」的:一句短中文。含换行 / 链接 / 超长的一律兜底 ——
/// 小程序侧由 `utils/transport/safe-user-message.js` 做同一件事(这里不整段移植
/// 它那套正则,见 QUESTIONS)。
String _failureMessage(Object error) {
  if (error is DioException) return '网络异常，请稍后重试';
  final String text = error.toString().replaceFirst('Exception: ', '').trim();
  final bool looksLikeCopy =
      text.isNotEmpty &&
      text.length <= 60 &&
      !text.contains('\n') &&
      !text.contains('http');
  return looksLikeCopy ? text : '网络异常，请稍后重试';
}

class _TopicPricingPageState extends ConsumerState<TopicPricingPage> {
  PricingSubType _subType = PricingSubType.guided;
  final _costCtrl = TextEditingController();
  final _teamCtrl = TextEditingController();

  PricingPreview? _preview;
  double _finalPrice = 0;
  bool _loading = true;
  bool _saving = false;

  /// 失败原因(用户可读的短句,**永远不是异常原文**)。
  String? _error;
  String? _submitError;

  /// 这次失败是「后端要登录」而不是故障(判据 [isUnauthorizedError])。
  bool _needLogin = false;

  /// 阵容名称补齐:`toType:toId` → 公开档案换出的名字。换不到就留兜底名。
  final Map<String, String> _lineupNames = <String, String>{};

  @override
  void initState() {
    super.initState();
    // 没有主题 id 就不打接口(深链 /topic/abc/pricing 会落到 0)。
    if (widget.topicId > 0) _load();
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _teamCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await ref
          .read(topicApiProvider)
          .pricingPreview(
            topicId: widget.topicId,
            subType: _subType,
            leadCost: double.tryParse(_costCtrl.text.trim()),
            teamSize: int.tryParse(_teamCtrl.text.trim()),
          );
      if (!mounted) return;
      setState(() {
        _preview = p;
        // 每次重算都把终价拉回下界 —— 换了子类型/成本,旧终价对新地板可能已经违规。
        _finalPrice = p.sliderMin.toDouble();
        _loading = false;
      });
      _resolveLineupNames(p);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _needLogin = isUnauthorizedError(e);
        // 401 走登录引导,不填这句话 —— 它只在非 401 分支被读。
        _error = _needLogin ? null : _failureMessage(e);
        // 刷新失败**不抹掉旧预览**(小程序 hasPreview 时只出一条 inline error):
        // 把已经算好的地板/终价整屏换成错误页,人会以为数据没了。
        // 401 例外 —— 那时必须整屏引导登录,旧预览留着反而挡住登录入口。
        if (_needLogin) _preview = null;
        _loading = false;
      });
    }
  }

  /// 与小程序定价页一致:preview 只回 `toType/toId`,名字逐行找公开档案要,
  /// 按 `toType:toId` 缓存、失败静默 —— 名称只是点缀,不该挡定价主路径。
  void _resolveLineupNames(PricingPreview preview) {
    for (final PricingLineupRow row in preview.lineup) {
      final String key = '${row.toType}:${row.toId}';
      if (_lineupNames.containsKey(key)) continue;
      unawaited(() async {
        try {
          final String? raw = row.toType == 'club'
              ? (await ref.read(clubApiProvider).detail(row.toId)).name
              : (await ref.read(roamApiProvider).publicMerchantDetail(row.toId))
                    .$1
                    .name;
          final String name = raw?.trim() ?? '';
          if (name.isEmpty) return;
          if (!mounted || !identical(_preview, preview)) return;
          setState(() => _lineupNames[key] = name);
        } catch (_) {
          // 静默:见上。
        }
      }());
    }
  }

  Future<void> _confirm() async {
    final p = _preview;
    if (p == null || !p.canConfirm(_finalPrice) || _saving) return;
    setState(() {
      _saving = true;
      _submitError = null;
    });
    try {
      await ref
          .read(topicApiProvider)
          .pricingConfirm(
            topicId: widget.topicId,
            subType: _subType,
            finalPrice: _finalPrice,
            leadCost: double.tryParse(_costCtrl.text.trim()),
            teamSize: int.tryParse(_teamCtrl.text.trim()),
          );
      if (!mounted) return;
      // 后端只推进到 PRICING,开售要运营在后台再审一次 —— 不能谎报「已开售」。
      CyNativeNotice.show(context, '终价已确认，请等待开售审核');
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      // 与 _load 同一分档 —— 这里同样是资金路径,原始 DioException 不能进
      // inline 错误文案。
      final String message = isUnauthorizedError(e)
          ? '登录状态已失效，请重新登录'
          : _failureMessage(e);
      setState(() => _submitError = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('确认终价')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: widget.topicId <= 0
              // 小程序 `cy-empty kind="missing-param"`:深链没带主题参数时
              // 说清缺什么,而不是把一个打不通的接口错误端给用户。
              ? const StatusView(
                  message: '缺少主题信息',
                  sub: '当前链接没有携带主题参数，无法确认终价。',
                  large: true,
                )
              : _loading && _preview == null
              ? const Center(child: CupertinoActivityIndicator())
              : (_preview == null ? _errorState() : _body(_preview!)),
        ),
      ),
    );
  }

  /// 失败态。★ 401 与故障分开说:游客(以及 App Store 审核员)点进这页必撞 401
  /// (生产实测 `POST /api/topic/pricing/preview` → 401),而这是一条资金路径,
  /// 「网络异常 + 重试」会让人以为再点一次就好 —— 其实永远好不了。
  Widget _errorState() {
    if (_needLogin) {
      return StatusView(
        message: '登录后确认终价',
        sub: '这一步需要登录,登录完会自动回到这一页。',
        icon: CupertinoIcons.lock,
        large: true,
        retryLabel: '去登录',
        onRetry: () async {
          if (!await requireLogin(context, ref)) return;
          await _load();
        },
      );
    }
    return StatusView(
      message: '定价信息加载失败',
      sub: _error,
      large: true,
      onRetry: _load,
    );
  }

  Widget _body(PricingPreview p) {
    final CyPalette palette = CyPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final canConfirm = p.canConfirm(_finalPrice);
    final delta = p.deltaText(_finalPrice);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(CyTokens.pageX),
            children: <Widget>[
              // 刷新的两态(小程序 pg-refreshing / cy-inline-error)。
              if (_loading)
                Semantics(
                  liveRegion: true,
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: CyTokens.space2),
                    child: Text('正在核对最新定价…'),
                  ),
                ),
              if (_error != null)
                _InlineError(title: '最新定价暂未取回', sub: _error!, onAction: _load),
              // 分段控件走共用层 CyTabs:26+ 是原生分段,旧系统回退同一套
              // Cupertino 分段(几何/配色与相邻页面一致),并补齐 44pt 触达区。
              CyTabs(
                key: const Key('pricing-sub-type'),
                variant: CyTabsVariant.segmented,
                tabs: <CyTab>[
                  for (final PricingSubType t in PricingSubType.values)
                    CyTab(key: t.name, label: t.label),
                ],
                active: _subType.name,
                onChanged: (String value) {
                  final PricingSubType type = PricingSubType.values.byName(
                    value,
                  );
                  if (type == _subType) return;
                  setState(() => _subType = type);
                  _load();
                },
              ),
              if (_subType == PricingSubType.guided) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const CySectionTitle('带队成本'),
                      const SizedBox(height: CyTokens.space2),
                      CupertinoTextField(
                        controller: _costCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        placeholder: '本团带队总成本',
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: _fieldDecoration(palette),
                      ),
                      const SizedBox(height: CyTokens.space2),
                      CupertinoTextField(
                        controller: _teamCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        placeholder: '成团人数',
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: _fieldDecoration(palette),
                      ),
                      const SizedBox(height: CyTokens.space2),
                      CupertinoButton(
                        onPressed: _load,
                        color: palette.bgSurfaceSubtle,
                        child: const Text('重新计算地板'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: CyTokens.space3),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '乙-2 成本地板',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      '¥${p.priceMin.toStringAsFixed(2)}',
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      '平台率、发起人预估保底、分成型比例和固定成本已计入;终价不可低于此值。',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text('你的终价', style: textTheme.titleMedium),
                        Text(
                          '¥${_finalPrice.toStringAsFixed(0)}',
                          style: textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    CupertinoSlider(
                      min: p.sliderMin.toDouble(),
                      max: p.sliderMax.toDouble(),
                      value: _finalPrice.clamp(
                        p.sliderMin.toDouble(),
                        p.sliderMax.toDouble(),
                      ),
                      onChanged: (double v) =>
                          setState(() => _finalPrice = v.roundToDouble()),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '地板 ¥${p.priceMin.toStringAsFixed(0)}',
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        Text(
                          '¥${p.sliderMax}',
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      p.referenceText,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    if (delta.isNotEmpty)
                      Text(delta, style: textTheme.bodySmall),
                  ],
                ),
              ),
              if (p.lineup.isNotEmpty) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const CySectionTitle('合作阵容'),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        '阵容已锁定，点开可查该合作方在本主题中的结算条款。',
                        style: textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                      for (final PricingLineupRow row in p.lineup)
                        _LineupRow(
                          row: row,
                          name: _lineupNames['${row.toType}:${row.toId}'] ?? '',
                          onTap: () => context.push(
                            Uri(
                              path: '/topic/pricing/partner',
                              queryParameters: <String, String>{
                                'topicId': '${widget.topicId}',
                                'toType': row.toType,
                                'toId': '${row.toId}',
                              },
                            ).toString(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: CyTokens.space3),
              Text(
                '终价高出成本地板的部分就是发起人毛利;结算保底只按本场真实核销商家数激活。',
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space2,
              CyTokens.pageX,
              CyTokens.space3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_submitError != null)
                  _InlineError(
                    title: '终价确认失败',
                    sub: _submitError!,
                    onAction: _confirm,
                  ),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    onPressed: (!canConfirm || _saving) ? null : _confirm,
                    // 主 CTA 用调色板:恒浅页(action-primary 浅端是黑底白字),
                    // 写死暗端常量会在白底上留下一颗白按钮。
                    color: palette.actionPrimaryBg,
                    disabledColor: palette.bgSurfaceSubtle,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CupertinoActivityIndicator(),
                          )
                        : Text(
                            '确认终价并开售',
                            style: TextStyle(
                              color: canConfirm
                                  ? palette.actionPrimaryFg
                                  : palette.textPlaceholder,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

BoxDecoration _fieldDecoration(CyPalette palette) => BoxDecoration(
  color: palette.inputBgEmpty,
  borderRadius: BorderRadius.circular(CyTokens.radiusSm),
  border: Border.all(color: palette.borderSubtle),
);

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: child,
    );
  }
}

/// 页内错误条(小程序 `cy-inline-error`):说清哪一块失败 + 一个重试入口。
///
/// 刷新失败与提交失败都用它 —— 这两种情况下页面本身还在,
/// 弹 toast 会飘走、也不给人重试的落点。
class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.title,
    required this.sub,
    required this.onAction,
  });

  final String title;
  final String sub;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    // 恒浅页(路由 `_merchantLight`):暗端常量在白底上对比度不足,取调色板双值。
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    title,
                    style: CyType.footnote.copyWith(
                      color: palette.statusWarning,
                    ),
                  ),
                ),
                Text(
                  sub,
                  style: CyType.caption1.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
            minimumSize: const Size(44, 44),
            onPressed: onAction,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 阵容一行:名字(真名没换到之前用兜底名)+ 条款摘要 + 箭头 → partner 页。
class _LineupRow extends StatelessWidget {
  const _LineupRow({
    required this.row,
    required this.name,
    required this.onTap,
  });

  final PricingLineupRow row;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return CupertinoButton(
      key: Key('lineup-${row.toType}-${row.toId}'),
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name.isEmpty ? row.fallbackName : name,
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  row.termsText,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          const Icon(CupertinoIcons.chevron_forward, size: 16),
        ],
      ),
    );
  }
}
