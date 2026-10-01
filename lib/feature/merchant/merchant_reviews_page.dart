import '../../l10n/strings.dart';
import 'merchant_review_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_review_api.dart';
import '../../data/models/merchant_review.dart';

typedef MerchantReviewRequestIdFactory =
    String Function(MerchantReviewAction action);

class MerchantReviewsPage extends StatefulWidget {
  const MerchantReviewsPage({
    super.key,
    required this.api,
    this.requestIdFactory,
  });

  final MerchantReviewGateway api;
  final MerchantReviewRequestIdFactory? requestIdFactory;

  @override
  State<MerchantReviewsPage> createState() => _MerchantReviewsPageState();
}

class _MerchantReviewsPageState extends State<MerchantReviewsPage> {
  static const int _pageSize = 20;

  List<MerchantReviewItem> _items = const <MerchantReviewItem>[];
  int _pageNum = 1;
  int _total = 0;
  double? _averageRating;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadFirstPage);
  }

  @override
  void dispose() {
    _requestToken += 1;
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    final int token = ++_requestToken;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _items = const <MerchantReviewItem>[];
      _pageNum = 1;
      _total = 0;
      _averageRating = null;
      _hasMore = false;
    });
    try {
      final MerchantReviewPage page = await widget.api.managePage(
        pageNum: 1,
        pageSize: _pageSize,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _items = page.items;
        _pageNum = page.pageNum;
        _total = page.total;
        _averageRating = page.averageRating;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final int token = _requestToken;
    setState(() => _loadingMore = true);
    try {
      final MerchantReviewPage page = await widget.api.managePage(
        pageNum: _pageNum + 1,
        pageSize: _pageSize,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _items = <MerchantReviewItem>[..._items, ...page.items];
        _pageNum = page.pageNum;
        _total = page.total;
        _averageRating = page.averageRating;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _requestToken) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openAction(
    MerchantReviewItem review,
    MerchantReviewAction action,
  ) async {
    final Object? receipt = await showCupertinoModalPopup<Object>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext sheetContext) => _ReviewActionSheet(
        api: widget.api,
        review: review,
        action: action,
        requestIdFactory: widget.requestIdFactory,
      ),
    );
    if (!mounted || receipt == null) return;
    CyNativeNotice.show(
      context,
      action == MerchantReviewAction.reply ? stringsOf(context).merchantManageReviewReplyPublished : stringsOf(context).merchantPublicReviewReportReceipt,
    );
    await _loadFirstPage();
  }

  /// 修改公开回复:回填原文,提交走 `reply/update`。
  Future<void> _openEditReply(MerchantReviewItem review) async {
    final Object? done = await showCupertinoModalPopup<Object>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext sheetContext) => _ReviewActionSheet(
        api: widget.api,
        review: review,
        action: MerchantReviewAction.reply,
        editing: true,
        initialContent: review.merchantReply ?? '',
        requestIdFactory: widget.requestIdFactory,
      ),
    );
    if (!mounted || done == null) return;
    CyNativeNotice.show(context, stringsOf(context).merchantManageReviewReplyUpdated);
    await _loadFirstPage();
  }

  /// 删除公开回复。不可逆动作先过三段式确认(快照 danger-actions.js
  /// `merchant.review.reply.delete`),删后评价回到待回复。
  Future<void> _deleteReply(MerchantReviewItem review) async {
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).merchantManageReviewDeleteTitle,
      content:
          '只是写错了话,改成新的比删掉更轻。\n'
          '· 玩家和其他访客将看不到你写的这段公开回复\n'
          '· 这条评价回到「待回复」,你可以重新写一条\n'
          '· 此操作不可撤销,删掉的回复内容无法找回',
      confirmText: stringsOf(context).merchantManageReviewDelete,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.api.deleteReply(
        reviewId: review.id,
        expectedVersion: review.version,
        requestId: _newReplyDeleteRequestId(),
      );
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantManageReviewDeleted);
      await _loadFirstPage();
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        merchantReviewErrorText(context, error),
        isError: true,
      );
    }
  }

  Future<void> _previewImages(List<Uri> urls, int initialIndex) {
    return showCupertinoModalPopup<void>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext previewContext) =>
          _ReviewImagePreview(urls: urls, initialIndex: initialIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantManageReviewTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const CySkeleton(type: CySkeletonType.card, count: 4);
    }
    final Object? error = _error;
    if (error is MerchantReviewApiException &&
        (error.isUnauthorized || error.isForbidden)) {
      return StatusView(
        icon: CupertinoIcons.lock,
        message: stringsOf(context).merchantManageReviewDenied,
        sub: stringsOf(context).merchantManageReviewDeniedHint,
        large: true,
      );
    }
    if (error != null) {
      return StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: stringsOf(context).merchantPublicReviewLoadError,
        sub: merchantReviewErrorText(context, error),
        onRetry: _loadFirstPage,
        retryLabel: stringsOf(context).merchantPublicReviewReload,
        large: true,
      );
    }
    if (_items.isEmpty) {
      return StatusView(
        icon: CupertinoIcons.chat_bubble_2,
        message: stringsOf(context).merchantManageReviewEmpty,
        sub: '新评价会在这里显示；商家不能修改用户原评。',
        onRetry: _loadFirstPage,
        retryLabel: stringsOf(context).merchantPublicReviewReload,
        large: true,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 100 ||
            notification is OverscrollNotification &&
                notification.overscroll > 0) {
          _loadMore();
        }
        return false;
      },
      child: RefreshIndicator.adaptive(
        onRefresh: _loadFirstPage,
        child: ListView.separated(
          key: const Key('merchant-review-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space8,
          ),
          itemCount: _items.length + 3,
          separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space4),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) return _hero(context);
            if (index == 1) return _listHead(context);
            if (index == _items.length + 2) return _footer(context);
            return _reviewCard(context, _items[index - 2]);
          },
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: _cardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'VERIFIED VISITS',
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(stringsOf(context).merchantManageReviewHeading, style: textTheme.headlineSmall),
                const SizedBox(height: CyTokens.space2),
                Text(
                  '评价资格来自已生效核销，商家回复不会改写用户原评。',
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                _averageRating?.toStringAsFixed(1) ?? stringsOf(context).merchantPublicReviewNoRating,
                style: textTheme.headlineMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                stringsOf(context).merchantPublicReviewCount(_total),
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(BuildContext context, MerchantReviewItem review) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      key: Key('merchant-review-${review.id}'),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipOval(
                child: review.authorAvatar == null
                    ? Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        color: palette.bgSubtle,
                        child: Text('城', style: textTheme.titleMedium),
                      )
                    : CyNetImage(
                        review.authorAvatar!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: CyTokens.space2,
                      runSpacing: CyTokens.space1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          review.hasAuthorNicknameFallback ? stringsOf(context).merchantPublicReviewAnonymous : review.authorNickname,
                          style: textTheme.titleSmall,
                        ),
                        if (review.verifiedRedemption)
                          Text(
                            stringsOf(context).merchantPublicReviewVerified,
                            style: textTheme.labelSmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      _minute(review.createTime) ?? stringsOf(context).merchantPublicReviewTimeUnknown,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(context, switch(review.status) {
MerchantReviewStatus.visible => stringsOf(context).merchantManageReviewVisible,
MerchantReviewStatus.pendingReview => stringsOf(context).merchantManageReviewPending,
MerchantReviewStatus.hidden => stringsOf(context).merchantManageReviewHidden
}),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              for (int star = 1; star <= 5; star++)
                Padding(
                  padding: const EdgeInsets.only(right: CyTokens.space1),
                  child: Icon(
                    star <= review.rating
                        ? CupertinoIcons.star_fill
                        : CupertinoIcons.star,
                    size: 18,
                    color: palette.textPrimary,
                    semanticLabel: star == review.rating
                        ? stringsOf(context).merchantPublicReviewStars(review.rating)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          Text(review.content, style: textTheme.bodyMedium),
          if (review.imageUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.imageUrls.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: CyTokens.space2),
                itemBuilder: (BuildContext context, int index) =>
                    CupertinoButton(
                      key: Key('merchant-review-image-${review.id}-$index'),
                      minimumSize: const Size(88, 88),
                      padding: EdgeInsets.zero,
                      pressedOpacity: MediaQuery.disableAnimationsOf(context)
                          ? 1
                          : 0.72,
                      onPressed: () => _previewImages(review.imageUrls, index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                        child: CyNetImage(
                          review.imageUrls[index].toString(),
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
              ),
            ),
          ],
          if (review.merchantReply != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: BoxDecoration(
                color: palette.bgSubtle,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    stringsOf(context).merchantManageReviewYourReply(review.repliedAt == null ? '' : ' · ${_minute(review.repliedAt!)}'),
                    style: textTheme.labelMedium,
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(review.merchantReply!),
                  // ★ 发布不是一次性的:服务端说能改(当前版本 + 当前岗位),
                  //   就给「修改回复 / 删除回复」;不能改时一个按钮都不摆。
                  if (review.canEditReply) ...<Widget>[
                    const SizedBox(height: CyTokens.space2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        CyNativeButton(
                          key: Key('merchant-review-edit-reply-${review.id}'),
                          label: stringsOf(context).merchantManageReviewEdit,
                          role: CyNativeButtonRole.secondary,
                          onPressed: () => _openEditReply(review),
                        ),
                        const SizedBox(width: CyTokens.space2),
                        CyNativeButton(
                          key: Key('merchant-review-delete-reply-${review.id}'),
                          label: stringsOf(context).merchantManageReviewDelete,
                          role: CyNativeButtonRole.destructive,
                          onPressed: () => _deleteReply(review),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (review.canReply || review.canReport) ...<Widget>[
            const SizedBox(height: CyTokens.space4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                if (review.canReply) ...<Widget>[
                  CyNativeButton(
                    key: Key('merchant-review-reply-${review.id}'),
                    label: stringsOf(context).merchantManageReviewReply,
                    onPressed: () =>
                        _openAction(review, MerchantReviewAction.reply),
                  ),
                ],
                if (review.canReport)
                  CyNativeButton(
                    key: Key('merchant-review-report-${review.id}'),
                    label: stringsOf(context).merchantPublicReviewReport,
                    role: CyNativeButtonRole.secondary,
                    onPressed: () =>
                        _openAction(review, MerchantReviewAction.report),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: _loadingMore
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CupertinoActivityIndicator(),
                  SizedBox(width: CyTokens.space2),
                  Text(stringsOf(context).merchantManageReviewLoadingMore),
                ],
              )
            : Text(_hasMore ? stringsOf(context).merchantManageReviewMore : stringsOf(context).merchantPublicReviewEnd),
      ),
    );
  }

  Widget _listHead(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(stringsOf(context).merchantManageReviewListTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: CyTokens.space1),
        Text(
          '公开列表仅展示平台当前判定为 VISIBLE 的内容',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }

  Widget _statusPill(BuildContext context, String label) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2_5,
        vertical: CyTokens.space1_5,
      ),
      decoration: BoxDecoration(
        color: palette.bgSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return BoxDecoration(
      color: palette.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      border: Border.all(color: palette.cardBorder),
      boxShadow: palette.cardShadow,
    );
  }
}

class _ReviewImagePreview extends StatefulWidget {
  const _ReviewImagePreview({required this.urls, required this.initialIndex});

  final List<Uri> urls;
  final int initialIndex;

  @override
  State<_ReviewImagePreview> createState() => _ReviewImagePreviewState();
}

class _ReviewImagePreviewState extends State<_ReviewImagePreview> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _move(int delta) {
    final int target = (_index + delta).clamp(0, widget.urls.length - 1);
    if (target == _index) return Future<void>.value();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(target);
      return Future<void>.value();
    }
    return _pageController.animateToPage(
      target,
      // ★ 翻页过场走令牌,别写裸时长(Test/theme/motion_ratchet 会拦)。
      duration: CyMotion.standard,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPopupSurface(
      key: const Key('merchant-review-image-preview'),
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  CupertinoButton(
                    key: const Key('merchant-review-image-previous'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: _index > 0 ? () => _move(-1) : null,
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      semanticLabel: stringsOf(context).merchantManageReviewPreviousImage,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('merchant-review-image-next'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: _index < widget.urls.length - 1
                        ? () => _move(1)
                        : null,
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      semanticLabel: stringsOf(context).merchantManageReviewNextImage,
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('merchant-review-image-close'),
                    minimumSize: const Size(44, 44),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      semanticLabel: stringsOf(context).merchantPublicReviewClosePreview,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.urls.length,
                  onPageChanged: (int index) => setState(() => _index = index),
                  itemBuilder: (BuildContext context, int index) =>
                      _ReviewZoomableImage(url: widget.urls[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewZoomableImage extends StatefulWidget {
  const _ReviewZoomableImage({required this.url});

  final Uri url;

  @override
  State<_ReviewZoomableImage> createState() => _ReviewZoomableImageState();
}

class _ReviewZoomableImageState extends State<_ReviewZoomableImage> {
  final TransformationController _transformation = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transformation.addListener(_updateZoomState);
  }

  @override
  void dispose() {
    _transformation
      ..removeListener(_updateZoomState)
      ..dispose();
    super.dispose();
  }

  void _updateZoomState() {
    final bool next = _transformation.value.getMaxScaleOnAxis() > 1.01;
    if (next != _zoomed && mounted) setState(() => _zoomed = next);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transformation,
      panEnabled: _zoomed,
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: CyNetImage(
          widget.url.toString(),
          width: double.infinity,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _ReviewActionSheet extends StatefulWidget {
  const _ReviewActionSheet({
    required this.api,
    required this.review,
    required this.action,
    this.editing = false,
    this.initialContent,
    this.requestIdFactory,
  });

  final MerchantReviewGateway api;
  final MerchantReviewItem review;
  final MerchantReviewAction action;

  /// 修改已有回复(而不是新发一条)。
  final bool editing;
  final String? initialContent;
  final MerchantReviewRequestIdFactory? requestIdFactory;

  @override
  State<_ReviewActionSheet> createState() => _ReviewActionSheetState();
}

class _ReviewActionSheetState extends State<_ReviewActionSheet> {
  final TextEditingController _controller = TextEditingController();

  bool _submitting = false;
  String? _error;
  String? _requestId;
  String? _fingerprint;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialContent ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final MerchantReviewReplyDraft? reply =
        widget.action == MerchantReviewAction.reply
        ? MerchantReviewReplyDraft(
            reviewId: widget.review.id,
            expectedVersion: widget.review.version,
            content: _controller.text,
          )
        : null;
    final MerchantReviewReportDraft? report =
        widget.action == MerchantReviewAction.report
        ? MerchantReviewReportDraft(
            reviewId: widget.review.id,
            expectedVersion: widget.review.version,
            reason: _controller.text,
          )
        : null;
    final String? validationError =
        merchantReviewLocalValidation(context, reply?.validationError ?? report?.validationError);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final String fingerprint = reply?.fingerprint ?? report!.fingerprint;
    if (_requestId == null || _fingerprint != fingerprint) {
      _requestId =
          widget.requestIdFactory?.call(widget.action) ??
          _newReviewRequestId(widget.action);
      _fingerprint = fingerprint;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.editing) {
        await widget.api.updateReply(draft: reply!, requestId: _requestId!);
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      final MerchantReviewReceipt receipt = reply != null
          ? await widget.api.reply(draft: reply, requestId: _requestId!)
          : await widget.api.reportAsMerchant(
              draft: report!,
              requestId: _requestId!,
            );
      if (!mounted) return;
      Navigator.of(context).pop(receipt);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = merchantReviewErrorText(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool isReply = widget.action == MerchantReviewAction.reply;
    return AnimatedPadding(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : CyMotion.standard,
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CupertinoPopupSurface(
        isSurfacePainted: true,
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space4,
                CyTokens.pageX,
                CyTokens.space4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.editing
                              ? stringsOf(context).merchantManageReviewEditTitle
                              : (isReply ? stringsOf(context).merchantManageReviewReply : stringsOf(context).merchantPublicReviewReportTitle),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          semanticLabel: stringsOf(context).merchantManageReviewClose,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    widget.editing
                        ? '只改你的这段公开回复，不会改动玩家评分与正文。'
                        : isReply
                        ? '回复后可修改，也可以删除；商家回复不会改写用户评分与正文。'
                        : '举报只会进入统一审核队列，不代表内容已经下架。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space3),
                  CupertinoTextField(
                    key: const Key('merchant-review-action-input'),
                    controller: _controller,
                    enabled: !_submitting,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 500,
                    placeholder: widget.editing
                        ? stringsOf(context).merchantManageReviewEditHint
                        : isReply
                        ? stringsOf(context).merchantManageReviewReplyHint
                        : stringsOf(context).merchantManageReviewReportHint,
                    padding: const EdgeInsets.all(CyTokens.space3),
                    decoration: BoxDecoration(
                      color: palette.inputBgEmpty,
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: CyTokens.space4),
                  SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      // 快照里这两颗按钮的可访问名(aria-label)。
                      label: widget.editing
                          ? stringsOf(context).merchantManageReviewSaveSemantics
                          : (isReply ? stringsOf(context).merchantManageReviewSend : stringsOf(context).merchantPublicReviewReportSubmit),
                      button: true,
                      child: CyNativeButton(
                        key: const Key('merchant-review-action-submit'),
                        label: widget.editing
                            ? stringsOf(context).merchantManageReviewSave
                            : (isReply ? stringsOf(context).merchantManageReviewSend : stringsOf(context).merchantPublicReviewReportSubmit),
                        loading: _submitting,
                        onPressed: _submitting ? null : _submit,
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

int _reviewRequestSequence = 0;

String _newReviewRequestId(MerchantReviewAction action) {
  _reviewRequestSequence += 1;
  final String kind = action == MerchantReviewAction.reply ? 'reply' : 'report';
  final String time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return 'mr-$kind-$time-${_reviewRequestSequence.toRadixString(36)}';
}

String _newReplyDeleteRequestId() {
  _reviewRequestSequence += 1;
  final String time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return 'mr-reply-del-$time-${_reviewRequestSequence.toRadixString(36)}';
}

String? _minute(DateTime? value) {
  if (value == null) return null;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
