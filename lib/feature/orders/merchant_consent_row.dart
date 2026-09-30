import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Card, Theme;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import 'marketing_consent_entry.dart';

/// 订单详情/报名结果弹层里的「商家消息」营销同意行。
/// 真源 = `components/cy/marketing-consent-entry`:
/// offer 静默加载(失败当没有)、按 `orderId:ownerMemberId` 只读一次、
/// 保存中不抖动、重试复用同一 requestId、退订去设置页。
/// [cardTitle] 非空时套一张卡片(订单详情的「商家消息」sec);没有 offer
/// 整块不渲染(真源 wx:if 挂在 sec 上,不是只藏行)。
class CyMerchantConsentRow extends ConsumerStatefulWidget {
  const CyMerchantConsentRow({
    super.key,
    required this.orderId,
    required this.ownerMemberId,
    this.cardTitle,
    this.onBusyChanged,
  });

  final int orderId;
  final int? ownerMemberId;
  final String? cardTitle;

  /// 支付结果面板用它:「勾了才停下等保存结果」—— consent 在保存中,
  /// 面板自愈关闭要先等这行落定。
  final ValueChanged<bool>? onBusyChanged;

  @override
  ConsumerState<CyMerchantConsentRow> createState() =>
      _CyMerchantConsentRowState();
}

enum _Mode { hidden, idle, saving, saved, failed }

class _CyMerchantConsentRowState extends ConsumerState<CyMerchantConsentRow> {
  /// 真源在 onLoad 拉一次并按 `id + ':' + ownerMemberId` 记键,onShow 刷新
  /// 不再重读 —— 这张表就是那个「记键」。null=查过、没有 offer。
  static final Map<String, ConsentOffer?> _offerCache =
      <String, ConsentOffer?>{};

  _Mode _mode = _Mode.hidden;
  ConsentOffer? _offer;
  String? _error;
  String? _requestId;

  String get _cacheKey => '${widget.orderId}:${widget.ownerMemberId ?? 0}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 商家 ownerMemberId 拿不到就没有 offer 可挑 —— 连查都不用查。
    if ((widget.ownerMemberId ?? 0) <= 0) return;
    final String key = _cacheKey;
    final ConsentOffer? cached = _offerCache[key];
    if (cached != null) {
      setState(() {
        _offer = cached;
        _mode = _Mode.idle;
      });
      return;
    }
    if (_offerCache.containsKey(key)) return;
    ConsentOffer? offer;
    try {
      offer = await loadConsentOffer(
        ref.read(pageParityApiProvider),
        widget.ownerMemberId,
      );
    } catch (_) {
      offer = null; // provider 本身起不来也照样静默。
    }
    _offerCache[key] = offer;
    if (offer != null && mounted) {
      setState(() {
        _offer = offer;
        _mode = _Mode.idle;
      });
    }
  }

  void _toggle(bool next) {
    if (_mode == _Mode.saving) return; // 在途不抖。
    if (next) {
      _submit();
    } else {
      // 退订在设置页做;这里取消勾选只收起成未同意。
      setState(() => _mode = _Mode.idle);
    }
  }

  Future<void> _submit() async {
    final ConsentOffer? offer = _offer;
    if (offer == null || _mode == _Mode.saving) return;
    setState(() {
      _mode = _Mode.saving;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    // 重试复用同一个 requestId:后端按它幂等,重放不会多落一条同意。
    _requestId ??= newConsentRequestId('order');
    final String? error = await submitConsent(
      ref.read(pageParityApiProvider),
      offer: offer,
      optedIn: true,
      requestId: _requestId!,
    );
    if (!mounted) {
      return;
    }
    widget.onBusyChanged?.call(false);
    if (error == null) {
      _offerCache[_cacheKey] = null;
      setState(() => _mode = _Mode.saved);
    } else {
      setState(() {
        _mode = _Mode.failed;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ConsentOffer? offer = _offer;
    if (offer == null) return const SizedBox.shrink();
    final bool checked = _mode == _Mode.saving || _mode == _Mode.saved;
    final String status = switch (_mode) {
      _Mode.saving => '正在保存…',
      _Mode.saved => '已同意，可在设置里随时退订',
      _Mode.failed => _error ?? '同意没有保存成功，请重试',
      _ => '',
    };
    final Widget row = Semantics(
      key: const Key('order-merchant-consent'),
      container: true,
      checked: checked,
      label: '接收「${offer.merchantName}」的活动消息',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: <Widget>[
            CupertinoCheckbox(
              value: checked,
              onChanged: (bool? value) => _toggle(value ?? false),
            ),
            const SizedBox(width: CyTokens.space2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '接收「${offer.merchantName}」的活动消息（站内消息，可随时在设置里退订）',
                    style: CyType.footnote,
                  ),
                  if (status.isNotEmpty)
                    Text(
                      status,
                      style: CyType.footnote.copyWith(
                        color: _mode == _Mode.failed
                            ? CyPalette.of(context).statusDanger
                            : CyPalette.of(context).textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (_mode == _Mode.failed)
              CupertinoButton(
                key: const Key('order-merchant-consent-retry'),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                ),
                onPressed: _submit,
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
    final String? title = widget.cardTitle;
    if (title == null) return row;
    return Card(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: CyTokens.space3),
            row,
          ],
        ),
      ),
    );
  }
}
