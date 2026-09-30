import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_review_api.dart';
import '../../data/models/merchant_review.dart';

typedef MerchantPublicReviewRequestIdFactory =
    String Function(MerchantReviewAction action);
typedef MerchantReviewImageSourceChooser =
    Future<CyImagePickSource?> Function(BuildContext context);
typedef MerchantReviewImagePicker =
    Future<List<String>> Function(CyImagePickSource source, int limit);
typedef MerchantReviewImageUploader = Future<String> Function(String filePath);
typedef MerchantReviewImagePurposeConfirmer =
    Future<bool> Function(BuildContext context);
typedef MerchantReviewImageSettingsOpener = Future<bool> Function();

Future<CyImagePickSource?> _chooseImageSource(BuildContext context) =>
    cyChooseImageSource(context);

Future<bool> _confirmImagePurpose(BuildContext context) => cyConfirm(
  context,
  title: '添加真实到店照片',
  content: '仅在你主动选择后访问相机或照片，用于补充这次真实到店评价；不会在后台访问其他图片。',
  cancelText: '暂不添加',
  confirmText: '继续选择',
);

Future<bool> _openImageSettings() => Geolocator.openAppSettings();

Future<List<String>> _pickImages(CyImagePickSource source, int limit) async {
  final ImagePicker picker = ImagePicker();
  if (source == CyImagePickSource.gallery && limit > 1) {
    final List<XFile> files = await picker.pickMultiImage(
      limit: limit,
      imageQuality: 90,
    );
    return files.map((XFile file) => file.path).toList(growable: false);
  }
  final XFile? file = await picker.pickImage(
    source: source == CyImagePickSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    imageQuality: 90,
  );
  return file == null ? const <String>[] : <String>[file.path];
}

class MerchantPublicReviewsPage extends StatefulWidget {
  const MerchantPublicReviewsPage({
    super.key,
    required this.api,
    required this.merchantRowId,
    required this.merchantOwnerMemberId,
    required this.uploadImage,
    this.requestIdFactory,
    this.chooseImageSource = _chooseImageSource,
    this.pickImages = _pickImages,
    this.confirmImagePurpose = _confirmImagePurpose,
    this.openImageSettings = _openImageSettings,
    this.imageUrlPolicy = MerchantReviewImageUrlPolicy.failClosed,
    this.liquidGlassSupported,
  });

  final MerchantPublicReviewGateway api;
  // ★ 主体 ID 可空:**不**在构造期 assert >0(和 public-home 同口径)。
  //   坏深链(缺参、非数字、0)是页面要承接的一个真实界面态,不是编程
  //   错误 —— 构造期断言会让 Debug 整屏红、没有出口(b1-sim-merchant-4 P2 实撞)。
  final int? merchantRowId;
  final int? merchantOwnerMemberId;
  final MerchantReviewImageUploader uploadImage;
  final MerchantPublicReviewRequestIdFactory? requestIdFactory;
  final MerchantReviewImageSourceChooser chooseImageSource;
  final MerchantReviewImagePicker pickImages;
  final MerchantReviewImagePurposeConfirmer confirmImagePurpose;
  final MerchantReviewImageSettingsOpener openImageSettings;
  final MerchantReviewImageUrlPolicy imageUrlPolicy;
  final bool? liquidGlassSupported;

  /// 链接可打开的判据:两个主体 ID 都有效(>0)。缺任一 → 页面渲染
  /// 「链接参数无效」态,不去打一个猜出来的 id(对齐 public-home 口径)。
  bool get _linkValid =>
      (merchantRowId ?? 0) > 0 && (merchantOwnerMemberId ?? 0) > 0;

  @override
  State<MerchantPublicReviewsPage> createState() =>
      _MerchantPublicReviewsPageState();
}

class _MerchantPublicReviewsPageState extends State<MerchantPublicReviewsPage> {
  static const int _pageSize = 20;

