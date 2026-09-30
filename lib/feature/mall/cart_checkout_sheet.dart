import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/address_api.dart';
import '../../data/models/product.dart';
import '../account/address_list_page.dart';
import 'mall_controller.dart';

/// Apple 原生积分兑换确认 Sheet。
///
/// 服务端预览是金额与默认地址的真源；地址列表只用于在用户自己的地址中切换。
class CartCheckoutSheet extends ConsumerStatefulWidget {
  const CartCheckoutSheet({
    super.key,
    required this.preview,
    required this.cartIds,
    required this.scrollController,
    this.onCompleted,
  });

  final CartSettlementPreview preview;
  final List<int> cartIds;
  final ScrollController scrollController;
  final ValueChanged<int>? onCompleted;

  @override
  ConsumerState<CartCheckoutSheet> createState() => _CartCheckoutSheetState();
}

class _CartCheckoutSheetState extends ConsumerState<CartCheckoutSheet> {
  final TextEditingController _remarkController = TextEditingController();
  int? _selectedAddressId;
  int? _completedOrderId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedAddressId = widget.preview.address?.id;
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  List<MemberAddress> _eligible(List<MemberAddress> rows) => rows
      .where((MemberAddress address) => address.id > 0 && address.hasAddress)
      .toList(growable: false);

  int? _effectiveAddressId(List<MemberAddress> rows) {
    final List<MemberAddress> eligible = _eligible(rows);
    final int? selected = _selectedAddressId;
    if (selected != null &&
        eligible.any((MemberAddress address) => address.id == selected)) {
      return selected;
    }
    if (eligible.isNotEmpty) return eligible.first.id;
    final SettlementAddress? previewAddress = widget.preview.address;
    if (previewAddress != null && previewAddress.oneLine.isNotEmpty) {
      return previewAddress.id;
    }
    return null;
  }

  Future<void> _submit(List<MemberAddress> rows) async {
    if (_submitting) return;
    final int? addressId = _effectiveAddressId(rows);
    if (addressId == null ||
        widget.preview.totalAmount == null ||
        widget.preview.hasEnoughPoints == false) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final int orderId = await ref
          .read(mallApiProvider)
          .settleOrder(
            cartIds: widget.cartIds,
            remark: _remarkController.text.trim(),
            addressId: addressId,
          );
      if (!mounted) return;
      ref.invalidate(cartListProvider);
      setState(() {
        _completedOrderId = orderId;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted && _submitting) setState(() => _submitting = false);
    }
  }

