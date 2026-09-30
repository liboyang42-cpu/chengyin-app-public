import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant_npc.dart';
import '../club/club_image_picker.dart';
import 'merchant_error_view.dart';

/// 用一张照片生成店铺 3D 形象。
///
/// ★★ **这一页现在只做到「提交 + 看结果缩略图」。**
///   真正的 3D 渲染(转起来看)等 P0 供应商试跑定案 —— 三家候选的产物
///   有没有骨骼、有没有口型 blendshape 差别很大,渲染方案跟着它走。
///   在那之前给一个转不动的假 3D 视图,比诚实地显示一张缩略图更坏。
///
/// ★ 三条语义:
///   ① **供应商没接就不进这一页**(入口按 available 隐藏,这里再判一次)。
///   ② **轮询只在 PENDING 时继续**,认不出的状态按不再轮询 ——
///      宁可让人手动刷新,也不要一个永远转的圈。
///   ③ **离页必须停掉轮询**,否则定时器会一直打接口。
class MerchantNpcAvatarPage extends ConsumerStatefulWidget {
  const MerchantNpcAvatarPage({super.key});

  @override
  ConsumerState<MerchantNpcAvatarPage> createState() =>
      _MerchantNpcAvatarPageState();
}

class _MerchantNpcAvatarPageState extends ConsumerState<MerchantNpcAvatarPage> {
  /// 轮询间隔。3D 生成要几十秒到几分钟,3 秒一次既不刷屏也不显得卡住。
  static const Duration _pollInterval = Duration(seconds: 3);

  static const Map<String, String> _styleLabels = <String, String>{
    'realistic': '写实',
    'cartoon': '卡通',
    'pixel': '像素',
  };

  NpcAvatarStatus _status = const NpcAvatarStatus();
  String _style = 'realistic';

  bool _loading = true;
  bool _loadFailed = false;
  bool _submitting = false;

  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // ★ ③ 离页停轮询。不停的话定时器会一直打接口,而且页面已经没了,
    //   setState 会抛「setState called after dispose」。
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final NpcAvatarStatus s = await ref
          .read(merchantNpcApiProvider)
          .avatarStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _style = s.styles.contains(_style)
            ? _style
            : (s.styles.isEmpty ? 'realistic' : s.styles.first);
        _loading = false;
      });
      _syncPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// 按当前任务状态决定要不要轮询。★ 只有 PENDING 才起定时器。
  void _syncPolling() {
    final bool keep = _status.job?.shouldKeepPolling ?? false;
    if (!keep) {
      _poller?.cancel();
      _poller = null;
      return;
    }
    _poller ??= Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (!mounted) return;
    try {
      final NpcAvatarStatus s = await ref
          .read(merchantNpcApiProvider)
          .avatarStatus();
      if (!mounted) return;
      setState(() => _status = s);
      _syncPolling();
    } catch (_) {
      // 轮询失败静默:下一次再试。★ 弹错误框会在生成期间反复打断人。
    }
  }

  Future<void> _generate() async {
    final List<String> urls = await pickAndUploadImages(
      context,
      ref,
      maxCount: 1,
    );
    if (urls.isEmpty || !mounted) return;

    setState(() => _submitting = true);
    try {
      final NpcAvatarJob job = await ref
          .read(merchantNpcApiProvider)
          .avatarGenerate(imageUrl: urls.first, style: _style);
      if (!mounted) return;
      setState(() {
        _status = NpcAvatarStatus(
          available: _status.available,
          styles: _status.styles,
          job: job,
        );
      });
      _syncPolling();
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('生成 3D 形象')),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(bottom: false, child: CySkeleton()),
        ),
      );
    }

    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('生成 3D 形象')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: _loadFailed
              ? merchantErrorView(
                  context,
                  '没能读到生成状态',
                  onRetry: _load,
                  what: '3D 形象',
                )
              // ★ ① 供应商没接就直说,不给生成入口。
              : !_status.available
              ? const StatusView(
                  message: '3D 形象生成还没开放',
                  sub: '开放后你可以拍一张照片,让店铺形象长得像你。',
                  icon: CupertinoIcons.cube,
                  large: true,
                )
              : ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    Text(
                      '拍一张正面、光线均匀的照片,选一种风格,'
                      '生成的形象会跟店铺形象一起审核。',
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    const CySectionTitle('风格'),
                    const SizedBox(height: CyTokens.space2),
                    _styleRow(p, t),
                    const SizedBox(height: CyTokens.space4),
                    if (_status.job != null) ...<Widget>[
                      const CySectionTitle('上次生成'),
                      const SizedBox(height: CyTokens.space2),
                      _jobCard(_status.job!, p, t),
                      const SizedBox(height: CyTokens.space4),
                    ],
                    CyNativeButton(
                      key: const Key('merchant-npc-avatar-generate'),
                      onPressed:
                          _submitting || (_status.job?.pending ?? false)
                          ? null
                          : _generate,
                      label: _submitting
                          ? '提交中…'
                          : (_status.job?.pending ?? false)
                          ? '正在生成…'
                          : '选照片并生成',
                      loading: _submitting,
                    ),
                    const SizedBox(height: CyTokens.space6),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _styleRow(CyPalette p, TextTheme t) {
    return Wrap(
      spacing: CyTokens.space2,
      children: <Widget>[
        for (final String style in _status.styles)
          CupertinoButton(
            key: Key('merchant-npc-avatar-style-$style'),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
            minimumSize: const Size(0, 44),
            borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            color: _style == style ? p.brandSoft : p.bgSurfaceSubtle,
            onPressed: () => setState(() => _style = style),
            child: Text(
              // 认不出的风格显示原值,不编一个中文名 —— 后端加了新风格时
              // 至少还能选,而不是显示成一个空按钮。
              _styleLabels[style] ?? style,
              style: t.bodySmall?.copyWith(
                color: _style == style ? p.textPrimary : p.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _jobCard(NpcAvatarJob job, CyPalette p, TextTheme t) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          if ((job.thumbUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
              child: CyNetImage(
                job.thumbUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            )
          else if (job.pending)
            const SizedBox(
              width: 64,
              height: 64,
              child: Center(child: CupertinoActivityIndicator()),
            ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  job.pending
                      ? '正在生成,通常要一两分钟'
                      : job.succeeded
                      ? '已生成,正在审核'
                      : '这次没成',
                  style: t.bodyMedium,
                ),
                if (!job.pending && !job.succeeded) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    // failReason 是后端给的安全文案,可以直接显示。
                    job.failReason ?? '换一张更清楚的正面照片再试试',
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
                if (job.succeeded) ...<Widget>[
                  const SizedBox(height: 2),
                  // ★★ 诚实地说清现在只能看缩略图,3D 预览还没做 ——
                  //   不说的话商家会以为「生成了但看不到转的」是个 bug。
                  Text(
                    '3D 预览还在做,现在先看这张缩略图。',
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