  final TextEditingController _contentController = TextEditingController();
  final List<String> _uploadedImages = <String>[];
  List<MerchantReviewItem> _items = const <MerchantReviewItem>[];
  MerchantReviewEligibility? _eligibility;
  int _rating = 0;
  int _pageNum = 1;
  int _total = 0;
  double? _averageRating;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _uploading = false;
  bool _imagePurposeAccepted = false;
  bool _submitting = false;
  Object? _error;
  String? _submitError;
  String? _createRequestId;
  String? _createFingerprint;
  late MerchantReviewImageUrlPolicy _imageUrlPolicy;
  int _sequence = 0;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _imageUrlPolicy = widget.imageUrlPolicy;
    _contentController.addListener(_draftChanged);
    if (widget._linkValid) Future<void>.microtask(_loadFirstPage);
  }

  @override
  void dispose() {
    _requestToken += 1;
    _contentController
      ..removeListener(_draftChanged)
      ..dispose();
    super.dispose();
  }

  void _draftChanged() {
    if (!mounted) return;
    setState(() => _submitError = null);
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
      final MerchantReviewPage page = await widget.api.publicPage(
        merchantRowId: widget.merchantRowId!,
        pageNum: 1,
        pageSize: _pageSize,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _items = page.items;
        _pageNum = page.pageNum;
        _total = page.total;
        _averageRating = page.averageRating;
        _eligibility = page.eligibility;
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
      final MerchantReviewPage page = await widget.api.publicPage(
        merchantRowId: widget.merchantRowId!,
        pageNum: _pageNum + 1,
        pageSize: _pageSize,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _items = <MerchantReviewItem>[..._items, ...page.items];
        _pageNum = page.pageNum;
        _total = page.total;
        _averageRating = page.averageRating;
        _eligibility = page.eligibility;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _requestToken) return;
      setState(() => _loadingMore = false);
    }
  }

  MerchantReviewCreateDraft? get _draft {
    final int? registrationId = _eligibility?.registrationId;
    if (registrationId == null) return null;
    return MerchantReviewCreateDraft(
      merchantRowId: widget.merchantRowId!,
      registrationId: registrationId,
      rating: _rating,
      content: _contentController.text,
      imageUrls: List<String>.unmodifiable(_uploadedImages),
      imageUrlPolicy: _imageUrlPolicy,
    );
  }

  String _requestId(MerchantReviewAction action) {
    final String? injected = widget.requestIdFactory?.call(action);
    if (injected != null) return injected;
    _sequence += 1;
    return 'mr-${action.name}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${_sequence.toRadixString(36)}';
  }

  Future<void> _addImages() async {
    if (_uploading || _submitting || _uploadedImages.length >= 9) return;
    if (!_imagePurposeAccepted) {
      final bool accepted = await widget.confirmImagePurpose(context);
      if (!accepted || !mounted) return;
      _imagePurposeAccepted = true;
    }
    setState(() {
      _uploading = true;
      _submitError = null;
    });
    try {
      final CyImagePickSource? source = await widget.chooseImageSource(context);
      if (source == null || !mounted) return;
      final int remaining = 9 - _uploadedImages.length;
      final List<String> paths = await widget.pickImages(source, remaining);
      if (paths.isEmpty || !mounted) return;
      final List<String> uploaded = <String>[];
      MerchantReviewImageUrlPolicy nextPolicy = _imageUrlPolicy;
      for (final String path in paths.take(remaining)) {
        final String uploadReceipt = await widget.uploadImage(path);
        nextPolicy = nextPolicy.allowingTrustedUploadReceipt(uploadReceipt);
        uploaded.add(uploadReceipt);
      }
      if (!mounted) return;
      setState(() {
        _imageUrlPolicy = nextPolicy;
        _uploadedImages.addAll(uploaded);
      });
    } on PlatformException {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        '需要照片权限，请到系统设置开启后重试',
        isError: true,
        actionLabel: '去设置',
        onAction: () => unawaited(widget.openImageSettings()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitError = _errorText(error, '图片上传失败'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final MerchantReviewCreateDraft? draft = _draft;
    final String? validationError = draft == null
        ? '核销资格已失效，请刷新'
        : draft.validationError;
    if (validationError != null) {
      setState(() => _submitError = validationError);
      return;
    }
    final String fingerprint = draft!.fingerprint;
    if (_createRequestId == null || _createFingerprint != fingerprint) {
      _createRequestId = _requestId(MerchantReviewAction.create);
      _createFingerprint = fingerprint;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final MerchantReviewReceipt receipt = await widget.api.create(
        draft: draft,
        requestId: _createRequestId!,
      );
      if (!mounted) return;
      _createRequestId = null;
      _createFingerprint = null;
      _contentController.clear();
      setState(() {
        _submitting = false;
        _rating = 0;
        _uploadedImages.clear();
        _imageUrlPolicy = widget.imageUrlPolicy;
      });
      final String message = switch (receipt.status) {
        'VISIBLE' => '该评价已通过复核并公开',
        'HIDDEN' => '该评价未通过平台复核',
        _ => '评价已提交，等待平台复核',
      };
      CyNativeNotice.show(context, message);
      await _loadFirstPage();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = _errorText(error, '评价提交失败');
      });
    }
  }

  Future<void> _report(MerchantReviewItem review) async {
    final MerchantReviewReceipt? receipt =
        await showCupertinoModalPopup<MerchantReviewReceipt>(
          context: context,
          semanticsDismissible: true,
          builder: (BuildContext sheetContext) => _PublicReportSheet(
            api: widget.api,
            merchantOwnerMemberId: widget.merchantOwnerMemberId!,
            review: review,
            requestIdFactory: widget.requestIdFactory,
            liquidGlassSupported: widget.liquidGlassSupported,
          ),
        );
    if (!mounted || receipt == null) return;
    CyNativeNotice.show(context, '举报已提交，等待平台复核');
  }

  Future<void> _previewImages(List<Uri> urls, int initialIndex) {
    return showCupertinoModalPopup<void>(
      context: context,
      semanticsDismissible: true,
      builder: (BuildContext previewContext) =>
          _PublicReviewImagePreview(urls: urls, initialIndex: initialIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(middle: Text('真实到店评价')),
      child: SafeArea(bottom: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    // ★ 缺参/0/解析不出数字是**一个界面态**(同 public-home 与小程序
    //   `state === 'invalid'` 口径):说清是链接的问题,不发请求、不给
    //   点了没用的重试;StatusView 自带「回首页」出口,不会白屏困死。
    if (!widget._linkValid) {
      return const StatusView(
        message: '链接参数无效',
        sub: '这个链接缺少商家或店主信息，无法打开这份口碑页。',
        large: true,
      );
    }
    if (_loading) {
      return const CySkeleton(type: CySkeletonType.card, count: 4);
    }
    if (_error != null) {
      return StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: '评价加载失败',
        sub: _error.toString(),
        onRetry: _loadFirstPage,
        retryLabel: '重新加载',
        large: true,
      );
    }
    return CustomScrollView(
      key: const Key('public-review-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        CupertinoSliverRefreshControl(onRefresh: _loadFirstPage),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space8,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              _hero(context),
              const SizedBox(height: CyTokens.space4),
              if (_eligibility?.canCreate == true)
                _composer(context)
              else
                _eligibilityNote(context),
              const SizedBox(height: CyTokens.space5),
              _listHead(context),
              const SizedBox(height: CyTokens.space3),
              for (final MerchantReviewItem item in _items) ...<Widget>[
                _reviewCard(context, item),
                const SizedBox(height: CyTokens.space4),
              ],
              _footer(context),
            ],
          ),
        ),
      ],
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
                Text('真实到店体验', style: textTheme.headlineSmall),
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
                _averageRating?.toStringAsFixed(1) ?? '暂无',
                style: textTheme.headlineMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                '$_total 条评价',
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

  Widget _composer(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final MerchantReviewCreateDraft? draft = _draft;
    final bool canSubmit =
        !_submitting && !_uploading && draft?.validationError == null;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('写下这次体验', style: textTheme.titleMedium),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      '核销已验证 · 提交后平台复核，过审后公开；原评不可编辑',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_contentController.text.length} / 1000',
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          Semantics(
            label: '体验评分',
            child: Row(
              children: <Widget>[
                for (int star = 1; star <= 5; star++)
                  CupertinoButton(
                    key: Key('public-review-star-$star'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            _rating = star;
                            _submitError = null;
                          }),
                    child: Icon(
                      star <= _rating
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      color: palette.textPrimary,
                      semanticLabel: '$star 星',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          CupertinoTextField(
            key: const Key('public-review-content'),
            controller: _contentController,
            minLines: 4,
            maxLines: 7,
            maxLength: 1000,
            enabled: !_submitting,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            placeholder: '说说环境、服务和真实到店感受',
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: palette.inputBgEmpty,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double extent =
                  (constraints.maxWidth - CyTokens.space2 * 2) / 3;
              return Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space2,
                children: <Widget>[
                  for (int index = 0; index < _uploadedImages.length; index++)
                    _uploadedImage(context, index, extent),
                  if (_uploadedImages.length < 9)
                    SizedBox.square(
                      dimension: extent,
                      child: CupertinoButton(
                        key: const Key('public-review-add-image'),
                        minimumSize: Size.square(extent),
                        padding: EdgeInsets.zero,
                        onPressed: _uploading || _submitting
                            ? null
                            : _addImages,
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: palette.bgSubtle,
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusMd,
                            ),
                            border: Border.all(color: palette.borderSubtle),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              _uploading
                                  ? const CupertinoActivityIndicator()
                                  : const Icon(
                                      CupertinoIcons.photo_on_rectangle,
                                    ),
                              const SizedBox(height: CyTokens.space1),
                              Text(
                                '添加图片',
                                style: textTheme.labelSmall?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            '最多 9 张；图片必须来自城瘾现有上传链路。',
            style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          if (_submitError != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              _submitError!,
              style: textTheme.bodySmall?.copyWith(
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space3),
          SizedBox(
            width: double.infinity,
            child: CyNativeButton(
              key: const Key('public-review-submit'),
              label: _submitting ? '提交中…' : '提交真实评价',
              loading: _submitting,
              onPressed: canSubmit ? _submit : null,
              liquidGlassSupported: widget.liquidGlassSupported,
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadedImage(BuildContext context, int index, double extent) {
    return SizedBox.square(
      key: Key('public-review-uploaded-$index'),
      dimension: extent,
      child: Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            child: CyNetImage(
              _uploadedImages[index],
              width: extent,
              height: extent,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CupertinoButton(
              key: Key('public-review-remove-image-$index'),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: _submitting
                  ? null
                  : () => setState(() => _uploadedImages.removeAt(index)),
              child: const Icon(
                CupertinoIcons.xmark_circle_fill,
                semanticLabel: '删除图片',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eligibilityNote(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final MerchantReviewEligibility eligibility =
        _eligibility ??
        const MerchantReviewEligibility(
          canCreate: false,
          reasonCode: 'UNAVAILABLE',
          registrationId: null,
        );
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(eligibility.title, style: textTheme.titleMedium),
          const SizedBox(height: CyTokens.space1),
          Text(
            eligibility.subtitle,
            style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _listHead(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('到店评价', style: textTheme.titleMedium),
        const SizedBox(height: CyTokens.space1),
        Text(
          '公开列表仅展示平台当前判定为 VISIBLE 的内容',
          style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }

  Widget _reviewCard(BuildContext context, MerchantReviewItem review) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      key: Key('public-review-${review.id}'),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
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
                    Text(review.authorNickname, style: textTheme.titleSmall),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      _minute(review.createTime) ?? '时间待确认',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (review.verifiedRedemption)
                Text(
                  '核销已验证',
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
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
                  ),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          Text(review.content, style: textTheme.bodyMedium),
          if (review.imageUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double extent =
                    (constraints.maxWidth - CyTokens.space2 * 2) / 3;
                return Wrap(
                  spacing: CyTokens.space2,
                  runSpacing: CyTokens.space2,
                  children: <Widget>[
                    for (
                      int index = 0;
                      index < review.imageUrls.length;
                      index++
                    )
                      SizedBox.square(
                        dimension: extent,
                        child: CupertinoButton(
                          key: Key('public-review-image-${review.id}-$index'),
                          minimumSize: Size.square(extent),
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              _previewImages(review.imageUrls, index),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusMd,
                            ),
                            child: CyNetImage(
                              review.imageUrls[index].toString(),
                              width: extent,
                              height: extent,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
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
                  Text('商家公开回复', style: textTheme.labelMedium),
                  const SizedBox(height: CyTokens.space1),
                  Text(review.merchantReply!),
                  if (review.repliedAt != null) ...<Widget>[
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      _minute(review.repliedAt)!,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (review.canReport) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                key: Key('public-review-report-${review.id}'),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                ),
                onPressed: () => _report(review),
                child: const Text('举报'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(CyTokens.space4),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (_hasMore) {
      return Center(
        child: CupertinoButton(
          key: const Key('public-review-load-more'),
          onPressed: _loadMore,
          child: const Text('加载更多'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(CyTokens.space3),
      child: Center(
        child: Text(
          _items.isEmpty ? '' : '已经到底了',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: CyPalette.of(context).textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PublicReviewImagePreview extends StatefulWidget {
  const _PublicReviewImagePreview({
    required this.urls,
    required this.initialIndex,
  });

  final List<Uri> urls;
  final int initialIndex;

  @override
  State<_PublicReviewImagePreview> createState() =>
      _PublicReviewImagePreviewState();
}

class _PublicReviewImagePreviewState extends State<_PublicReviewImagePreview> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPopupSurface(
      key: const Key('public-review-image-preview'),
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(width: 44),
                  Expanded(
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('public-review-image-close'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      semanticLabel: '关闭评价图片预览',
                    ),
                  ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.urls.length,
                  onPageChanged: (int index) => setState(() => _index = index),
                  itemBuilder: (BuildContext context, int index) =>
                      InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Center(
                          child: CyNetImage(
                            widget.urls[index].toString(),
                            width: double.infinity,
                            fit: BoxFit.contain,
                          ),
                        ),
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

class _PublicReportSheet extends StatefulWidget {
  const _PublicReportSheet({
    required this.api,
    required this.merchantOwnerMemberId,
    required this.review,
    required this.requestIdFactory,
    required this.liquidGlassSupported,
  });

  final MerchantPublicReviewGateway api;
  final int merchantOwnerMemberId;
  final MerchantReviewItem review;
  final MerchantPublicReviewRequestIdFactory? requestIdFactory;
  final bool? liquidGlassSupported;

  @override
  State<_PublicReportSheet> createState() => _PublicReportSheetState();
}

class _PublicReportSheetState extends State<_PublicReportSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _requestId;
  String? _fingerprint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _newRequestId() =>
      widget.requestIdFactory?.call(MerchantReviewAction.report) ??
      'mr-report-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  Future<void> _submit() async {
    if (_submitting) return;
    final MerchantReviewReportDraft draft = MerchantReviewReportDraft(
      reviewId: widget.review.id,
      expectedVersion: widget.review.version,
      reason: _controller.text,
    );
    final String? validationError = draft.validationError;
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    if (_requestId == null || _fingerprint != draft.fingerprint) {
      _requestId = _newRequestId();
      _fingerprint = draft.fingerprint;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final MerchantReviewReceipt receipt = await widget.api.reportPublic(
        merchantOwnerMemberId: widget.merchantOwnerMemberId,
        draft: draft,
        requestId: _requestId!,
      );
      if (!mounted) return;
      Navigator.of(context).pop(receipt);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _errorText(error, '举报提交失败');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text('提交平台复核', style: textTheme.titleLarge)),
                  CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                '举报只会进入统一审核队列，不代表内容已经下架。',
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              CupertinoTextField(
                key: const Key('public-review-report-input'),
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                enabled: !_submitting,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                placeholder: '请说明不实、攻击、广告或其他违规事实',
                padding: const EdgeInsets.all(CyTokens.space3),
                decoration: BoxDecoration(
                  color: palette.inputBgEmpty,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ],
              const SizedBox(height: CyTokens.space3),
              CyNativeButton(
                key: const Key('public-review-report-submit'),
                label: _submitting ? '提交中…' : '提交举报',
                loading: _submitting,
                onPressed: _submitting ? null : _submit,
                liquidGlassSupported: widget.liquidGlassSupported,
              ),
            ],
          ),
        ),
      ),
    );
  }
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

String _errorText(Object error, String fallback) {
  final String text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty ? fallback : text;
}

String? _minute(DateTime? value) {
  if (value == null) return null;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