  void _finishSuccess() {
    final int? orderId = _completedOrderId;
    if (orderId == null) return;
    final ValueChanged<int>? completed = widget.onCompleted;
    if (completed != null) {
      completed(orderId);
    } else {
      Navigator.of(context).pop(orderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? completedOrderId = _completedOrderId;
    if (completedOrderId != null) {
      return _MallCheckoutSuccess(
        orderId: completedOrderId,
        onDone: _finishSuccess,
      );
    }
    final AsyncValue<List<MemberAddress>> addresses = ref.watch(
      addressListProvider,
    );
    final List<MemberAddress> rows = addresses.value ?? const [];
    final List<MemberAddress> eligible = _eligible(rows);
    final int? effectiveAddressId = _effectiveAddressId(rows);
    final CyPalette palette = CyPalette.of(context);
    final bool insufficient = widget.preview.hasEnoughPoints == false;
    final bool unknownTotal = widget.preview.totalAmount == null;
    final bool canSubmit =
        !_submitting &&
        !insufficient &&
        !unknownTotal &&
        effectiveAddressId != null;

    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(
            0,
            CyTokens.space2,
            0,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
              child: Text(
                '确认兑换',
                style: CyType.title2.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            CupertinoFormSection.insetGrouped(
              backgroundColor: palette.bgPage,
              header: const Text('积分明细'),
              children: <Widget>[
                _SummaryRow(
                  label: '商品积分',
                  value: formatPoints(widget.preview.productAmount),
                ),
                _SummaryRow(
                  label: '运费',
                  value: formatPoints(widget.preview.deliveryFee),
                ),
                _SummaryRow(
                  label: '税费',
                  value: formatPoints(widget.preview.taxFee),
                ),
                _SummaryRow(
                  label: '需要',
                  value: widget.preview.requiredPoints == null
                      ? '积分待确认'
                      : '需要 ${widget.preview.requiredPoints} 积分',
                  emphasize: true,
                ),
                _SummaryRow(
                  label: '当前积分',
                  value: widget.preview.pointBalance == null
                      ? '提交时由服务端校验'
                      : '当前 ${formatPoints(widget.preview.pointBalance)}',
                  valueColor: insufficient ? palette.statusDanger : null,
                ),
              ],
            ),
            CupertinoFormSection.insetGrouped(
              backgroundColor: palette.bgPage,
              header: const Text('收货地址'),
              footer: addresses.hasError
                  ? const Text('地址列表暂时没读出来，可管理地址后重试。')
                  : null,
              children: <Widget>[
                if (eligible.isEmpty)
                  addresses.isLoading
                      ? const SizedBox(height: 56, child: LoadingView())
                      : _PreviewOrEmptyAddress(address: widget.preview.address)
                else
                  for (final MemberAddress address in eligible)
                    _AddressChoice(
                      address: address,
                      selected: address.id == effectiveAddressId,
                      onPressed: _submitting
                          ? null
                          : () =>
                                setState(() => _selectedAddressId = address.id),
                    ),
                CupertinoButton(
                  key: const Key('mall-checkout-manage-address'),
                  minimumSize: const Size(44, 44),
                  alignment: Alignment.centerLeft,
                  onPressed: _submitting
                      ? null
                      : () async {
                          await context.push('/address');
                          ref.invalidate(addressListProvider);
                        },
                  child: const Text('管理收货地址'),
                ),
              ],
            ),
            CupertinoFormSection.insetGrouped(
              backgroundColor: palette.bgPage,
              header: const Text('订单备注'),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  child: Semantics(
                    textField: true,
                    label: '订单备注',
                    child: CupertinoTextField(
                      key: const Key('mall-checkout-remark'),
                      controller: _remarkController,
                      enabled: !_submitting,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 200,
                      textInputAction: TextInputAction.done,
                      placeholder: '选填，例如配送时间',
                      padding: const EdgeInsets.all(CyTokens.space3),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
              child: CyNativeButton(
                key: const Key('mall-checkout-confirm'),
                label: _checkoutLabel(
                  insufficient: insufficient,
                  unknownTotal: unknownTotal,
                  hasAddress: effectiveAddressId != null,
                ),
                onPressed: canSubmit ? () => _submit(rows) : null,
                loading: _submitting,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _checkoutLabel({
    required bool insufficient,
    required bool unknownTotal,
    required bool hasAddress,
  }) {
    if (_submitting) return '正在兑换';
    if (!hasAddress) return '请选择收货地址';
    if (unknownTotal) return '积分待确认';
    if (insufficient) return '积分不足';
    return '确认兑换';
  }
}

class _MallCheckoutSuccess extends StatelessWidget {
  const _MallCheckoutSuccess({required this.orderId, required this.onDone});

  final int orderId;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Semantics(
                label: '兑换成功',
                image: true,
                child: Icon(
                  CupertinoIcons.check_mark_circled_solid,
                  size: 72,
                  color: palette.actionPrimaryBg,
                ),
              ),
              const SizedBox(height: CyTokens.space4),
              Text(
                '兑换成功',
                style: CyType.title2.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                '订单编号：$orderId',
                style: CyType.body.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                '积分已扣除，商品将按所选收货信息处理。',
                textAlign: TextAlign.center,
                style: CyType.body.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: CyTokens.space5),
              CyNativeButton(
                key: const Key('mall-checkout-success-done'),
                label: '继续逛商城',
                onPressed: onDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      child: Row(
        children: <Widget>[
          Text(label, style: CyType.body),
          const Spacer(),
          Text(
            value,
            style: CyType.body.copyWith(
              color: valueColor,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressChoice extends StatelessWidget {
  const _AddressChoice({
    required this.address,
    required this.selected,
    required this.onPressed,
  });

  final MemberAddress address;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${address.fullName}，${address.oneLine}',
      child: CupertinoButton(
        key: Key('mall-checkout-address-${address.id}'),
        minimumSize: const Size(44, 56),
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3,
          vertical: CyTokens.space2,
        ),
        alignment: Alignment.centerLeft,
        onPressed: onPressed,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${address.fullName}  ${address.mobilePhone}',
                    style: CyType.body.copyWith(color: palette.textPrimary),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    address.oneLine,
                    style: CyType.subhead.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: palette.actionPrimaryBg,
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewOrEmptyAddress extends StatelessWidget {
  const _PreviewOrEmptyAddress({required this.address});

  final SettlementAddress? address;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final SettlementAddress? row = address;
    final bool usable = row != null && row.oneLine.isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: usable
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${row.fullName}  ${row.mobilePhone}',
                    style: CyType.body.copyWith(color: palette.textPrimary),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    row.oneLine,
                    style: CyType.subhead.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              )
            : Text(
                '还没有可用的收货地址',
                style: CyType.body.copyWith(color: palette.textSecondary),
              ),
      ),
    );
  }
}
