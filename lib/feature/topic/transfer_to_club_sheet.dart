import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club.dart';
import '../club/club_controller.dart';

/// 原生 Sheet 已展示时，包内第二次 `showSheet` 会直接回 true。
/// 整条移交流程复用同一 Future，避免将这个 true 误当成“用户
/// 已关闭但未选择”，也避免同一主题并发复制两份新草稿。
Future<int?>? _activeTransferResolution;

/// 移交主题给俱乐部承接。
///
/// 小程序流程是：`/api/club/my` → 按原顺序选 Club → 确认 →
/// `/api/topic/transfer-to-club` → 返回 `newTopicId`。App 仅替换展示层，
/// 不改真实 club id、确认动作或返回落点。
Future<int?> showTransferToClubSheet(
  BuildContext context, {
  required int topicId,
}) {
  final Future<int?>? active = _activeTransferResolution;
  if (active != null) return active;

  final Future<int?> resolution = _runTransferFlow(
    context: context,
    topicId: topicId,
  );
  _activeTransferResolution = resolution;
  return resolution.whenComplete(() {
    if (identical(_activeTransferResolution, resolution)) {
      _activeTransferResolution = null;
    }
  });
}

Future<int?> _runTransferFlow({
  required BuildContext context,
  required int topicId,
}) async {
  final List<Club>? clubs = await _loadTransferClubs(context);
  if (clubs == null || clubs.isEmpty || !context.mounted) return null;

  final Club? club = await _chooseTransferClub(context, clubs);
  if (club == null || !context.mounted) return null;

  final bool confirmed = await cyConfirm(
    context,
    title: '移交给俱乐部承接',
    content:
        '将复制一份新的城市定向主题(有人带),挂到「${club.name}」承接;'
        '原主题会下架,历史票不受影响。',
    confirmText: '确认移交',
    danger: true,
  );
  if (!confirmed || !context.mounted) return null;

  try {
    final int newTopicId = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(topicApiProvider).transferToClub(topicId: topicId, clubId: club.id);
    if (newTopicId <= 0) {
      throw Exception('没拿到新主题号 —— 别当移交成功了');
    }
    return newTopicId;
  } catch (error) {
    if (!context.mounted) return null;
    CyNativeNotice.show(
      context,
      error.toString().replaceFirst('Exception: ', ''),
      isError: true,
    );
    return null;
  }
}

Future<List<Club>?> _loadTransferClubs(BuildContext context) {
  return showCupertinoModalPopup<List<Club>>(
    context: context,
    builder: (BuildContext popupContext) => const _TransferClubLoader(),
  );
}

class _TransferClubLoader extends ConsumerStatefulWidget {
  const _TransferClubLoader();

  @override
  ConsumerState<_TransferClubLoader> createState() =>
      _TransferClubLoaderState();
}

class _TransferClubLoaderState extends ConsumerState<_TransferClubLoader> {
  bool _didReturnClubs = false;

  void _returnClubs(List<Club> clubs) {
    if (_didReturnClubs) return;
    _didReturnClubs = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(clubs);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Club>> async = ref.watch(clubMyProvider);
    return _TransferPopupFrame(
      child: async.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (Object _, StackTrace _) => StatusView(
          icon: CupertinoIcons.exclamationmark_circle,
          message: '网络错误,请重试',
          onRetry: () => ref.invalidate(clubMyProvider),
        ),
        data: (List<Club> clubs) {
          if (clubs.isNotEmpty) {
            _returnClubs(clubs);
            return const Center(child: CupertinoActivityIndicator());
          }
          return const StatusView(
            icon: CupertinoIcons.person_3,
            message: '你还没有可承接的俱乐部',
          );
        },
      ),
    );
  }
}

Future<Club?> _chooseTransferClub(
  BuildContext context,
  List<Club> clubs,
) async {
  Club? nativeSelection;
  try {
    final bool shownNatively = await AppleLiquidSheet.showSheet(
      heightFraction: CyTokens.iosSheetHeightFraction,
      // 不额外缩放背景，不叠加自定义按压动画；保留系统
      // Sheet 转场，让 Reduce Motion 由 iOS 自己处理。
      backgroundZoomScale: 1,
      scrollContext: context,
      content: AppleLiquidSheetContent(
        title: '选择承接俱乐部',
        doneSemanticLabel: '取消移交给俱乐部承接',
        sections: <AppleLiquidSheetSection>[
          AppleLiquidSheetSection(
            rows: clubs
                .map(
                  (Club club) => AppleLiquidSheetRow.button(
                    title: _clubName(club),
                    systemImage: 'person.3.fill',
                    semanticLabel: '选择俱乐部：${_clubName(club)}',
                    dismissesSheet: true,
                    style: const AppleLiquidSheetButtonStyle(
                      buttonHeight: 48,
                      borderWidth: 0,
                      backgroundOpacity: 0,
                      rowHorizontalInset: 0,
                      rowVerticalInset: 0,
                      alignment: AppleLiquidSheetButtonAlignment.leading,
                      pressedScale: 1,
                      pressAnimationDuration: 0,
                      showsFormBackground: true,
                      showsSeparator: true,
                    ),
                    onPressed: () => nativeSelection = club,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
    if (shownNatively) return nativeSelection;
  } on MissingPluginException {
    // 旧 iOS /原生包未注册时继续可用的 Cupertino 选择。
  } on PlatformException {
    // 原生层暂时无法展示时不改变业务流程。
  }

  if (!context.mounted) return null;
  return _showTransferClubFallback(context, clubs);
}

Future<Club?> _showTransferClubFallback(
  BuildContext context,
  List<Club> clubs,
) {
  return showCupertinoModalPopup<Club>(
    context: context,
    builder: (BuildContext popupContext) => _TransferPopupFrame(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: CyTokens.space3),
        itemCount: clubs.length,
        itemBuilder: (BuildContext context, int index) {
          final Club club = clubs[index];
          final String name = _clubName(club);
          return Semantics(
            button: true,
            label: '选择俱乐部：$name',
            child: ExcludeSemantics(
              child: CupertinoListTile(
                key: Key('transfer-club-${club.id}'),
                title: Text(name),
                onTap: () => Navigator.of(popupContext).pop(club),
              ),
            ),
          );
        },
      ),
    ),
  );
}

String _clubName(Club club) => club.name.isEmpty ? '未命名俱乐部' : club.name;

class _TransferPopupFrame extends StatelessWidget {
  const _TransferPopupFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.64,
          // ★ 不再叠一层 Material 面板色:`CupertinoPopupSurface(isSurfacePainted: true)`
          //   自己就画系统弹层底(半透 + 背景模糊),再糊一层 Material surface 是
          //   「系统层自己上背景」(M5),两层叠出来的颜色既不是 iOS 的也不是品牌的。
          //   文本样式由各控件显式给出(StatusView / CupertinoListTile 都自带)。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.space2,
                  CyTokens.space1,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '选择承接俱乐部',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    CupertinoButton(
                      key: const Key('transfer-club-cancel'),
                      padding: const EdgeInsets.all(CyTokens.space2),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
