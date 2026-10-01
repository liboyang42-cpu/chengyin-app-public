// 在聊天里发一张「路线卡片」—— 对应小程序 im/chat 的 routePicker。
//
// ★ 复用 `/api/topic/list`,**零新端点**(小程序那页的注释原话)。
//
// ⚠️ 卡片**只传 topicId**,不传标题/封面 ——
//   展示字段服务端不收、由接收方现拉(小程序 spec 决策 8)。
//   把标题一起塞进 extra_json 的话,路线改名后聊天记录里还是旧名字。

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/error_presentation.dart';
import '../../core/widgets/localized_error_status.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/topic.dart';

/// 卡片的 extra_json。★ 与小程序 `sendCard({cardType:'route', topicId})` 同形 ——
/// 两端要能互相解析,字段名不能各写各的。
String routeCardJson(int topicId) =>
    jsonEncode(<String, dynamic>{'cardType': 'route', 'topicId': topicId});

final _routeSearchProvider = FutureProvider.autoDispose
    .family<List<Topic>, String>(
      (Ref ref, String kw) =>
          ref.watch(topicApiProvider).list(keyword: kw.isEmpty ? null : kw),
    );

/// 选一条路线;返回它的 id(取消返回 null)。
Future<int?> pickRouteToShare(BuildContext context) => showCupertinoSheet<int>(
  context: context,
  showDragHandle: true,
  topGap: 0.18,
  scrollableBuilder:
      (BuildContext context, ScrollController scrollController) =>
          _Sheet(scrollController: scrollController),
);

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.scrollController});

  final ScrollController scrollController;
  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  String _kw = '';

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final AsyncValue<List<Topic>> async = ref.watch(_routeSearchProvider(_kw));
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).imRemainingChooseRoute),
        trailing: CyNativeIconButton(
          label: stringsOf(context).imRemainingClose,
          icon: const CyNativeButtonIcon(
            sfSymbol: 'xmark',
            fallback: CupertinoIcons.xmark,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: CyTokens.space3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
              child: CySearchField(
                key: const Key('route-picker-search'),
                value: _kw,
                placeholder: stringsOf(context).imRemainingSearchRoutes,
                onChanged: (String v) => setState(() => _kw = v),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => Semantics(
                  liveRegion: true,
                  label: stringsOf(context).imRemainingLoadingRoutes,
                  child: const ExcludeSemantics(
                    child: Center(child: CupertinoActivityIndicator()),
                  ),
                ),
                error: (Object e, StackTrace _) => LocalizedErrorStatus(
                  error: e,
                  fallback: stringsOf(context).imRemainingRouteLoadFailed,
                  originalApiMessage: legacyApiMessage(e),
                  large: true,
                  onRetry: () => ref.invalidate(_routeSearchProvider(_kw)),
                ),
                data: (List<Topic> rows) => rows.isEmpty
                    ? StatusView(
                        message: stringsOf(context).imRemainingNoRoutes,
                        sub: _kw.isEmpty ? stringsOf(context).imRemainingNoShareRoutes : stringsOf(context).imRemainingTryKeyword,
                        large: true,
                      )
                    : ListView(
                        controller: widget.scrollController,
                        children: <Widget>[
                          CupertinoListSection(
                            children: rows
                                .map((Topic route) {
                                  final String introduction =
                                      (route.introduction ?? '').trim();
                                  void selectRoute() =>
                                      Navigator.of(context).pop(route.id);
                                  return Semantics(
                                    container: true,
                                    excludeSemantics: true,
                                    label: introduction.isEmpty
                                        ? stringsOf(context).imRemainingSelectRoute(route.name)
                                        : stringsOf(context).imRemainingSelectRouteDetail(route.name, introduction),
                                    button: true,
                                    onTap: selectRoute,
                                    child: CupertinoListTile(
                                      key: Key('route-pick-${route.id}'),
                                      title: Text(
                                        route.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: introduction.isEmpty
                                          ? null
                                          : Text(
                                              introduction,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: p.textTertiary,
                                              ),
                                            ),
                                      onTap: selectRoute,
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
