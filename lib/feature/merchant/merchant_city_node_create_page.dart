import '../../l10n/strings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_city_node.dart';
import 'merchant_error_view.dart';

/// 报名成为节点(提交据点投放申请)。对齐小程序 `pages/merchant/citynode/create`。
///
/// 两步:① 配店铺玩法(模板)② 确认店址。两步都齐才能提交。
///
/// ★★ 三条语义来自小程序那页,每条都对应一个真会犯的错:
///
///   ① **店址默认用档案坐标,但必须让商家点头一次**。
///      直接拿档案坐标静默提交的话,坐标偏了没人会发现 ——
///      表现出来是"玩家一直打不了卡",而商家完全不知道问题在哪。
///
///   ② **提交成功后再点不重复提交**,只重做回读。
///      后端没有幂等键,重复点 = 重复的投放申请。
///
///   ③ **审核通过前绝不在客户端伪造成已上线节点**(小程序原注释)。
///      提交只换来"待审",不能让列表先显示成在架。
/// 真源 `accessState`:loading / ready / no-permission / error。
enum _AccessState { loading, ready, denied, error }

class MerchantCityNodeCreatePage extends ConsumerStatefulWidget {
  const MerchantCityNodeCreatePage({super.key});

  @override
  ConsumerState<MerchantCityNodeCreatePage> createState() =>
      _MerchantCityNodeCreatePageState();
}

