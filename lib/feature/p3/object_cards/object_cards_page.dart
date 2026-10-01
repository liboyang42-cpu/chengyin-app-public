import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/network/request_session_scope.dart';
import '../../../core/network/session_data.dart';
import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_native_notice.dart';
import '../../../core/widgets/cy_widgets.dart';
import '../../../core/widgets/status_view.dart';
import '../../../data/models/object_card.dart';
import '../../../l10n/strings.dart';
import '../../account/account_login_gate.dart';
import '../../auth/auth_controller.dart';
import 'object_cards_controller.dart';

class ObjectCardsPage extends ConsumerStatefulWidget {
  const ObjectCardsPage({super.key});

  @override
  ConsumerState<ObjectCardsPage> createState() => _ObjectCardsPageState();
}

class _ObjectCardsPageState extends ConsumerState<ObjectCardsPage> {
  late final ObjectCardsController _controller;
  Timer? _backTimer;
  bool _gathered = false;
  int _ownerVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller = ObjectCardsController(
      (category) {
        final auth = ref.read(authControllerProvider);
        final owner = auth.user?.id;
        if (owner == null || auth.loading || !auth.initialized) {
          return Future.error(const SessionDataUnavailable());
        }
        final version = _ownerVersion;
        final session = ref.read(authControllerProvider.notifier).requestScope(owner);
        final scope = RequestSessionScope(() => mounted &&
            version == _ownerVersion && session.isCurrent());
        return RequestSessionScope.run(scope,
          () => ref.read(objectCardApiProvider).list(category: category));
      },
    );
    ref.listenManual(sessionDataKeyProvider, (previous, next) {
      _ownerVersion++;
      _backTimer?.cancel();
      _controller.reset();
      _gathered = false;
      if (next.userId != null && next.initialized && !next.loading) {
        unawaited(_load(''));
      }
    }, fireImmediately: true);
  }

  Future<void> _load(String category) async {
    final ownerVersion = _ownerVersion;
    final hadData = _controller.collection != null;
    final success = await _controller.load(category);
    if (!mounted || ownerVersion != _ownerVersion) return;
    if (success) {
      _backTimer?.cancel();
      setState(() => _gathered = false);
    } else if (hadData) {
      CyNativeNotice.show(context, stringsOf(context).objectCardsFilterError);
    } else {
      // cy-error auto-back: explain the error, then return after two seconds.
      _backTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.canPop() ? router.pop() : router.go('/');
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _backTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = stringsOf(context);
    final ownerId = ref.watch(authControllerProvider.select((state) => state.user?.id));
    if (ownerId == null) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(strings.objectCardsTitle)),
        child: Center(child: AccountLoginGate(
          key: const Key('object-cards-login'),
          message: strings.objectCardsLogin,
          onSignedIn: () {
            if (!_controller.loading && _controller.collection == null) {
              unawaited(_load(''));
            }
          },
        )),
      );
    }
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(strings.objectCardsTitle)),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final cards = _controller.collection?.cards ?? const <ObjectCard>[];
            return Column(
              children: [
                CyPageTitle(strings.objectCardsTitle),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          onPressed: _controller.loading ? null : _chooseCategory,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text(_categoryLabel(context, _controller.category))),
                              const Icon(CupertinoIcons.chevron_down),
                            ],
                          ),
                        ),
                      ),
                      if (cards.length > 1)
                        CupertinoButton(
                          onPressed: () => setState(() => _gathered = !_gathered),
                          child: Semantics(
                            label: _gathered ? strings.objectCardsRelease : strings.objectCardsGather,
                            child: ExcludeSemantics(
                              child: Icon(_gathered ? CupertinoIcons.arrow_down : CupertinoIcons.sparkles),
                            ),
                          ),
                        ),
                      if (_controller.loading && cards.isNotEmpty)
                        const CupertinoActivityIndicator(),
                    ],
                  ),
                ),
                Expanded(
                  child: _controller.error
                      ? Center(child: StatusView(
                          message: strings.objectCardsLoadError,
                          sub: strings.objectCardsLoadErrorDetail,
                          large: true,
                        ))
                      : _controller.loading && cards.isEmpty
                      ? const Center(child: CupertinoActivityIndicator())
                      : cards.isEmpty
                      ? Center(child: StatusView(
                          message: _controller.category.isEmpty
                              ? strings.objectCardsEmpty
                              : strings.objectCardsCategoryEmpty,
                          sub: strings.objectCardsEmptyDetail,
                          large: true,
                        ))
                      : _pile(cards),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _chooseCategory() async {
    final category = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(stringsOf(context).objectCardsCategory),
        actions: [
          for (final category in objectCardCategories)
            CupertinoActionSheetAction(
              isDefaultAction: category == _controller.category,
              onPressed: () => Navigator.of(sheetContext).pop(category),
              child: Text(_categoryLabel(context, category)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(stringsOf(context).cancel),
        ),
      ),
    );
    if (!mounted || category == null || category == _controller.category) return;
    await _load(category);
  }

  Widget _pile(List<ObjectCard> cards) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: stringsOf(context).objectCardsPile(cards.length),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final size = math.min(64.0, width / 5);
        return Stack(
          children: [
            Positioned(
              left: CyTokens.pageX,
              right: CyTokens.pageX,
              bottom: CyTokens.space6,
              child: Container(height: 1, color: CyPalette.of(context).borderStrong),
            ),
            for (var index = 0; index < cards.length; index++)
              AnimatedPositioned(
                key: ValueKey('object-card-${cards[index].id}'),
                duration: reduced ? Duration.zero : CyMotion.slow,
                curve: Curves.easeOut,
                left: _gathered
                    ? (width - size) / 2 + math.cos(index * 2.4) * math.sqrt(index) * size / 5
                    : (width - size) * ((index * 0.61803398875) % 1),
                top: _gathered
                    ? (height - size) * 0.42 + math.sin(index * 2.4) * math.sqrt(index) * size / 5
                    : math.max(0, height - CyTokens.space6 - size - (index ~/ 6) * size * 0.58),
                width: size,
                height: size,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    final ownerId = ref.read(authControllerProvider).user?.id;
                    if (ownerId == null) return;
                    showCupertinoSheet<void>(
                      context: context,
                      builder: (_) => _ObjectCardDetail(
                        card: cards[index],
                        ownerId: ownerId,
                      ),
                    );
                  },
                  child: _CardImage(url: cards[index].thumbnail, title: cards[index].title),
                ),
              ),
          ],
        );
      }),
    );
  }
}

