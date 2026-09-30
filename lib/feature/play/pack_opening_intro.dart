import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:rive/rive.dart' hide PaintingStyle;

import '../../core/theme/app_colors.dart';

/// 开卡包 intro 的纯 Dart 时序:tap 序列 → 该发的 Rive trigger → cutScene 后计时到 done。
///
/// 抽出来单独成类是为了可单测:Rive 的 .riv 状态机在 widget test 里起不了
/// (rive_native 需要原生库),但「第几次点该发哪个 trigger、何时算播完」这层
/// 逻辑跟 Rive 无关,必须能脱离原生环境断言。
class PackIntroSequencer {
  PackIntroSequencer({this.revealDelay = const Duration(milliseconds: 2600)});

  /// cutScene 触发后到 onDone 的时长:卡片翻出 + 停留展示的观感时间。
  /// 现用的 .riv 没有对外的「播完」事件,只能按时长收场;
  /// 换成自制卡包时应在 Rive 里加 done 事件,把这个定时器换成事件回调。
  final Duration revealDelay;

  int _step = 0;

  /// 返回本次 tap 应触发的 trigger 名;三步走完后返回 null(后续 tap 无效)。
  String? onTap() {
    final int step = _step;
    if (step >= 3) return null;
    _step = step + 1;
    return const <String>['tapOpen', 'tapOpen2', 'cutScene'][step];
  }

  /// cutScene 已发出 ⇒ 动画进入卡片揭晓段,revealDelay 后该收场了。
  bool get finished => _step >= 3;
}

/// mode2(自由探索)进场的 Rive 开卡包 intro,全屏盖在打卡列表上。
///
/// 交互与小程序的四拍同一套语言:逐次点按推进(入场 → 二段 → 揭晓),
/// 也可右上角跳过。系统开了「减弱动态效果」时整个 intro 不出现,直接 onDone。
class PackOpeningIntro extends StatefulWidget {
  const PackOpeningIntro({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<PackOpeningIntro> createState() => _PackOpeningIntroState();
}

class _PackOpeningIntroState extends State<PackOpeningIntro> {
  final PackIntroSequencer _sequencer = PackIntroSequencer();
  FileLoader? _fileLoader;
  Timer? _revealTimer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    const String asset = String.fromEnvironment('PACK_OPENING_ASSET');
    if (asset.isNotEmpty) {
      _fileLoader = FileLoader.fromAsset(asset, riveFactory: Factory.rive);
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _fileLoader?.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return; // 定时器与「跳过」可能都到:只放行一次
    _done = true;
    widget.onDone();
  }

  void _onTap(ViewModelInstance? vmi) {
    final String? trigger = _sequencer.onTap();
    if (trigger == null) return;
    vmi?.trigger(trigger)?.trigger();
    if (_sequencer.finished) {
      _revealTimer = Timer(_sequencer.revealDelay, _finish);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      // 动画永远不能是必须看完的 —— 与小程序 reducedMotion 直接落定同一立场。
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return const SizedBox.shrink();
    }
    return ColoredBox(
      color: AppColors.bgDeep,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const PackOpeningPoster(),
          if (_fileLoader == null)
            Semantics(
              button: true,
              label: '继续开卡',
              onTap: () => _onTap(null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => _onTap(null),
                child: const SizedBox.expand(),
              ),
            )
          else
            RiveWidgetBuilder(
              fileLoader: _fileLoader!,
              artboardSelector: ArtboardSelector.byName('MainScreen'),
              stateMachineSelector: StateMachineSelector.byName(
                'State Machine 1',
              ),
              dataBind: DataBind.auto(),
              builder: (BuildContext context, RiveState state) =>
                  switch (state) {
                    RiveLoaded(
                      :final RiveWidgetController controller,
                      :final ViewModelInstance? viewModelInstance,
                    ) =>
                      Semantics(
                        button: true,
                        label: '继续开卡动画',
                        hint: '轻点推进，或选择跳过',
                        onTap: () => _onTap(viewModelInstance),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: () => _onTap(viewModelInstance),
                          child: RiveWidget(
                            controller: controller,
                            fit: Fit.cover,
                          ),
                        ),
                      ),
                    // 加载中黑屏即可(资产在包内,窗口极短);加载失败没有降级动画可播,
                    // 直接放行进列表 —— intro 挂了不能把整个玩法挡死。
                    RiveFailed() => Builder(
                      builder: (BuildContext context) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _finish(),
                        );
                        return const SizedBox.shrink();
                      },
                    ),
                    _ => const SizedBox.shrink(),
                  },
            ),
          Positioned(
            top: 8,
            right: 16,
            child: SafeArea(
              child: CupertinoButton(
                onPressed: _finish,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '跳过',
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: .6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// B13 的稳定首帧：Rive 解码前先画出同一张自由探索卡包，避免短暂纯黑。
/// Golden 直接测这层；真机仍由上面的 Rive 接管撕包与发牌动效。
class PackOpeningPoster extends StatelessWidget {
  const PackOpeningPoster({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('free-explore-pack-poster'),
    label: '自由探索，城市附近发现，1 章，1 家商户',
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.2,
          colors: <Color>[Color(0xFF421A13), Color(0xFF09090B)],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Transform.rotate(
            angle: -0.035,
            child: CustomPaint(
              painter: const _FoilPackPainter(),
              child: const SizedBox(
                width: 232,
                height: 398,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(30, 116, 22, 42),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '自由探索\n· 城市附\n近发现',
                        style: TextStyle(
                          color: CupertinoColors.black,
                          fontSize: 35,
                          height: 0.94,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Spacer(),
                      Text(
                        '1 章 · 1 家商户',
                        style: TextStyle(
                          color: CupertinoColors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FoilPackPainter extends CustomPainter {
  const _FoilPackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final Path pack = Path()
      ..moveTo(8, 0)
      ..lineTo(size.width - 8, 0)
      ..lineTo(size.width, 9)
      ..lineTo(size.width - 4, size.height - 12)
      ..lineTo(size.width - 10, size.height)
      ..lineTo(8, size.height)
      ..lineTo(0, size.height - 10)
      ..lineTo(4, 8)
      ..close();
    canvas.drawPath(
      pack,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF7FB9C9),
            Color(0xFFE8F4F4),
            Color(0xFFB5A1D3),
            Color(0xFFE48B8B),
            Color(0xFF718B93),
          ],
          stops: <double>[0, .24, .49, .7, 1],
        ).createShader(bounds),
    );

    final Paint crimp = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFFD9ECF0),
          Color(0xFF6D7780),
          Color(0xFFE9F5F6),
          Color(0xFF778187),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 30));
    canvas.drawRect(Rect.fromLTWH(4, 0, size.width - 8, 30), crimp);
    canvas.save();
    canvas.translate(0, size.height);
    canvas.scale(1, -1);
    canvas.drawRect(Rect.fromLTWH(4, 0, size.width - 8, 34), crimp);
    canvas.restore();

    final Paint seam = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1.4;
    for (double y = 6; y <= 24; y += 6) {
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y), seam);
    }
    for (double y = size.height - 28; y <= size.height - 6; y += 6) {
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y), seam);
    }

    final Paint fold = Paint()
      ..color = const Color(0x44809AA3)
      ..strokeWidth = 5;
    canvas.drawLine(const Offset(7, 30), Offset(22, size.height - 35), fold);
    canvas.drawLine(
      Offset(size.width - 7, 30),
      Offset(size.width - 22, size.height - 35),
      fold,
    );
    canvas.drawPath(
      pack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xAA9AD2DB),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
