import '../../core/map/map_launcher.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';
import 'nearby_explore_day.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/city_node_detail.dart';
import '../../data/models/roam_merchant_info.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'roam_poi_interaction_logic.dart';

/// 据点(POI)详情(对齐小程序 `subpackageRoam/poi-detail` + scene-roam-poi-detail):
/// 商家 hero + 招牌主推 + 到店互动 + 相册 + 品牌故事 + 基本信息。
///
/// ★ 完成打卡的动作不能撞后端报错:未上线/已下线/已完成的据点直接禁用按钮;
///   选项问答没配好选项也是禁用,别让用户点下去再撞「答案不正确」。
class RoamPoiDetailPage extends ConsumerStatefulWidget {
  const RoamPoiDetailPage({super.key, required this.poiId});

  final int poiId;

  @override
  ConsumerState<RoamPoiDetailPage> createState() => _RoamPoiDetailPageState();
}

enum _LoadState { loading, error, empty, needLogin, ready }

class _RoamPoiNativePage extends StatelessWidget {
  const _RoamPoiNativePage({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: title == null ? null : Text(title!),
        backgroundColor: Colors.transparent,
        automaticBackgroundVisibility: false,
        border: null,
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: child),
      ),
    );
  }
}

class _RoamPoiDetailPageState extends ConsumerState<RoamPoiDetailPage> {
  _LoadState _state = _LoadState.loading;
  String _errorText = '据点暂时打不开';
  CityNodeDetail? _node;
  RoamMerchantInfo? _merchant;
  RoamFeatured? _featured;