class _MerchantCityNodeCreatePageState
    extends ConsumerState<MerchantCityNodeCreatePage> {
  static const int _radiusM = 80;

  /// 经营团队权限核对的三态(真源 `accessState`:loading / no-permission /
  /// error / ready)。没权限的岗位进来只会撞一串注定失败的请求,
  /// 所以这一闸在**读店铺资料之前**,且三种失败各说各的话。
  _AccessState _access = _AccessState.loading;
  String? _accessError;

  /// 本页草稿(玩法配了 / 店址确认或改过)没提交就走,要有那句放弃确认。
  bool _draftDirty = false;

  // ---- 店铺资料 ----
  bool _shopLoaded = false;
  String? _shopLoadError;
  double? _lat;
  double? _lng;
  String? _shopName;
  String? _shopAddress;

  /// 坐标是不是来自入驻档案(而不是商家这次自己确认的)。
  /// 决定要不要显示那句「先看一眼对不对」。
  bool _fromProfile = false;

  /// 商家有没有**点头确认过**店址。见类注释 ①。
  bool _confirmed = false;

  // ---- 玩法模板 ----
  int? _templateId;
  String? _templateTitle;

  // ---- 提交 ----
  bool _submitting = false;
  int? _submittedApplicationId;
  String? _error;

  /// 提交后回读列表没找到这条申请 —— 不是失败,是**还没同步出来**。
  bool _readbackMiss = false;

  bool get _canSubmit =>
      _templateId != null && _confirmed && _lat != null && _lng != null;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  /// 真源 `loadAccess()`:先读 `/api/merchant/access/me`,
  /// **active 且 canManageProjects 才让进本页表单**;
  /// 读失败与"岗不对"是两种话,不能混成一句「加载失败」。
  Future<void> _loadAccess() async {
    setState(() {
      _access = _AccessState.loading;
      _accessError = null;
    });
    try {
      final MerchantAccess access = await ref
          .read(merchantApiProvider)
          .access();
      if (!mounted) return;
      if (!access.active || !access.canManageProjects) {
        setState(() => _access = _AccessState.denied);
        return;
      }
      setState(() => _access = _AccessState.ready);
      await _loadShop();
    } catch (e) {
      if (!mounted) return;
      // sub 只放人话:后端原话优先,网络故障用真源那句,
      // DioException 的英文原文不许糊上屏(同 merchant_error_view 的口径)。
      String msg = '';
      if (e is MerchantApiException) {
        msg = e.message;
      } else if (e is DioException) {
        final Object? data = e.response?.data;
        if (data is Map) msg = data['msg']?.toString().trim() ?? '';
      }
      setState(() {
        _access = _AccessState.error;
        _accessError = msg.isEmpty ? stringsOf(context).merchantNodeAccessNetwork : msg;
      });
    }
  }

  Future<void> _loadShop() async {
    setState(() {
      _shopLoaded = false;
      _shopLoadError = null;
    });
    try {
      final Map<String, dynamic> m = await ref
          .read(merchantApiProvider)
          .merchantInfo();
      double? num2(Object? v) =>
          v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
      if (!mounted) return;
      setState(() {
        _lat = num2(m['locationLat']) ?? num2(m['latitude']);
        _lng = num2(m['locationLng']) ?? num2(m['longitude']);
        _shopName = m['name']?.toString();
        _shopAddress = m['address']?.toString();
        _fromProfile = _lat != null && _lng != null;
        _shopLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _shopLoaded = true;
        _shopLoadError = stringsOf(context).merchantNodeShopNetwork;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    // ★ 见类注释 ②:已经提交过就只重做回读,绝不再发一次申请。
    final int? already = _submittedApplicationId;
    if (already != null) {
      await _readBack(already);
      return;
    }
    if (!_canSubmit) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> d = await ref
          .read(merchantApiProvider)
          .saveCityNode(
            templateId: _templateId!,
            lat: _lat,
            lng: _lng,
            radius: _radiusM,
            name: _shopName,
            address: _shopAddress,
          );
      final Object? id = d['id'];
      final int appId = id is num ? id.toInt() : 0;
      if (!mounted) return;
      setState(() => _submittedApplicationId = appId);
      await _readBack(appId);
    } on MerchantApiException catch (e) {
      // 后端的拒绝话术自带信息量(配额上限带具体数字、模板未选、已上线据点
      // 不能复用入口),必须原文显示。
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = stringsOf(context).merchantNodeNetworkRetry;
      });
    }
  }

  /// ★ 回执 ≠ 观测:提交返回 200 只证明请求被接受了。
  ///   回列表里找到这条申请,才算真的落到了对面。
  Future<void> _readBack(int applicationId) async {
    setState(() {
      _submitting = true;
      _readbackMiss = false;
    });
    try {
      final CityNodeHome home = await ref.read(merchantApiProvider).cityNodes();
      final bool found = home.applications.any(
        (CityNodeApplication a) => a.id == applicationId,
      );
      if (!mounted) return;
      if (found) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _submitting = false;
        _readbackMiss = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _readbackMiss = true;
      });
    }
  }

  /// 真源 `onUnload` 的草稿守卫:玩法或店址改过但还没提交,
  /// 直接离开会把这一页的编辑全丢掉,得先问一句。
  Future<bool> _confirmLeave() async {
    if (!_draftDirty) return true;
    final bool leave = await cyConfirm(
      context,
      title: stringsOf(context).merchantNodeDiscardTitle,
      content: stringsOf(context).merchantNodeDiscardBody,
      confirmText: stringsOf(context).merchantNodeLeave,
      cancelText: stringsOf(context).merchantNodeKeepEditing,
      danger: true,
    );
    return leave;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_draftDirty,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        if (!await _confirmLeave()) return;
        if (!context.mounted) return;
        setState(() => _draftDirty = false);
        Navigator.of(context).pop();
      },
      child: CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CyPageTitle(stringsOf(context).merchantNodeApplyTitle, subtitle: stringsOf(context).merchantNodeApplySubtitle),
            Expanded(child: _body(context)),
            if (_access == _AccessState.ready)
              Padding(
                padding: const EdgeInsets.all(CyTokens.space4),
                child: CyNativeButton(
                  onPressed:
                      (_canSubmit || _submittedApplicationId != null) &&
                          !_submitting
                      ? _submit
                      : null,
                  label: _submittedApplicationId != null
                      ? stringsOf(context).merchantNodeReadApplication
                      : stringsOf(context).merchantNodeSubmitApplication,
                  width: double.infinity,
                  loading: _submitting,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_access) {
      case _AccessState.loading:
        // 真源整页只有这一行状态字:没权限的岗位不该先撞一串注定失败的请求。
        return Center(child: Text(stringsOf(context).merchantNodeCheckingPermissions));
      case _AccessState.denied:
        return merchantDeniedView(title: stringsOf(context).merchantNodeManageDenied, sub: stringsOf(context).merchantNodeContactManager);
      case _AccessState.error:
        return StatusView(
          message: stringsOf(context).merchantNodeAccessFailed,
          sub: _accessError,
          large: true,
          onRetry: _loadAccess,
          retryLabel: stringsOf(context).merchantNodeRetry,
        );
      case _AccessState.ready:
        return ListView(
          padding: const EdgeInsets.all(CyTokens.space4),
          children: <Widget>[
            _templateCard(context),
            const SizedBox(height: CyTokens.space3),
            _addressCard(context),
            if (_error != null) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              // 快照用 cy-inline-error 的 title/sub 两行:只说后端原话,
              // 商家不知道「刚才这一步是提交还是读取失败了」。
              Text(stringsOf(context).merchantNodeNotSubmitted, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: CyTokens.space1),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_readbackMiss) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              // 不说"失败" —— 申请已经提交了,说失败会让商家再提一次。
              Text(
                stringsOf(context).merchantNodeAwaitSync,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
    }
  }

  Widget _templateCard(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return _card(
      context,
      step: stringsOf(context).merchantNodeStepExperience,
      done: _templateId != null,
      children: <Widget>[
        if (_templateId != null) ...<Widget>[
          Text(_templateTitle ?? stringsOf(context).merchantNodeConfigured, style: t.titleSmall),
          const SizedBox(height: CyTokens.space2),
          CyNativeButton(
            onPressed: _pickTemplate,
            label: stringsOf(context).merchantNodeReconfigure,
            role: CyNativeButtonRole.secondary,
          ),
        ] else ...<Widget>[
          Text(stringsOf(context).merchantNodeExperienceHint, style: t.bodySmall),
          const SizedBox(height: CyTokens.space2),
          CyNativeButton(
            onPressed: _pickTemplate,
            label: stringsOf(context).merchantNodeConfigure,
            role: CyNativeButtonRole.secondary,
          ),
        ],
      ],
    );
  }

  Widget _addressCard(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final List<Widget> body;
    if (!_shopLoaded) {
      body = <Widget>[Text(stringsOf(context).merchantNodeLoadingShop, style: t.bodySmall)];
    } else if (_shopLoadError != null) {
      body = <Widget>[
        Text(_shopLoadError!, style: t.bodySmall),
        const SizedBox(height: CyTokens.space2),
        CyNativeButton(
          onPressed: _loadShop,
          label: stringsOf(context).merchantNodeRetry,
          role: CyNativeButtonRole.secondary,
        ),
      ];
    } else if (_lat == null || _lng == null) {
      // 档案里没坐标 —— 后端也会拒(「你的店铺资料里还没有坐标」),
      // 但在这里给出路:直接在地图上点一下店门口,不用绕去店铺资料。
      body = <Widget>[
        Text(stringsOf(context).merchantNodeMissingCoordinates, style: t.bodySmall),
        const SizedBox(height: CyTokens.space2),
        CyNativeButton(
          onPressed: _repick,
          label: stringsOf(context).merchantNodeMarkLocation,
          role: CyNativeButtonRole.secondary,
        ),
      ];
    } else {
      body = <Widget>[
        Text(
          _shopName?.isNotEmpty == true ? _shopName! : stringsOf(context).merchantNodeMyStore,
          style: t.titleSmall,
        ),
        if ((_shopAddress ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            _shopAddress!,
            style: t.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
        if (_fromProfile && !_confirmed) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          // ★ 这句是本页最重要的一句话:说清确认它的**后果**。
          //   不说的话,坐标偏了没人会发现 —— 表现成"玩家一直打不了卡",
          //   而商家完全不知道问题在哪。
          Text(
            stringsOf(context).merchantNodeAddressHint(_radiusM),
            style: t.bodySmall,
          ),
          const SizedBox(height: CyTokens.space2),
          CyNativeButton(
            onPressed: () => setState(() {
              _confirmed = true;
              _draftDirty = true;
            }),
            label: stringsOf(context).merchantNodeConfirmAddress,
          ),
          const SizedBox(height: CyTokens.space2),
          CyNativeButton(
            onPressed: _repick,
            label: stringsOf(context).merchantNodeChooseAgain,
            role: CyNativeButtonRole.secondary,
          ),
        ],
        if (!_fromProfile || _confirmed) ...<Widget>[
          const SizedBox(height: CyTokens.space2),
          CyNativeButton(
            onPressed: _repick,
            label: stringsOf(context).merchantNodeChooseAddressAgain,
            role: CyNativeButtonRole.secondary,
          ),
        ],
      ];
    }
    return _card(context, step: stringsOf(context).merchantNodeStepAddress, done: _confirmed, children: body);
  }

  Widget _card(
    BuildContext context, {
    required String step,
    required bool done,
    required List<Widget> children,
  }) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(step, style: t.labelLarge)),
              if (done)
                Text(
                  stringsOf(context).merchantNodeCompleted,
                  style: t.labelSmall?.copyWith(color: p.statusSuccess),
                ),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          ...children,
        ],
      ),
    );
  }

  /// 真源 `repick`(wx.chooseLocation):商家在地图上亲手指的点
  /// 不算「来自档案的猜测」,直接视为已确认 —— 但它是本页草稿的一部分。
  Future<void> _repick() async {
    final (String, double, double)? point = await GoRouter.of(
      context,
    ).push<(String, double, double)>('/publish/poi');
    if (point == null || !mounted) return;
    setState(() {
      _lat = point.$2;
      _lng = point.$3;
      _shopAddress = point.$1;
      _fromProfile = false;
      _confirmed = true;
      _draftDirty = true;
    });
  }

  /// 去配玩法。配完带回 {id, title}。
  ///
  /// ★ 之前这里是一句还在做的提示 —— **不做假入口**那条仍然成立,
  ///   只是现在配置页真有了(NodeTemplateEditPage),所以换成真跳转。
  Future<void> _pickTemplate() async {
    final Object? r = await GoRouter.of(
      context,
    ).push('/merchant/node-template');
    if (r is! Map) return;
    final Object? id = r['id'];
    if (id is! num) return;
    setState(() {
      _templateId = id.toInt();
      _templateTitle = r['title']?.toString();
      _draftDirty = true;
    });
  }
}
