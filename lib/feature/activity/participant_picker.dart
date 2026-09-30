import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/participant_api.dart';

/// 我的参与人列表。接口顺序就是小程序展示顺序，不在客户端重排。
final participantsProvider = FutureProvider.autoDispose<List<Participant>>((
  Ref ref,
) {
  return ref.watch(participantApiProvider).list();
});

/// 选择已保存的参与人；点选或新增成功都返回服务端真实对象，取消返回 null。
///
/// [preferNative] 只作为旧系统/MissingPlugin 负控缝。生产默认先尝试仓库已固定的
/// `mjn_liquid_ui` 原生 SwiftUI Form sheet；插件不可用时完整回退到 Cupertino。
Future<Participant?> pickParticipant(
  BuildContext context, {
  @visibleForTesting bool preferNative = true,
}) async {
  final List<Participant>? initialRows =
      await showCupertinoModalPopup<List<Participant>>(
        context: context,
        builder: (_) => const _ParticipantLoadSheet(),
      );
  if (initialRows == null || !context.mounted) return null;
  List<Participant> rows = initialRows;

  while (context.mounted) {
    _PickerAction action;
    if (preferNative) {
      if (!context.mounted) return null;
      final _NativePickerResult native = await _showNativePicker(context, rows);
      if (!context.mounted) return null;
      if (native.shown) {
        action = native.action ?? const _PickerAction.cancel();
      } else {
        action =
            await _showCupertinoPicker(context, rows) ??
            const _PickerAction.cancel();
      }
    } else {
      if (!context.mounted) return null;
      action =
          await _showCupertinoPicker(context, rows) ??
          const _PickerAction.cancel();
    }

    switch (action.type) {
      case _PickerActionType.cancel:
        return null;
      case _PickerActionType.select:
        return action.participant;
      case _PickerActionType.add:
        if (!context.mounted) return null;
        final Participant? created = await _editParticipant(context, rows);
        if (created != null || !context.mounted) return created;
        // 小程序从新增页返回列表会重新 getList；取消新增也回到选择层，而不是
        // 退出整条报名流程。这里同样刷新后继续选择。
        final List<Participant>? refreshed =
            await showCupertinoModalPopup<List<Participant>>(
              context: context,
              builder: (_) => const _ParticipantLoadSheet(forceRefresh: true),
            );
        if (refreshed == null || !context.mounted) return null;
        rows = refreshed;
    }
  }
  return null;
}

enum _PickerActionType { cancel, select, add }

class _PickerAction {
  const _PickerAction.cancel()
    : type = _PickerActionType.cancel,
      participant = null;

  const _PickerAction.select(this.participant)
    : type = _PickerActionType.select;

  const _PickerAction.add() : type = _PickerActionType.add, participant = null;

  final _PickerActionType type;
  final Participant? participant;
}

class _NativePickerResult {
  const _NativePickerResult({required this.shown, this.action});

  final bool shown;
  final _PickerAction? action;
}