  bool _completing = false;
  RoamInteractionRecovery _recovery = RoamInteractionRecovery.none;
  String _recoveryTitle = '';
  String _recoveryText = '';
  VoidCallback? _recoveryRetry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, msg, isError: isError);
  }

  Future<void> _load() async {
    setState(() {
      _state = _LoadState.loading;
      _node = null;
      _merchant = null;
      _featured = null;
    });
    // 游客:`/api/city/nodes/{id}` 契约 auth=required(真源
    // get-auth-matrix-contract.test.js:42),必撞 401 —— 先不发这个注定失败
    // 的请求,由页内登录门解释(B1 二轮报告 N1:401 说成「稍后可以重新读取」,
    // 重试对游客永远是死路;同 #208 口径)。
    if (!ref.read(authControllerProvider).isLoggedIn) {
      if (!mounted) return;
      setState(() => _state = _LoadState.needLogin);
      return;
    }
    try {
      final CityNodeDetail node = await ref
          .read(roamApiProvider)
          .nodeDetail(widget.poiId);
      RoamMerchantInfo? merchant;
      RoamFeatured? featured;
      if (node.merchantId != null && node.merchantId! > 0) {
        try {
          final (RoamMerchantInfo m, RoamFeatured? f) = await ref
              .read(roamApiProvider)
              .publicMerchantDetail(node.merchantId!);
          merchant = m;
          featured = f;
        } catch (_) {
          // 商家信息读不到不影响据点本体:据点卡仍可用,
          // 商家区退成「没读到」占位(与小程序两段加载一致)。
          merchant = null;
          featured = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _node = node;
        _merchant = merchant;
        _featured = featured;
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      // 401 = 后端以「未登录」表态(token 失效也会走到这里),不是故障:
      //   说成「稍后可以重新读取」是把人往死路上引。走登录门。
      if (isUnauthorizedError(e)) {
        setState(() => _state = _LoadState.needLogin);
        return;
      }
      final String msg = e.toString().replaceFirst('Exception: ', '');
      final bool notFound = msg.contains('节点不存在') || msg.contains('据点不存在');
      setState(() {
        _state = notFound ? _LoadState.empty : _LoadState.error;
        _errorText = notFound ? '找不到这个据点' : '据点暂时打不开';
      });
    }
  }

  // ===== 收藏 =====

  Future<void> _toggleFavorite() async {
    if (!await requireLogin(context, ref)) return;
    final CityNodeDetail? node = _node;
    if (node == null) return;
    try {
      final bool now = await ref
          .read(roamApiProvider)
          .toggleFavorite(widget.poiId);
      if (!mounted) return;
      setState(() => _node = _copyNode(node, favorited: now));
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  /// 导航到据点。★ 结果分三档各说各的 —— 见 map_launcher.dart。
  Future<void> _navigate(CityNodeDetail node) async {
    final MapLaunchResult r = await launchNavigation(
      lat: node.lat,
      lng: node.lng,
      name: node.name,
      address: node.merchantAddress,
      isIOS: Platform.isIOS,
    );
    if (!mounted) return;
    final String msg = mapLaunchMessage(r);
    if (msg.isEmpty) return; // 打开了就别打扰
    CyNativeNotice.show(context, msg, isError: true);
  }

  static CityNodeDetail _copyNode(
    CityNodeDetail n, {
    bool? favorited,
    bool? completed,
  }) {
    return CityNodeDetail(
      poiId: n.poiId,
      name: n.name,
      description: n.description,
      lat: n.lat,
      lng: n.lng,
      radiusM: n.radiusM,
      nodeLevel: n.nodeLevel,
      tags: n.tags,
      coverImg: n.coverImg,
      status: n.status,
      merchantId: n.merchantId,
      merchantName: n.merchantName,
      merchantLogo: n.merchantLogo,
      merchantAddress: n.merchantAddress,
      templateTitle: n.templateTitle,
      interactionType: n.interactionType,
      validationMethod: n.validationMethod,
      couponId: n.couponId,
      questionName: n.questionName,
      questionA: n.questionA,
      questionB: n.questionB,
      questionC: n.questionC,
      questionD: n.questionD,
      completed: completed ?? n.completed,
      favorited: favorited ?? n.favorited,
    );
  }

  // ===== 到店互动 =====

  void _clearRecovery() {
    setState(() {
      _recovery = RoamInteractionRecovery.none;
      _recoveryTitle = '';
      _recoveryText = '';
      _recoveryRetry = null;
    });
  }

  void _setRecovery(
    RoamInteractionRecovery state,
    String title,
    String text, [
    VoidCallback? retry,
  ]) {
    setState(() {
      _recovery = state;
      _recoveryTitle = title;
      _recoveryText = text;
      _recoveryRetry = retry;
    });
  }

  Future<void> _startInteract() async {
    if (!await requireLogin(context, ref)) return;
    final CityNodeDetail? node = _node;
    if (node == null || _completing) return;
    _clearRecovery();
    switch (interactionKindFor(node.validationMethod)) {
      case RoamInteractionKind.text:
        await _askAnswer(node);
      case RoamInteractionKind.choice:
        await _askChoice(node);
      case RoamInteractionKind.photo:
        await _pickPhoto();
      case RoamInteractionKind.scan:
        await _scanPosterCode();
      case RoamInteractionKind.gps:
        await _complete();
    }
  }

  Future<void> _askAnswer(CityNodeDetail node) async {
    final String? answer = await showCySystemTextInputAlert(
      context: context,
      title: '完成互动',
      placeholder: '输入答案 / 暗号',
      confirmText: '确定',
      keyboardKind: CySystemKeyboardKind.text,
    );
    if (answer == null) return;
    await _complete(answer: answer);
  }

  Future<void> _askChoice(CityNodeDetail node) async {
    final List<CityNodeChoice> choices = node.choices;
    if (choices.isEmpty) {
      _toast('这道题还没配好选项', isError: true);
      return;
    }
    final String? picked = await showCupertinoModalPopup<String>(
      context: context,
      semanticsDismissible: true,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          node.questionName?.isNotEmpty == true ? node.questionName! : '完成互动',
        ),
        actions: choices
            .map(
              (CityNodeChoice c) => CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, c.letter),
                child: Text(c.display),
              ),
            )
            .toList(growable: false),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
    if (picked == null) return;
    await _complete(answer: picked);
  }

  Future<void> _pickPhoto() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );
    if (file == null) return;
    _toast('照片上传中…');
    try {
      final String url = await ref.read(playApiProvider).uploadImage(file.path);
      if (!mounted) return;
      await _complete(photoUrl: url);
    } catch (e) {
      if (!mounted) return;
      _toast(
        '照片没传上去:${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    }
  }

  Future<void> _scanPosterCode() async {
    // 对照表 #11:扫码 = 全屏 + 系统返回。`showGeneralDialog` 的路由**不渲染**
    // 导航返回钮(探针实证),叠上 `barrierDismissible: false` 就是扫不到码
    // 出不去的死角。走 CupertinoPageRoute:返回钮 + 边缘手势都在。
    final String? code = await Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(builder: (_) => const _PosterScanDialog()),
    );
    if (code == null) return;
    await _complete(code: code);
  }

  /// 附近的探店日推荐。
  ///
  /// ★★ **没有就一声不响** —— 后端「附近没合适的」返回 `success(null)`,
  ///   那是正常态。弹一句「附近没有活动」等于为一件没发生的事打断玩家。
  /// ★ 这是顺带推荐,失败也不提示(provider 自己吞成 null)。
  Future<void> _suggestNearbyExploreDay(double lat, double lng) async {
    final NearbyExploreDay? d = await ref.read(
      nearbyExploreDayProvider((lat, lng)).future,
    );
    if (d == null || !mounted) return;
    final String? distance = d.distanceText;
    final bool go = await cyConfirm(
      context,
      title: '附近有个探店日',
      // 距离拿不到就不写这一行 —— 别编一个「0 米」。
      content: <String>[
        d.title,
        if (d.subtitle.isNotEmpty) d.subtitle,
        if (distance != null) '离你 $distance',
        if (d.meetingPoint.isNotEmpty) '集合点:${d.meetingPoint}',
      ].join('\n'),
      confirmText: '去看看',
      cancelText: '不了',
    );
    if (go && mounted) context.push('/activity/${d.activityId}');
  }

  Future<void> _complete({
    String answer = '',
    String photoUrl = '',
    String code = '',
  }) async {
    final CityNodeDetail? node = _node;
    if (node == null) return;
    setState(() => _completing = true);
    _clearRecovery();
    try {
      final Position pos = await Geolocator.getCurrentPosition();
      final CityNodeCompleteResult result = await ref
          .read(roamApiProvider)
          .completeNode(
            widget.poiId,
            lat: pos.latitude,
            lng: pos.longitude,
            answer: answer,
            photoUrl: photoUrl,
            code: code,
          );
      if (!mounted) return;
      setState(() {
        _completing = false;
        _node = _copyNode(node, completed: true);
      });
      if (result.needRedeem) {
        // 有券据点:引导玩家出示据点核销码给商家扫码领券。
        context.push(
          Uri(
            path: '/roam/citynode-code',
            queryParameters: <String, String>{
              'poiId': '${widget.poiId}',
              'name': node.name,
            },
          ).toString(),
        );
      } else {
        _toast(result.alreadyClaimed ? '你已完成过' : '打卡成功');
        // ★ 打完卡顺带看看附近有没有探店日 —— 玩家此刻正好在街上。
        //   没有就什么都不发生(后端「附近没活动」返 success(null),是正常态)。
        await _suggestNearbyExploreDay(pos.latitude, pos.longitude);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _completing = false);
      final String msg = e.toString().replaceFirst('Exception: ', '');
      if (isLocationCancel(msg)) {
        _clearRecovery();
        return;
      }
      if (isLocationPermissionFailure(msg)) {
        _setRecovery(
          RoamInteractionRecovery.locationPermission,
          '需要定位权限',
          '在设置里允许定位，返回后会继续本次打卡。',
          () => _complete(answer: answer, photoUrl: photoUrl, code: code),
        );
        return;
      }
      // 后端原文(答案不正确/离据点太远/已核销等)是给玩家的可行动提示,原样说。
      _toast(msg.isEmpty ? '网络异常' : msg, isError: true);
    }
  }

  Future<void> _recoverInteraction() async {
    switch (_recovery) {
      case RoamInteractionRecovery.cameraPermission:
      case RoamInteractionRecovery.locationPermission:
        await Geolocator.openAppSettings();
        if (!mounted) return;
        final VoidCallback? retry = _recoveryRetry;
        if (retry != null) {
          _clearRecovery();
          retry();
        }
      case RoamInteractionRecovery.retry:
        final VoidCallback? retry = _recoveryRetry;
        _clearRecovery();
        retry?.call();
      case RoamInteractionRecovery.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RoamPoiNativePage(
      child: switch (_state) {
        _LoadState.loading => const Center(child: CupertinoActivityIndicator()),
        _LoadState.error => StatusView(
          icon: CupertinoIcons.location_slash,
          message: _errorText,
          sub: '这次没有读到据点信息，稍后可以重新读取',
          onRetry: _load,
        ),
        _LoadState.empty => const StatusView(
          icon: CupertinoIcons.map_pin_slash,
          message: '找不到这个据点',
          sub: '该点位可能已经下线，请返回地图继续探索',
        ),
        // ★ 游客/失效态:给「登录后查看 + 去登录」门,不弹假「稍后重试」——
        //   写法同 stamp-album/camera/nearby 的 #208 页内门;StatusView
        //   自带无栈直达时的「回首页」出口。
        _LoadState.needLogin => StatusView(
          key: const Key('roam-poi-login-gate'),
          message: '登录后查看这个据点',
          sub: '据点信息要登录后才能读取，登录完就能看。',
          icon: CupertinoIcons.lock,
          large: true,
          retryLabel: '去登录',
          onRetry: () async {
            if (!await requireLogin(context, ref)) return;
            if (!mounted) return;
            _load();
          },
        ),
        _LoadState.ready => _buildBody(),
      },
    );
  }

  Widget _buildBody() {
    final CityNodeDetail node = _node!;
    final RoamMerchantInfo? merchant = _merchant;
    final bool disabled =
        _completing || node.completed || node.choicesNotConfigured;
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space6),
      children: <Widget>[
        if (merchant != null) _MerchantHero(merchant: merchant),
        if (_featured != null && _featured!.isUsable)
          _FeaturedCard(featured: _featured!),
        _NodeCard(node: node),
        // ★ 导航到这个据点。这个产品的核心动作就是「走到那儿」,
        //   而 App 此前**完全没有唤起地图的能力** —— 用户只能手抄地址。
        //   走兜底链(高德 → 系统地图 → 复制地址),不会出现按了没反应。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            0,
          ),
          child: CyNativeButton(
            key: const Key('poi-navigate'),
            width: double.infinity,
            role: CyNativeButtonRole.secondary,
            onPressed: () => _navigate(node),
            icon: const CyNativeButtonIcon(
              sfSymbol: 'location.fill',
              fallback: CupertinoIcons.location_fill,
            ),
            label: '导航过去',
          ),
        ),
        if (_recovery != RoamInteractionRecovery.none)
          _RecoveryCard(
            title: _recoveryTitle,
            text: _recoveryText,
            actionLabel: _recovery == RoamInteractionRecovery.retry
                ? '重试'
                : '去设置',
            onAction: _recoverInteraction,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: CyNativeButton(
                  width: double.infinity,
                  role: CyNativeButtonRole.secondary,
                  onPressed: _completing ? null : _toggleFavorite,
                  label: node.favorited ? '已收藏' : '收藏',
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              // 真源 pages/roam/index.js:480-484 `openCityStamp`:
              // 「投一张」收半屏 → citystamp(kind=sign, place=据点名)。
              // 写是代价、看是回报,入口在「到了这一站」这里,不在集邮册里。
              Expanded(
                child: Semantics(
                  button: true,
                  label: '在${node.name.isEmpty ? '这一站' : node.name}投一张换一张',
                  excludeSemantics: true,
                  child: CyNativeButton(
                    key: const Key('roam-poi-citystamp-entry'),
                    width: double.infinity,
                    role: CyNativeButtonRole.secondary,
                    onPressed: () => context.push(
                      '/roam/citystamp?kind=sign&place=${Uri.encodeComponent(node.name.isEmpty ? '这一站' : node.name)}',
                    ),
                    label: '投一张',
                  ),
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                flex: 2,
                child: CyNativeButton(
                  width: double.infinity,
                  onPressed: disabled ? null : _startInteract,
                  label: interactButtonLabel(
                    completed: node.completed,
                    completing: _completing,
                  ),
                  loading: _completing,
                ),
              ),
            ],
          ),
        ),
        if (node.completed)
          const Padding(
            padding: EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              '这个据点你已完成过，每人每据点仅一次',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: CyTokens.textTertiary,
              ),
            ),
          ),
        if (merchant != null && merchant.gallery.isNotEmpty)
          _GallerySection(gallery: merchant.gallery),
        if (merchant != null &&
            ((merchant.storyTitle ?? '').isNotEmpty ||
                (merchant.description ?? '').isNotEmpty))
          _StorySection(merchant: merchant),
        if (merchant != null) _InfoSection(merchant: merchant),
      ],
    );
  }
}

