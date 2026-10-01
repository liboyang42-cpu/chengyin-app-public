import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';

/// 商家承接设置。可见字段、顺序和保存后返回均以小程序为真源。
///
/// `suitActivityTypes` 与 `coopOpen` 同属全量覆盖接口，但不属于这一页的
/// 可见入口；读取后原样带回，避免保存四项时意外清空其它页面的设置。
final coopProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) {
  return ref.read(merchantApiProvider).coopProfile();
});

class MerchantCoopProfilePage extends ConsumerStatefulWidget {
  const MerchantCoopProfilePage({super.key});

  @override
  ConsumerState<MerchantCoopProfilePage> createState() =>
      _MerchantCoopProfilePageState();
}

class _MerchantCoopProfilePageState
    extends ConsumerState<MerchantCoopProfilePage> {
  final TextEditingController _capacity = TextEditingController();
  final TextEditingController _availableTime = TextEditingController();
  final TextEditingController _demand = TextEditingController();

  String? _suitActivityTypes;
  int? _coopOpen;
  int? _chargeType;

  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _capacity.dispose();
    _availableTime.dispose();
    _demand.dispose();
    super.dispose();
  }

  void _fill(Map<String, dynamic> m) {
    if (_loaded) return;
    _loaded = true;
    _capacity.text = (m['capacity'] ?? '').toString();
    _availableTime.text = (m['availableTime'] ?? '').toString();
    _demand.text = (m['demand'] ?? '').toString();
    _suitActivityTypes = m['suitActivityTypes']?.toString();

    final Object? rawCoopOpen = m['coopOpen'];
    _coopOpen = rawCoopOpen is num ? rawCoopOpen.toInt() : null;

    final Object? rawChargeType = m['chargeType'];
    final int? parsedCharge = rawChargeType is num
        ? rawChargeType.toInt()
        : null;
    _chargeType = parsedCharge == 0 || parsedCharge == 1 ? parsedCharge : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final String capacityText = _capacity.text.trim();
    final int? capacity = capacityText.isEmpty
        ? null
        : int.tryParse(capacityText);
    if (capacityText.isNotEmpty && (capacity == null || capacity < 0)) {
      setState(() => _error = stringsOf(context).merchantDirectoryCapacityInvalid);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final String msg = await ref
          .read(merchantApiProvider)
          .saveCoopProfile(
            capacity: capacity,
            availableTime: _availableTime.text.trim(),
            suitActivityTypes: _suitActivityTypes,
            chargeType: _chargeType,
            demand: _demand.text.trim(),
            coopOpen: _coopOpen,
          );
      ref.invalidate(coopProfileProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on MerchantApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(coopProfileProvider);
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantDirectorySettings)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const CySkeleton(),
            error: (Object e, StackTrace st) => StatusView(
              icon: CupertinoIcons.exclamationmark_triangle,
              message: stringsOf(context).merchantDirectorySettingsFailed,
              sub: e.toString().replaceFirst('Exception: ', ''),
              large: true,
              onRetry: () => ref.invalidate(coopProfileProvider),
              retryLabel: stringsOf(context).merchantDirectoryReload,
            ),
            data: (Map<String, dynamic> m) {
              if (m.isEmpty) {
                return StatusView(
                  message: stringsOf(context).merchantDirectorySettingsUnavailable,
                  sub: stringsOf(context).merchantDirectorySettingsNoStore,
                  large: true,
                  onRetry: () => context.push('/merchant/apply'),
                  retryLabel: stringsOf(context).merchantDirectoryApply,
                );
              }
              _fill(m);
              return _form(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.space4,
          0,
          CyTokens.space4,
          CyTokens.space3,
        ),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.space3_5,
              CyTokens.space1,
              CyTokens.space3_5,
              CyTokens.space3_5,
            ),
            decoration: BoxDecoration(
              color: palette.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              border: Border.all(color: palette.cardBorder),
              boxShadow: palette.cardShadow,
            ),
            child: Column(
              children: <Widget>[
                _field(
                  _capacity,
                  stringsOf(context).merchantDirectoryCapacity,
                  hint: stringsOf(context).merchantDirectoryCapacityHint,
                  keyboard: TextInputType.number,
                ),
                _field(_availableTime, stringsOf(context).merchantDirectoryAvailability, hint: stringsOf(context).merchantDirectoryAvailabilityHint),
                _chargeTypeField(palette, textTheme),
                _field(_demand, stringsOf(context).merchantDirectoryGoals, hint: stringsOf(context).merchantDirectoryGoalsHint),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              _error!,
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space5),
          SizedBox(
            width: double.infinity,
            height: CyTokens.btnH,
            child: CupertinoButton.filled(
              key: const Key('merchant-coop-save'),
              onPressed: _saving ? null : _save,
              padding: EdgeInsets.zero,
              child: Text(_saving ? stringsOf(context).merchantDirectorySaving : stringsOf(context).merchantDirectorySaveSettings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chargeTypeField(CyPalette palette, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            stringsOf(context).merchantDirectoryChargeType,
            style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: CyTokens.space1_5),
          SizedBox(
            height: 44,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _chargeType,
              children: <int, Widget>{
                0: Center(child: Text(stringsOf(context).merchantDirectoryFreeHosting)),
                1: Center(child: Text(stringsOf(context).merchantDirectoryPaidHosting)),
              },
              onValueChanged: (int? value) {
                if (value != null) setState(() => _chargeType = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: CyTokens.space1_5),
          CupertinoTextField(
            controller: controller,
            minLines: maxLines,
            maxLines: maxLines,
            keyboardType: keyboard,
            placeholder: hint,
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: CyTokens.space2,
            ),
            decoration: BoxDecoration(
              color: CyPalette.of(context).inputBgEmpty,
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
            ),
          ),
        ],
      ),
    );
  }
}