Future<_NativePickerResult> _showNativePicker(
  BuildContext context,
  List<Participant> rows,
) async {
  _PickerAction? action;
  try {
    final bool shown = await AppleLiquidSheet.showSheet(
      scrollContext: context,
      heightFraction: 0.82,
      backgroundZoomScale: MediaQuery.disableAnimationsOf(context) ? 1 : 0.96,
      content: AppleLiquidSheetContent(
        title: '选择参与人信息',
        trailingAction: const AppleLiquidSheetToolbarAction(
          title: '取消',
          semanticLabel: '取消选择参与人信息',
        ),
        detents: const AppleLiquidSheetDetents(
          initialHeight: 420,
          expandedHeight: 680,
        ),
        sections: <AppleLiquidSheetSection>[
          if (rows.isEmpty)
            const AppleLiquidSheetSection(
              rows: <AppleLiquidSheetRow>[
                AppleLiquidSheetRow.text(
                  title: '暂无参与人信息',
                  subtitle: '新增后可在报名时直接选用',
                  systemImage: 'person.crop.circle.badge.questionmark',
                ),
              ],
            )
          else
            AppleLiquidSheetSection(
              rows: rows
                  .map(
                    (Participant participant) => AppleLiquidSheetRow.button(
                      title: participant.fullName,
                      subtitle: participant.maskedPhone,
                      systemImage: 'person.crop.circle',
                      semanticLabel:
                          '选择${participant.fullName}，${participant.maskedPhone}',
                      dismissesSheet: true,
                      onPressed: () {
                        action = _PickerAction.select(participant);
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          AppleLiquidSheetSection(
            rows: <AppleLiquidSheetRow>[
              AppleLiquidSheetRow.button(
                title: '新增参与人信息',
                systemImage: 'person.badge.plus',
                semanticLabel: '新增参与人信息',
                dismissesSheet: true,
                onPressed: () {
                  action = const _PickerAction.add();
                },
              ),
            ],
          ),
        ],
      ),
    );
    return _NativePickerResult(shown: shown, action: action);
  } on MissingPluginException {
    return const _NativePickerResult(shown: false);
  } on PlatformException {
    return const _NativePickerResult(shown: false);
  }
}

class _ParticipantLoadSheet extends ConsumerStatefulWidget {
  const _ParticipantLoadSheet({this.forceRefresh = false});

  final bool forceRefresh;

  @override
  ConsumerState<_ParticipantLoadSheet> createState() =>
      _ParticipantLoadSheetState();
}

class _ParticipantLoadSheetState extends ConsumerState<_ParticipantLoadSheet> {
  bool _delivered = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceRefresh) {
      ref.invalidate(participantsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Participant>> async = ref.watch(participantsProvider);
    if (async case AsyncData<List<Participant>>(:final value)) {
      if (!_delivered) {
        _delivered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(value);
        });
      }
    }

    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 280,
          child: Column(
            children: <Widget>[
              _SheetHeader(
                title: '选择参与人信息',
                onCancel: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: async.when(
                  loading: () => const Center(
                    key: Key('participant-picker-loading'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CupertinoActivityIndicator(radius: 13),
                        SizedBox(height: CyTokens.space3),
                        Text('参与人信息加载中'),
                      ],
                    ),
                  ),
                  error: (Object error, StackTrace stackTrace) => StatusView(
                    message: '没能读到参与人',
                    sub: error.toString().replaceFirst('Exception: ', ''),
                    onRetry: () {
                      _delivered = false;
                      ref.invalidate(participantsProvider);
                    },
                  ),
                  data: (_) => const Center(
                    child: CupertinoActivityIndicator(radius: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<_PickerAction?> _showCupertinoPicker(
  BuildContext context,
  List<Participant> rows,
) {
  return showCupertinoModalPopup<_PickerAction>(
    context: context,
    builder: (_) => _CupertinoParticipantPicker(rows: rows),
  );
}

class _CupertinoParticipantPicker extends StatelessWidget {
  const _CupertinoParticipantPicker({required this.rows});

  final List<Participant> rows;

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height * 0.72;
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: <Widget>[
              _SheetHeader(
                title: '选择参与人信息',
                onCancel: () =>
                    Navigator.of(context).pop(const _PickerAction.cancel()),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          '暂无参与人信息',
                          style: CyType.body.copyWith(
                            color: CyPalette.of(context).textTertiary,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(
                          top: CyTokens.space2,
                          bottom: CyTokens.space3,
                        ),
                        children: <Widget>[
                          CupertinoListSection.insetGrouped(
                            children: rows
                                .map(
                                  (Participant participant) => Semantics(
                                    button: true,
                                    label:
                                        '选择${participant.fullName}，${participant.maskedPhone}',
                                    child: CupertinoListTile.notched(
                                      key: Key(
                                        'participant-row-${participant.id}',
                                      ),
                                      title: Text(participant.fullName),
                                      subtitle: Text(participant.maskedPhone),
                                      trailing: const Icon(
                                        CupertinoIcons.chevron_forward,
                                        size: 18,
                                      ),
                                      onTap: () => Navigator.of(
                                        context,
                                      ).pop(_PickerAction.select(participant)),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  CyTokens.space3,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: CupertinoButton.tinted(
                    onPressed: () =>
                        Navigator.of(context).pop(const _PickerAction.add()),
                    child: const Text('新增参与人信息'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.onCancel});

  final String title;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Text(title, style: CyType.headline),
          Positioned(
            left: CyTokens.space2,
            child: CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              onPressed: onCancel,
              child: const Text('取消'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<Participant?> _editParticipant(
  BuildContext context,
  List<Participant> existing,
) {
  return showCupertinoModalPopup<Participant>(
    context: context,
    builder: (_) => _AddParticipantSheet(existing: existing),
  );
}

class _AddParticipantSheet extends ConsumerStatefulWidget {
  const _AddParticipantSheet({required this.existing});

  final List<Participant> existing;

  @override
  ConsumerState<_AddParticipantSheet> createState() =>
      _AddParticipantSheetState();
}

class _AddParticipantSheetState extends ConsumerState<_AddParticipantSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();

  bool _saving = false;
  bool _savedAwaitingReadback = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_savedAwaitingReadback &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();
    final ParticipantApi api = ref.read(participantApiProvider);
    try {
      if (!_savedAwaitingReadback) {
        await api.save(fullName: name, mobilePhone: phone);
        _savedAwaitingReadback = true;
      }
      final Set<int> existingIds = widget.existing
          .map((Participant participant) => participant.id)
          .toSet();
      final List<Participant> refreshed = await api.list();
      final Participant? created = _findCreatedParticipant(
        refreshed,
        existingIds: existingIds,
        name: name,
        phone: phone,
      );
      if (created == null) {
        throw const _ParticipantReadbackException('参与人已保存，但没能回读真实编号，请重试读取');
      }
      ref.invalidate(participantsProvider);
      if (mounted) Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final double available = MediaQuery.sizeOf(context).height - keyboard - 24;
    final double height = math.min(500, available);
    return AnimatedPadding(
      duration: reduceMotion ? Duration.zero : CyMotion.standard,
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: CupertinoPopupSurface(
        isSurfacePainted: true,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  _SheetHeader(
                    title: '参与人信息',
                    onCancel: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: CyTokens.space3),
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            CyTokens.pageX,
                            0,
                            CyTokens.pageX,
                            CyTokens.space3,
                          ),
                          child: Text(
                            '用于报名联系和到场核验，不会公开展示，也不用于配送。',
                            style: CyType.footnote.copyWith(
                              color: CyPalette.of(context).textSecondary,
                            ),
                          ),
                        ),
                        CupertinoFormSection.insetGrouped(
                          children: <Widget>[
                            CupertinoTextFormFieldRow(
                              controller: _nameController,
                              focusNode: _nameFocus,
                              enabled: !_saving && !_savedAwaitingReadback,
                              prefix: const Text('姓名'),
                              placeholder: '输入姓名',
                              textInputAction: TextInputAction.next,
                              autofillHints: const <String>[AutofillHints.name],
                              onFieldSubmitted: (_) =>
                                  _phoneFocus.requestFocus(),
                              validator: (String? value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return '请输入姓名';
                                }
                                return null;
                              },
                            ),
                            CupertinoTextFormFieldRow(
                              controller: _phoneController,
                              focusNode: _phoneFocus,
                              enabled: !_saving && !_savedAwaitingReadback,
                              prefix: const Text('手机号'),
                              placeholder: '输入手机号',
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              autofillHints: const <String>[
                                AutofillHints.telephoneNumber,
                              ],
                              maxLength: 11,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onFieldSubmitted: (_) => _save(),
                              validator: (String? value) {
                                final String phone = (value ?? '').trim();
                                if (phone.isEmpty) return '请输入手机号';
                                if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
                                  return '请输入正确的手机号';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                        if (_error != null)
                          Semantics(
                            liveRegion: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CyTokens.pageX,
                              ),
                              child: Text(
                                _error!,
                                style: CyType.footnote.copyWith(
                                  color: CyTokens.statusDanger,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.pageX,
                      CyTokens.space2,
                      CyTokens.pageX,
                      CyTokens.space3,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: CupertinoButton.filled(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white,
                              )
                            : Text(
                                _savedAwaitingReadback
                                    ? '重新读取参与人信息'
                                    : '保存参与人信息',
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Participant? _findCreatedParticipant(
  List<Participant> rows, {
  required Set<int> existingIds,
  required String name,
  required String phone,
}) {
  for (final Participant participant in rows) {
    if (participant.id > 0 &&
        !existingIds.contains(participant.id) &&
        participant.fullName == name &&
        participant.mobilePhone == phone) {
      return participant;
    }
  }
  return null;
}

class _ParticipantReadbackException implements Exception {
  const _ParticipantReadbackException(this.message);

  final String message;

  @override
  String toString() => message;
}
