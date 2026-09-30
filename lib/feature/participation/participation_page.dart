import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'participation_api.dart';
import 'participation_detail_sheet.dart';
import 'participation_models.dart';

export 'participation_detail_sheet.dart' show ParticipationDetailPresenter;

abstract interface class ParticipationDetailErrorNativeDriver {
  bool get supportsLiquidGlass;

  Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
  });
}

class _LiquidGlassParticipationDetailErrorDriver
    implements ParticipationDetailErrorNativeDriver {
  const _LiquidGlassParticipationDetailErrorDriver();

  @override
  bool get supportsLiquidGlass => NativeLiquidGlassUtils.supportsLiquidGlass;

  @override
  Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    await LiquidGlassAlert.show(
      context: context,
      title: title,
      message: message,
      actions: const <LiquidGlassAlertAction>[
        LiquidGlassAlertAction(id: 'close', title: '返回参与列表', isCancel: true),
      ],
    );
  }
}

class ParticipationPage extends ConsumerStatefulWidget {
  const ParticipationPage({
    super.key,
    this.liquidGlassSupported,
    this.detailPresenter,
    this.detailErrorNativeDriver,
  });

  final bool? liquidGlassSupported;
  final ParticipationDetailPresenter? detailPresenter;
  final ParticipationDetailErrorNativeDriver? detailErrorNativeDriver;

  @override
  ConsumerState<ParticipationPage> createState() => _ParticipationPageState();
}

class _ParticipationPageState extends ConsumerState<ParticipationPage> {
  /// 分段控件高度:44pt 是触达下限(L9),字号被系统放大时必须跟着长高 ——
  /// 固定 39 会在大字号下裁字(T4)。与票夹 `#307`/`CyTabs` 分段同一算法
  /// (label + 24,下限 44)。
  static double _segmentControlHeight(BuildContext context) {
    final double label = MediaQuery.textScalerOf(
      context,
    ).scale(CyTokens.typeBody);
    return label + 24 < 44 ? 44 : label + 24;
  }

  ParticipationFilter _filter = ParticipationFilter.all;
  int? _loadingDetailId;

  /// 真源 mycanyu.js:有缓存数据时刷新失败**不打断** —— 继续显示旧列表,
  /// 不整屏翻回错误态。invalidate 会让 FutureProvider 丢掉旧值,所以快照
  /// 由页面自己留一份。
  List<ParticipationRecord>? _snapshot;

