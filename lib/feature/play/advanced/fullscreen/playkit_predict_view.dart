import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../../core/theme/cy_tokens.dart';
import '../../../../core/widgets/cy_native_button.dart';
import '../playkit_fullscreen.dart';
import '../playkit_projection.dart';
import 'playkit_fullscreen_parts.dart';
import 'playkit_misc_data.dart';

/// `cy-playkit-predict` · 竞猜 · 押一个,等商家给答案。
///
/// 真源:`~/城瘾app/xcx-ref/pages/play/components/playkit-predict/`。
/// 结构 1:1 —— 选项、押定、火漆印、揭晓四态(等 / 中 / 没中 / 作废)。
///
/// ## 结果由服务端定
/// 押完**不当场出结果**:到点由商家公布,可能是三天后。所以这一屏没有判定屏,
/// 组件不判对错、不猜答案 ——「硬套一张『答对/答错』上去就是骗人,那个时刻答案
/// 还不存在」(真源注释原文)。`settleStatus` 没回来时整块揭晓区**不渲染**,
/// 而不是摆一句「暂无结果」。
///
/// ## 押定不可逆:服务端说押过就不许再押
/// 卡片 `complete`(真源 `segmentComplete`:`myOptionKey` 非空)或段里已有
/// `myOptionKey` 时,CTA 直接进「已经押了」的禁用态 —— 不发第二次
/// (上一批 ② 的同类问题:少这一条,玩家会以为自己刚才那下没生效)。
///
/// ## 与真源的已知差异(§7.2 accepted,「iOS 27 原生化」)
/// * 转盘:真源是自绘圆柱面 3D 转盘(十条切片 + perspective 拼出弯卡面),
///   App 换成**系统分页卡组**(`PageView`,相邻卡露出一角)。
///   「等/翻到想要的那张,点它,再押定」这条主流程保留,3D 投影不保留。
/// * **不做连续自转**:自转是「等」的拟物表达,而持续自行运动的可点内容
///   在 iOS 无障碍上要求可暂停(WCAG 2.2.2),收益不抵成本;
///   分页惯性 + 吸附承担同一件事,减动效下两者都不影响可点性。
/// * 卡面/火漆印保留道具色(近黑卡面 + 红蜡),字重 800 → w600/w700(T3)。
///
/// 台面 chrome(退出/限时条)是宿主的活,不在玩法组件里抢一份。
class PlayKitPredictView extends StatefulWidget {
  const PlayKitPredictView({super.key, required this.data});

  final PlayKitFullscreenContext data;

  @override
  State<PlayKitPredictView> createState() => _PlayKitPredictViewState();
}

/// 皮肤 `skin-predict`(`style/play-surface.wxss:23`)的逐值道具色。
/// 这一屏恒为近黑(原型的「转盘/火漆印」语言),不跟主题翻转 ——
/// 同类先例:`playkit_countdown_view.dart` 的白台面、`playkit_walk_view.dart` 的琥珀。
const Color _kPredictSurface = Color(0xFF08080A);
const Color _kPredictInk = Color(0xFFF4F4F6);
const Color _kPredictSub = Color(0xFF78787F);
const Color _kPredictCard = Color(0xFF0C0C10);
const Color _kPredictCardEdge = Color(0x33FFFFFF);

/// 火漆色(真源 `.pd__seal-wax` 的 radial-gradient 主段)。
const Color _kPredictWax = Color(0xFFC22A32);
const Color _kPredictWaxDeep = Color(0xFF8A141B);
const Color _kPredictWaxChar = Color(0xFF9E1C24);

/// 卡面比例 276 : 372(真源 `CW` / `CH`),与原型 138×186pt 一致。
const double _kPredictCardAspect = 276 / 372;

/// 一个选项的键名行(真源 `.pd__k`,11pt 字距拉开)—— 服务端认的是 key。
const double _kPredictKeySpacing = 2.4;