String _categoryLabel(BuildContext context, String category) {
  final strings = stringsOf(context);
  final labels = [
    strings.objectCardsAll, strings.objectCardsElectronics,
    strings.objectCardsClothing, strings.objectCardsBags,
    strings.objectCardsFood, strings.objectCardsBooks,
    strings.objectCardsToys, strings.objectCardsHousehold, strings.objectCardsOther,
  ];
  final index = objectCardCategories.indexOf(category);
  return index < 0 ? category : labels[index];
}

class _ObjectCardDetail extends ConsumerStatefulWidget {
  const _ObjectCardDetail({required this.card, required this.ownerId});
  final ObjectCard card;
  final int ownerId;

  @override
  ConsumerState<_ObjectCardDetail> createState() => _ObjectCardDetailState();
}

class _ObjectCardDetailState extends ConsumerState<_ObjectCardDetail> {
  int _frame = 0;
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(authControllerProvider.select((state) => state.user?.id));
    if (ownerId != widget.ownerId) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).objectCardsTitle)),
        child: const SizedBox.shrink(),
      );
    }
    final card = widget.card;
    final strings = stringsOf(context);
    final spinning = card.frames.length > 1;
    final photoCard = !spinning && card.cutoutUrl.isEmpty;
    final image = spinning ? card.frames[_frame]
        : card.cutoutUrl.isNotEmpty ? card.cutoutUrl : card.frames.firstOrNull ?? '';
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(card.title.isEmpty ? strings.objectCardsItem : card.title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Semantics(
            label: strings.objectCardsClose,
            child: const ExcludeSemantics(child: Icon(CupertinoIcons.xmark)),
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(CyTokens.pageX),
          children: [
            Semantics(
              hint: spinning ? strings.objectCardsRotate : null,
              onIncrease: spinning ? () => setState(() => _frame = (_frame + 1) % card.frames.length) : null,
              onDecrease: spinning ? () => setState(() => _frame = (_frame - 1) % card.frames.length) : null,
              child: GestureDetector(
                onHorizontalDragStart: spinning ? (_) => _drag = 0 : null,
                onHorizontalDragUpdate: spinning ? (details) {
                  _drag += details.delta.dx;
                  final steps = (_drag / 8).truncate();
                  if (steps == 0) return;
                  _drag -= steps * 8;
                  setState(() => _frame = (_frame + steps) % card.frames.length);
                } : null,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _CardImage(url: image, title: card.title),
                ),
              ),
            ),
            if (photoCard && card.caption.isNotEmpty) Text(card.caption),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(title: Text(strings.objectCardsName), additionalInfo: Text(card.title, maxLines: 2, overflow: TextOverflow.ellipsis)),
                if (card.category.isNotEmpty)
                  CupertinoListTile(title: Text(strings.objectCardsCategory), additionalInfo: Text(_categoryLabel(context, card.category))),
              ],
            ),
            if (card.place.isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: Text(strings.objectCardsInformation),
                children: [CupertinoListTile(title: Text(strings.objectCardsPlace), additionalInfo: Text(card.place, maxLines: 2, overflow: TextOverflow.ellipsis))],
              ),
            if (card.generating) Text(strings.objectCardsGenerating),
          ],
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.url, required this.title});
  final String url, title;

  @override
  Widget build(BuildContext context) {
    final placeholder = Semantics(
      label: title,
      child: Icon(CupertinoIcons.photo, color: CyPalette.of(context).textDisabled),
    );
    if (url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.contain,
      semanticLabel: title,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