  @override
  Widget build(BuildContext context) {
    // ★ 游客深链落地给页内登录门,不静默弹回首页(b1-sim-club-2 N1,同券域
    //   b1-sim-coupon P1-1 范式);游客短路掉注定 401 的请求 —— 此前只有
    //   登录态过期(401 回包)才见得到登录入口,游客根本走不到那一步。
    final AuthState auth = ref.watch(authControllerProvider);
    if (!auth.isLoggedIn) {
      return CupertinoPageScaffold(
        backgroundColor: CyPalette.of(context).bgPage,
        navigationBar: const CupertinoNavigationBar(),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const CyPageTitle('我的参与'),
                Expanded(
                  child: StatusView(
                    key: const Key('participation-login-gate'),
                    message: '登录后查看我的参与',
                    sub: '参与记录存在你的账号里，登录完就能看到。',
                    icon: CupertinoIcons.lock,
                    large: true,
                    retryLabel: '去登录',
                    onRetry: () async {
                      if (!await requireLogin(context, ref)) return;
                      if (mounted) ref.invalidate(participationRecordsProvider);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final AsyncValue<List<ParticipationRecord>> async = ref.watch(
      participationRecordsProvider,
    );
    final bool liquidGlassSupported =
        widget.liquidGlassSupported ??
        NativeLiquidGlassUtils.supportsLiquidGlass;
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('我的参与'),
              _ParticipationFilters(
                active: _filter,
                liquidGlassSupported: liquidGlassSupported,
                onChanged: (ParticipationFilter value) {
                  setState(() => _filter = value);
                },
              ),
              const SizedBox(height: CyTokens.space4),
              Expanded(
                child: async.when(
                  loading: () => _snapshot == null
                      ? const KeyedSubtree(
                          key: Key('participation-loading'),
                          // 真源 subpackageMember/mycanyu:`type="list" count="4"`。
                          child: CySkeleton(type: CySkeletonType.list),
                        )
                      : _list(_snapshot!),
                  error: (Object error, StackTrace stackTrace) =>
                      _snapshot == null ? _errorView(error) : _list(_snapshot!),
                  data: (List<ParticipationRecord> allRows) {
                    _snapshot = allRows;
                    return _list(allRows);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 错误落点收口:后端消息原样透传,网络/Dio 异常给中文,不把
  /// `Exception: ...`、`DioException [...]` 这类实现细节抛给用户。
  static String _userErrorText(Object error) => switch (error) {
    ParticipationApiException(:final String message) => message,
    DioException _ =>
      participationUnauthorizedError(error) ? '登录状态已失效，请重新登录' : '网络异常，请重试',
    _ => error.toString().replaceFirst('Exception: ', ''),
  };

  /// 错误态文案逐档收口:后端消息原样透传,网络/未知失败给中文落点,
  /// 不再把 `Exception: ...` 这类实现细节抛给用户;401 给登录入口。
  Widget _errorView(Object error) {
    if (participationUnauthorizedError(error)) {
      return StatusView(
        icon: CupertinoIcons.lock,
        message: '登录后查看我的参与',
        sub: '登录状态已失效，请重新登录',
        large: true,
        retryLabel: '去登录',
        onRetry: () async {
          if (!await requireLogin(context, ref)) return;
          if (mounted) ref.invalidate(participationRecordsProvider);
        },
      );
    }
    return StatusView(
      icon: CupertinoIcons.exclamationmark_triangle,
      message: '参与记录没能打开',
      sub: _userErrorText(error),
      large: true,
      onRetry: () => ref.invalidate(participationRecordsProvider),
    );
  }

  Widget _list(List<ParticipationRecord> allRows) {
    final List<ParticipationRecord> rows = filterParticipations(
      allRows,
      _filter,
    );
    if (rows.isEmpty) {
      final bool all = _filter == ParticipationFilter.all;
      return StatusView(
        icon: CupertinoIcons.map_pin_ellipse,
        message: all ? '暂无参与记录' : '当前筛选暂无参与记录',
        sub: all ? '报名后，路线和活动会出现在这里' : '切换其他状态查看参与记录',
        large: true,
      );
    }
    return RefreshIndicator.adaptive(
      // 列表在 loading/error+快照 分支也会渲染,稳定 key 保住下拉指示器状态。
      key: const Key('participation-list'),
      onRefresh: _refresh,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          CyTokens.space2,
          0,
          CyTokens.space2,
          CyTokens.space4 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: rows.length,
        itemBuilder: (BuildContext context, int index) {
          final ParticipationRecord record = rows[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space4),
            child: _ParticipationCard(
              record: record,
              loading: _loadingDetailId == record.id,
              onTap: _loadingDetailId == null
                  ? () => _openDetail(record)
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// 下拉刷新直接重拉并落快照:失败静默(真源「有快照不打断」),
  /// 成功覆盖快照;不 invalidate Provider,避免整屏闪回骨架态。
  Future<void> _refresh() async {
    try {
      final List<ParticipationRecord> rows = await ref
          .read(participationRepositoryProvider)
          .list();
      if (mounted) setState(() => _snapshot = rows);
    } catch (_) {
      // 快照继续在场,错误不在刷新路径上打扰用户。
    }
  }

  Future<void> _openDetail(ParticipationRecord record) async {
    setState(() => _loadingDetailId = record.id);
    try {
      final ParticipationDetail detail = await ref
          .read(participationRepositoryProvider)
          .detail(record.id);
      if (!mounted) return;
      final ParticipationDetailResult? result =
          await (widget.detailPresenter ?? showParticipationDetail)(
            context,
            detail,
          );
      if (!mounted || result == null) return;
      await _runDetailAction(result);
    } catch (error) {
      if (!mounted) return;
      await _showDetailError(_userErrorText(error));
    } finally {
      if (mounted) setState(() => _loadingDetailId = null);
    }
  }

  /// 半屏只收集意图,动作在这里执行(真源:非场景目标先 close 再跳转)。
  Future<void> _runDetailAction(ParticipationDetailResult result) async {
    final ParticipationDetail detail = result.detail;
    switch (result.kind) {
      case ParticipationDetailActionKind.startPlay:
        if (detail.id == 0 || detail.ownerId == 0) {
          // 真源 goPlay 缺参兜底 = 票夹(subpackageMember/signup/index)。
          context.push('/tickets');
          return;
        }
        context.push(
          detail.isTopic
              ? '/play/0?topicId=${detail.ownerId}&registrationId=${detail.id}'
              : '/play/${detail.ownerId}?registrationId=${detail.id}',
        );
      case ParticipationDetailActionKind.cancel:
        await _cancelParticipation(detail);
      case ParticipationDetailActionKind.modify:
        context.push('/merchant/registration/${detail.id}/edit');
      case ParticipationDetailActionKind.contact:
        await showParticipationContactDialog(context);
      case ParticipationDetailActionKind.scan:
        context.push('/merchant/scan');
      case ParticipationDetailActionKind.openTemplate:
        context.push('/template/${detail.templateId}?scope=my');
    }
  }

  /// 取消参与。确认文案与 danger-actions.js `order.cancel` /
  /// `order.cancel-refund` 逐字同源;**判据是 paymentStatus==2(已支付)**,
  /// 与真源详情组件同一条 —— 已支付却调 /cancel 会票没了钱不退。
  Future<void> _cancelParticipation(ParticipationDetail detail) async {
    final bool paid = detail.paymentStatus == 2;
    final String deadline = detail.refundDeadlineDisplay.isEmpty
        ? '已核销或已过开始时间不可退'
        : detail.refundDeadlineDisplay;
    final bool ok = await cyConfirm(
      context,
      title: paid ? '取消报名?' : '取消这个待支付订单?',
      content: paid
          ? '取消后报名资格失效，现金退款和积分返还按本单实际支付记录处理。$deadline。'
          : '订单关闭，不再保留名额；此操作不可撤销，需要时请重新下单。',
      confirmText: paid ? '取消并退款' : '取消订单',
      cancelText: '再想想',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _loadingDetailId = detail.id);
    try {
      final String msg = await ref
          .read(activityApiProvider)
          .cancelRegistration(registrationId: detail.id, paid: paid);
      if (!mounted) return;
      CyNativeNotice.show(context, msg);
      // 真源:取消成功 → triggerEvent('refresh') 通知宿主重拉列表。
      final List<ParticipationRecord> rows = await ref
          .read(participationRepositoryProvider)
          .list();
      if (mounted) setState(() => _snapshot = rows);
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(context, _userErrorText(error), isError: true);
    } finally {
      if (mounted) setState(() => _loadingDetailId = null);
    }
  }

  Future<void> _showDetailError(String message) async {
    final ParticipationDetailErrorNativeDriver driver =
        widget.detailErrorNativeDriver ??
        const _LiquidGlassParticipationDetailErrorDriver();
    if (driver.supportsLiquidGlass) {
      try {
        await driver.show(
          context: context,
          title: '参与详情没能打开',
          message: message,
        );
        return;
      } on MissingPluginException {
        // 原生通道未注册时保留完整 Cupertino 错误弹窗。
      } on PlatformException {
        // 原生 presentation 失败时保留完整 Cupertino 错误弹窗。
      }
    }
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => CupertinoAlertDialog(
        title: const Text('参与详情没能打开'),
        content: Text(message),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('返回参与列表'),
          ),
        ],
      ),
    );
  }
}

class _ParticipationFilters extends StatelessWidget {
  const _ParticipationFilters({
    required this.active,
    required this.liquidGlassSupported,
    required this.onChanged,
  });

  final ParticipationFilter active;
  final bool liquidGlassSupported;
  final ValueChanged<ParticipationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final double controlHeight = _ParticipationPageState._segmentControlHeight(
      context,
    );
    final CyPalette palette = CyPalette.of(context);
    if (liquidGlassSupported) {
      return _hitTarget(
        height: controlHeight,
        child: LiquidGlassSegmentedControl(
          labels: ParticipationFilter.values
              .map((ParticipationFilter filter) => filter.label)
              .toList(growable: false),
          selectedIndex: active.index,
          // ★ 黑白基调:不给 tint 就吃到 SwiftUI 默认系统蓝(C1)。
          //   同票夹分段(#307)与 CyTabs 分段变体,传 textPrimary。
          color: palette.textPrimary,
          onValueChanged: (int index) {
            onChanged(ParticipationFilter.values[index]);
          },
          height: controlHeight,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: _hitTarget(
        height: controlHeight,
        child: SizedBox(
          height: controlHeight,
          child: CupertinoSlidingSegmentedControl<int>(
            groupValue: active.index,
            // 回退档同样取语义色,不用控件自带的系统默认底/滑块
            // (#307 实证:白色滑块上不压前景色,选中项白压白直接消失)。
            backgroundColor: palette.bgSurfaceSubtle,
            thumbColor: palette.actionPrimaryBg,
            children: <int, Widget>{
              for (final ParticipationFilter filter
                  in ParticipationFilter.values)
                filter.index: Text(
                  filter.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: active == filter
                        ? palette.actionPrimaryFg
                        : palette.textPrimary,
                  ),
                ),
            },
            onValueChanged: (int? index) {
              if (index != null) onChanged(ParticipationFilter.values[index]);
            },
          ),
        ),
      ),
    );
  }

  Widget _hitTarget({required double height, required Widget child}) {
    return SizedBox(
      key: const Key('participation-filter-hitbox'),
      height: height < _minHitHeight ? _minHitHeight : height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails details) {
                final double segmentWidth =
                    constraints.maxWidth / ParticipationFilter.values.length;
                final int index = (details.localPosition.dx / segmentWidth)
                    .floor()
                    .clamp(0, ParticipationFilter.values.length - 1);
                onChanged(ParticipationFilter.values[index]);
              },
              child: Center(child: child),
            ),
      ),
    );
  }

  static const double _minHitHeight = 44;
}

class _ParticipationCard extends StatelessWidget {
  const _ParticipationCard({
    required this.record,
    required this.loading,
    required this.onTap,
  });

  final ParticipationRecord record;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      button: true,
      label:
          '${record.sourceName}，${record.stateText}，${record.dateText}，${record.typeLabel}，${record.address}',
      child: Material(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: CupertinoButton(
          key: Key('participation-record-${record.id}'),
          onPressed: onTap,
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          child: SizedBox(
            height: 176,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 216,
                    height: 176,
                    child: CyNetImage(
                      record.coverUrl,
                      fit: BoxFit.cover,
                      fallback: const _CoverFallback(),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 216,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[
                          palette.bgSurface.withValues(alpha: 0),
                          palette.bgSurface.withValues(alpha: 0.18),
                          palette.bgSurface,
                        ],
                        stops: const <double>[0.48, 0.77, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: CyTokens.space3,
                  top: CyTokens.space4,
                  bottom: CyTokens.space3,
                  width: 168,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space1,
                    ),
                    child: Column(
                      // 真源 FILLED/23 修复后的层级:状态签在上独占首行,
                      // 标题在下面占满整行(最多两行) —— 不再与状态签并排互相挤压。
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _StatePill(state: record.state, text: record.stateText),
                        const SizedBox(height: CyTokens.space1_5),
                        Text(
                          record.sourceName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: CyTokens.typeSectionTitle,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        _MetaLine(
                          icon: CupertinoIcons.calendar,
                          text: record.dateText,
                        ),
                        const SizedBox(height: CyTokens.space1_5),
                        _MetaLine(
                          icon: CupertinoIcons.location_solid,
                          text: '${record.typeLabel} · ${record.address}',
                        ),
                      ],
                    ),
                  ),
                ),
                if (loading)
                  Positioned.fill(
                    key: Key('participation-detail-loading-${record.id}'),
                    child: ColoredBox(
                      color: palette.overlay,
                      child: const Center(child: CupertinoActivityIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 封面缺席的占位:实色表面 + 图标即可;斜向渐变属装饰性光效
    // (视觉收口删减清单:去渐变),真源这里也是一张静态占位图。
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.bgElevated),
      child: Icon(CupertinoIcons.map, color: palette.textTertiary, size: 42),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state, required this.text});

  final ParticipationState state;
  final String text;

  @override
  Widget build(BuildContext context) {
    // 状态色走 CyPalette(随外观变),不用 CyTokens 暗色编译期常量(C4 双值)。
    final CyPalette p = CyPalette.of(context);
    final Color color = switch (state) {
      ParticipationState.notStarted => p.statusInfo,
      ParticipationState.inProgress => p.statusSuccess,
      ParticipationState.completed => p.textTertiary,
      ParticipationState.pendingPayment => p.statusWarning,
      ParticipationState.expired => p.statusWarning,
      ParticipationState.cancelled => p.textTertiary,
      ParticipationState.refunded => p.statusSuccess,
      ParticipationState.refunding => p.statusWarning,
      ParticipationState.manualRefund => p.statusWarning,
      ParticipationState.nonRefundable => p.textTertiary,
      ParticipationState.unknown => p.textTertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space1_5,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: CyTokens.typeCaption,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Color color = CyPalette.of(context).textSecondary;
    return Row(
      children: <Widget>[
        Icon(icon, size: 12, color: color),
        const SizedBox(width: CyTokens.space1),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: CyTokens.typeLabel, color: color),
          ),
        ),
      ],
    );
  }
}