class _PlayKitPredictViewState extends State<PlayKitPredictView>
    with SingleTickerProviderStateMixin {
  late final PageController _pager = PageController(viewportFraction: 0.66);
  // 在 initState 里显式建,不靠 late 懒初始化:整局没押定时 dispose 会成为
  // 第一次访问,_seal.dispose() 反而触发建 ticker,在已 deactivate 的
  // element 上 lookup ancestor 直接崩(同级先例:playkit_countdown_view)。
  late final AnimationController _seal;

  /// 玩家这一局点了哪张。**不跟分页联动**:真源是「点一张卡才算选中」,
  /// 滑到哪张不等于押哪张(划过去的和押下去的不是一回事)。
  int _picked = -1;

  /// 这一局本地押定过。服务端说押过([_serverCommitted])同样进押定态,
  /// 但那是「已经发生的事」,不再播一次火漆印。
  bool _committed = false;
  bool _sealAnimated = false;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  Map<String, Object?> get _kit => widget.data.card.kit;

  List<PlayKitPredictOption> get _options =>
      PlayKitPredictOption.listFrom(_kit['options']);

  String get _question {
    final String fromKit = '${_kit['question'] ?? ''}'.trim();
    if (fromKit.isNotEmpty) return fromKit;
    return widget.data.card.title;
  }

  String get _myOptionKey => '${_kit['myOptionKey'] ?? ''}'.trim();

  bool get _serverCommitted =>
      widget.data.card.complete || _myOptionKey.isNotEmpty;

  bool get _isCommitted => _committed || _serverCommitted;

  String get _waitLabel => predictWaitLabelOf(
    '${_kit['closeMode'] ?? ''}'.trim(),
    int.tryParse('${_kit['closeDays'] ?? ''}') ?? 0,
  );

  PlayKitPredictRevealText? get _reveal => predictRevealOf(
    settleStatus: _kit['settleStatus'],
    settledOption: '${_kit['settledOption'] ?? ''}',
    won: _kit['won'] == true,
    options: _options,
    myOptionKey: _myOptionKey,
  );

  @override
  void initState() {
    super.initState();
    _seal = AnimationController(vsync: this, duration: CyMotion.celebrate);
  }

  @override
  void dispose() {
    _seal.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _pick(int index) {
    if (_isCommitted) return;
    playKitHaptic(context, PlayKitHaptic.selection);
    setState(() => _picked = index);
  }

  void _commit() {
    if (_isCommitted || _picked < 0 || _picked >= _options.length) return;
    if (!widget.data.enabled) return;
    final PlayKitPredictOption option = _options[_picked];
    // 「做成了」= 押定这一下。它不可逆,给 medium(真源 onCommit 的 motion.haptic)。
    playKitHaptic(context, PlayKitHaptic.medium);
    setState(() {
      _committed = true;
      _sealAnimated = true;
    });
    if (!_reduced) unawaited(_seal.forward(from: 0));
    widget.data.onAction?.call(
      PlayKitAction(
        label: '就押这个',
        action: 'SUBMIT_PREDICT',
        // 真源 serverPayload:`predict:submit → { optionKey: d.key }` ——
        // 带的是 key,不是下标(下标在服务端没有意义)。
        payload: <String, Object?>{'optionKey': option.key},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<PlayKitPredictOption> options = _options;
    final bool committed = _isCommitted;
    final PlayKitPredictRevealText? reveal = _reveal;
    return ColoredBox(
      color: _kPredictSurface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space4,
            vertical: CyTokens.space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_question.isNotEmpty)
                Text(
                  _question,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kPredictInk,
                    fontSize: CyTokens.typePageTitle,
                    fontWeight: FontWeight.w600,
                    height: CyTokens.leadingTight,
                  ),
                ),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: options.isEmpty
                          // 空态:服务端段在、选项不在。说清「怎么才会有」,不摆空转盘。
                          ? const Center(
                              child: Text(
                                '这一轮还没有选项，等商家把题目配好再来。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _kPredictSub,
                                  fontSize: CyTokens.typeBody,
                                  height: CyTokens.leadingNormal,
                                ),
                              ),
                            )
                          : Center(child: _carousel(options, committed)),
                    ),
                    if (committed)
                      Positioned(
                        right: CyTokens.space5,
                        top: CyTokens.space2,
                        // ★ 必须走 AnimatedBuilder:_seal.value 只在 build 里读
                        //   的话没人重建,章会停在第 0 帧(Opacity 0)——
                        //   parts 文件 ★ 警告过的死动画,这里当时也踩中了。
                        child: AnimatedBuilder(
                          animation: _seal,
                          builder: (BuildContext context, Widget? child) =>
                              _PredictSeal(
                                // 减动效:章还在(它是「押定了」这条信息),只是不砸下来。
                                // 真源 `.pd--reduced .pd__seal { animation: none; }`。
                                progress: (!_sealAnimated || _reduced)
                                    ? 1
                                    : Curves.easeOutBack.transform(
                                        _seal.value.clamp(0, 1),
                                      ),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              // 真源 `.pd__hint` 绝对定位在按钮正上方(不跟内容流)。没揭晓就常驻
              // 一行:没押时是固定指引「转到想押的那张，点它」(逐字),押了之后
              // 换成等待话术。(kit 里的 `hint` 字段真源只声明从不渲染,
              // App 不替商家自造展示位。)
              if (reveal == null && (!committed || _waitLabel.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(bottom: CyTokens.space3),
                  child: Text(
                    committed ? _waitLabel : '转到想押的那张，点它',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color:
                          _kPredictSub, // 真源 var(--sub) = skin-predict #78787f
                      fontSize: CyTokens.typeLabel, // 真源 24rpx
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.72, // 真源 .06em
                    ),
                  ),
                ),
              if (reveal != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: CyTokens.space3),
                  child: _RevealBlock(reveal: reveal),
                ),
              CyNativeButton(
                key: const Key('playkit-predict-cta'),
                label: committed ? '已经押了' : '就押这个',
                width: double.infinity,
                loading: widget.data.acting,
                onPressed: (!committed && _picked >= 0 && widget.data.enabled)
                    ? _commit
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carousel(List<PlayKitPredictOption> options, bool committed) {
    // 服务端回填的「已押」没有本地 _picked:按 `myOptionKey` 反查是哪一张。
    // 不反查的话整排卡全被压暗、一张都不亮 —— 真源注释原文:
    // 「转盘还要继续转,玩家得看得见自己押的是哪张」。
    final int selected = _picked >= 0
        ? _picked
        : options.indexWhere(
            (PlayKitPredictOption o) =>
                _myOptionKey.isNotEmpty && o.key == _myOptionKey,
          );
    // 卡宽由可用宽度定(视口的那一档),高度按真源卡片比例反推 ——
    // 不写死像素:大字号的设备上卡面跟着长,不裁字(T4)。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cardWidth = (constraints.maxWidth * 0.66).clamp(
          140.0,
          240.0,
        );
        final double cardHeight = cardWidth / _kPredictCardAspect;
        return SizedBox(
          height: cardHeight + CyTokens.space3,
          child: PageView.builder(
            controller: _pager,
            itemCount: options.length,
            physics: committed ? const NeverScrollableScrollPhysics() : null,
            itemBuilder: (BuildContext context, int index) {
              final PlayKitPredictOption option = options[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space1,
                ),
                child: _PredictCard(
                  key: Key('playkit-predict-option-$index'),
                  option: option,
                  index: index,
                  selected: index == selected,
                  dimmed: committed && index != selected,
                  onTap: committed ? null : () => _pick(index),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PredictCard extends StatefulWidget {
  const _PredictCard({
    super.key,
    required this.option,
    required this.index,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final PlayKitPredictOption option;
  final int index;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  State<_PredictCard> createState() => _PredictCardState();
}

class _PredictCardState extends State<_PredictCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final double scale = _pressed ? 0.97 : 1;
    final Widget card = AnimatedScale(
      scale: scale,
      duration: CyMotion.press,
      child: Opacity(
        opacity: widget.dimmed ? 0.55 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: _kPredictCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected ? _kPredictInk : _kPredictCardEdge,
              width: widget.selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(CyTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.option.key.toUpperCase(),
                style: const TextStyle(
                  color: _kPredictSub,
                  fontSize: CyTokens.typeCaption,
                  fontWeight: FontWeight.w600,
                  letterSpacing: _kPredictKeySpacing,
                ),
              ),
              const Spacer(),
              Text(
                widget.option.label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kPredictInk,
                  fontSize: CyTokens.typePageTitle,
                  fontWeight: FontWeight.w600,
                  height: CyTokens.leadingTight,
                ),
              ),
              const Spacer(),
              if (widget.selected)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    size: 20,
                    color: _kPredictInk,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: enabled,
      selected: widget.selected,
      label: enabled ? '押 ${widget.option.label}' : widget.option.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        // ⚠️ 只挂在 onTap 上:onTapUp 与 onTap 在一次点击里**都会**触发,
        // 两处都调一遍会让「选一张卡」执行两次(上一版就是这么写的)。
        onTap: enabled
            ? () {
                setState(() => _pressed = false);
                widget.onTap?.call();
              }
            : null,
        child: card,
      ),
    );
  }
}

/// 揭晓那一块。中/没中/作废各有一条**语义边** + 一行标题说人话 ——
/// 状态不只靠颜色(§9.3 V5)。
class _RevealBlock extends StatelessWidget {
  const _RevealBlock({required this.reveal});

  final PlayKitPredictRevealText reveal;

  @override
  Widget build(BuildContext context) {
    final Color edge = switch (reveal.kind) {
      // 中/没中的边色逐值取自真源组件自己的 `playkit-predict/index.wxss`:
      // `.pd__reveal--won #12a06f` / `.pd__reveal--lost #d0323b`(红底白字 5.0:1)。
      // 不是台面 `--ok` —— skin-predict 的 `--ok` 是 #ffffff,那是另一回事。
      PlayKitPredictReveal.won => const Color(0xFF12A06F),
      PlayKitPredictReveal.lost => const Color(0xFFD0323B),
      PlayKitPredictReveal.wait => _kPredictCardEdge,
      PlayKitPredictReveal.voided => const Color(0x2EFFFFFF),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space4,
        vertical: CyTokens.space3,
      ),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: edge, width: 2),
      ),
      child: Column(
        children: <Widget>[
          Text(
            reveal.head,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kPredictInk,
              fontSize: CyTokens.typeButton,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            reveal.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9A9AA2), // 真源 .pd__reveal-t
              fontSize: CyTokens.typeBody, // 真源 26rpx,上到 iOS 梯级 Body
              height: CyTokens.leadingNormal, // 真源 1.6
            ),
          ),
        ],
      ),
    );
  }
}

/// 押定的火漆印:红蜡一坨、边缘不规则、歪着砸下去。
///
/// 真源 `.pd__seal` 逐值:88pt、右 16% / 上 23%、rotate(-11deg)、
/// 从上方 2.5 倍缩放砸下再回弹。App 保留「歪 + 红蜡 + 内环 + 一个字」,
/// 动画压成一段 easeOutBack(§7.2「iOS 27 原生化」:转场与触感允许重做)。
class _PredictSeal extends StatelessWidget {
  const _PredictSeal({required this.progress});

  /// 0 → 1:`1` 是砸定后的静止形态(减动效 / 服务端已押过时直接用 1)。
  final double progress;

  @override
  Widget build(BuildContext context) {
    final double t = progress.clamp(0, 1);
    return ExcludeSemantics(
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -24 * (1 - t)),
          child: Transform.rotate(
            angle: -11 * math.pi / 180,
            child: Transform.scale(
              scale: 0.84 + 0.16 * t,
              child: SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // 蜡块:径向渐变 + 四角半径互不相同(蜡本来就压不圆)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.elliptical(41, 44),
                          topRight: Radius.elliptical(47, 45),
                          bottomLeft: Radius.elliptical(45, 43),
                          bottomRight: Radius.elliptical(44, 46),
                        ),
                        gradient: const RadialGradient(
                          center: Alignment(-0.28, -0.4),
                          radius: 0.95,
                          colors: <Color>[
                            Color(0xFFEC5A61),
                            _kPredictWax,
                            _kPredictWaxDeep,
                          ],
                          stops: <double>[0, 0.54, 1],
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                    // 凹进去的内环
                    Container(
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0x2EFFFFFF),
                          width: 2,
                        ),
                      ),
                    ),
                    const Text(
                      '押',
                      style: TextStyle(
                        color: _kPredictWaxChar,
                        fontSize: 30,
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
    );
  }
}