class _MerchantHero extends StatelessWidget {
  const _MerchantHero({required this.merchant});

  final RoamMerchantInfo merchant;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if ((merchant.coverImage ?? '').isNotEmpty)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              merchant.coverImage!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: CyTokens.bgSurfaceSubtle,
                child: const Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(CyTokens.space4),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: (merchant.logo ?? '').isNotEmpty
                      ? Image.network(
                          merchant.logo!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: CyTokens.bgSurfaceSubtle,
                            child: const Icon(Icons.storefront_outlined),
                          ),
                        )
                      : Container(
                          color: CyTokens.bgSurfaceSubtle,
                          child: const Icon(Icons.storefront_outlined),
                        ),
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      merchant.name ?? '商家',
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: CyTokens.typeCardTitle,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      merchant.isOpen ? '● 营业中' : '● 已打烊',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: CyTokens.typeCaption,
                        color: CyTokens.textSecondary,
                      ),
                    ),
                    if ((merchant.cityRole ?? '').isNotEmpty)
                      Text(
                        merchant.cityRole!,
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: CyTokens.typeCaption,
                          color: CyTokens.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (merchant.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              0,
              CyTokens.pageX,
              CyTokens.space3,
            ),
            child: Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: merchant.tags
                  .map(
                    (String t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space2_5,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: CyTokens.bgSurfaceSubtle,
                        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                      ),
                      child: Text(
                        t,
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: CyTokens.typeCaption,
                          color: CyTokens.textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.featured});

  final RoamFeatured featured;

  /// 源 scene-roam-poi-detail/index.js:427-430 `openFeatured`:
  /// 1=店内活动 → 活动详情;2=券 → 券包。actionable 为假时保持纯展示。
  String? get _route => switch (featured.featuredType) {
    1 => '/activity/${featured.featuredId}',
    2 => '/coupons',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String? route = featured.actionable ? _route : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '招牌主推',
            style: textTheme.titleMedium?.copyWith(
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Semantics(
            button: route != null,
            label: '查看${featured.name}',
            excludeSemantics: true,
            child: GestureDetector(
              key: const Key('roam-poi-featured'),
              behavior: HitTestBehavior.opaque,
              onTap: route == null ? null : () => context.push(route),
              child: Row(
                children: <Widget>[
                  if (featured.image.isNotEmpty) ...<Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: Image.network(
                          featured.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: CyTokens.bgSurfaceSubtle,
                            child: const Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: CyTokens.space3),
                  ],
                  Expanded(
                    child: Text(
                      featured.name,
                      style: textTheme.bodyMedium?.copyWith(
                        fontSize: CyTokens.typeBody,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node});

  final CityNodeDetail node;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(CyTokens.pageX),
      child: Container(
        padding: const EdgeInsets.all(CyTokens.space4),
        decoration: BoxDecoration(
          color: CyTokens.bgElevated,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '漫游 · 到店互动',
              style: textTheme.bodySmall?.copyWith(
                fontSize: CyTokens.typeCaption,
                color: CyTokens.textTertiary,
              ),
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              (node.templateTitle ?? '').isNotEmpty
                  ? node.templateTitle!
                  : (node.name.isNotEmpty ? node.name : '到店打卡'),
              style: textTheme.titleMedium?.copyWith(
                fontSize: CyTokens.typeCardTitle,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              nodeMetaText(node),
              style: textTheme.bodySmall?.copyWith(
                fontSize: CyTokens.typeLabel,
                color: CyTokens.textSecondary,
              ),
            ),
            if ((node.description ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                node.description!,
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: CyTokens.typeBody,
                  color: CyTokens.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space3,
      ),
      child: Container(
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyTokens.bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              size: 20,
              color: CyTokens.textSecondary,
            ),
            const SizedBox(width: CyTokens.space2_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: CyTokens.typeLabel,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: CyTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              onPressed: onAction,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _GallerySection extends StatelessWidget {
  const _GallerySection({required this.gallery});

  final List<String> gallery;

  void _preview(BuildContext context, String current) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => CupertinoPageScaffold(
          child: Stack(
            children: <Widget>[
              PageView.builder(
                controller: PageController(
                  initialPage: gallery.indexOf(current),
                ),
                itemCount: gallery.length,
                itemBuilder: (_, int i) => InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      gallery[i],
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Semantics(
                  button: true,
                  label: '关闭图片预览',
                  child: CupertinoButton(
                    onPressed: () => Navigator.pop(ctx),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.xmark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            0,
          ),
          child: Text(
            '店铺相册',
            style: TextStyle(
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            itemCount: gallery.length,
            separatorBuilder: (_, _) => const SizedBox(width: CyTokens.space2),
            itemBuilder: (_, int i) {
              void preview() => _preview(context, gallery[i]);
              return Semantics(
                key: Key('roam-gallery-preview-$i'),
                container: true,
                excludeSemantics: true,
                button: true,
                label: '预览店铺图片 ${i + 1}，共 ${gallery.length} 张',
                onTap: preview,
                child: CupertinoButton(
                  onPressed: preview,
                  minimumSize: const Size(128, 96),
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                    child: SizedBox(
                      width: 128,
                      height: 96,
                      child: Image.network(
                        gallery[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: CyTokens.bgSurfaceSubtle,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StorySection extends StatelessWidget {
  const _StorySection({required this.merchant});

  final RoamMerchantInfo merchant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space3,
        CyTokens.pageX,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            (merchant.storyTitle ?? '').isNotEmpty
                ? merchant.storyTitle!
                : '品牌故事',
            style: const TextStyle(
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            merchant.description ?? '',
            style: const TextStyle(
              fontSize: CyTokens.typeBody,
              height: CyTokens.leadingNormal,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.merchant});

  final RoamMerchantInfo merchant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space3,
        CyTokens.pageX,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '基本信息',
            style: TextStyle(
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          _row(context, '商家名称', merchant.name ?? '商家'),
          if (merchant.catNames.isNotEmpty)
            _row(context, '品类', merchant.catNames),
          _row(context, '收费方式', merchant.chargeText),
          _row(context, '营业状态', merchant.isOpen ? '营业中' : '已打烊'),
          if ((merchant.address ?? '').isNotEmpty)
            _row(context, '门店地址', merchant.address!),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space1_5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: CyTokens.typeLabel,
                color: CyTokens.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: CyTokens.typeLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// 到店扫码:全屏扫码对话框,扫到码即返回。
class _PosterScanDialog extends StatefulWidget {
  const _PosterScanDialog();

  @override
  State<_PosterScanDialog> createState() => _PosterScanDialogState();
}

class _PosterScanDialogState extends State<_PosterScanDialog> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RoamPoiNativePage(
      title: '扫店内张贴码',
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          const Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Text(
              '对准店内张贴的到店打卡码',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: CyTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    for (final Barcode b in capture.barcodes) {
      final String? raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handled = true;
      await _controller.stop();
      if (mounted) Navigator.pop(context, raw);
      return;
    }
  }
}
