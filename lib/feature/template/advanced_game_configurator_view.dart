/// 「高级玩法配置器」的编辑页 UI —— 玩法目录单选 + 决定/挑战类配置面板 + 计时修饰段。
///
/// 结构 1:1 真源 `pages/publish/temp/index.wxml` 的「选择玩法」九宫格 + 各段面板;
/// 外观 iOS 27 原生(CupertinoTextField / CupertinoSwitch / 分段控件)。数据全部走
/// [AdvancedConfigDraft],状态由编辑页持有并监听(见 template_edit_page)。
///
/// 本批只接决定类 + 挑战类七段(纯标量、无图、无嵌套图选)+ timer 修饰段。目录里
/// 其余玩法禁用(置灰、仍显示真源 sub),不做「选了却没有面板能填」的假入口。
library;

import 'package:flutter/cupertino.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/models/advanced_play_config.dart';
import '../../data/models/node_game_catalog.dart';
import 'advanced_game_configurator.dart';

class AdvancedGameConfigurator extends StatelessWidget {
  const AdvancedGameConfigurator({super.key, required this.draft});

  final AdvancedConfigDraft draft;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: draft,
      builder: (BuildContext context, _) {
        final CyPalette palette = CyPalette.of(context);
        final String error = draft.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 卡内子区块标题:走 iOS 梯级 Headline(17 Semibold,T2)。
            // 不用 CySectionTitle(Title3 20)—— 外层「玩法配置」卡标题是
            // #332 域(18pt),子标题压过父级会造成层级倒挂。
            Text(
              '选择玩法',
              style: CyType.headline.copyWith(color: palette.textPrimary),
            ),
            _GameCatalogGrid(draft: draft),
            _SelectedGamePanel(draft: draft),
            const SizedBox(height: CyTokens.space4),
            _ModifierTimer(draft: draft),
            if (error.isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                error,
                key: const Key('advanced-config-error'),
                style: CyType.footnote.copyWith(color: palette.statusDanger),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 选中玩法的配置面板(仅本批已接的段)。
class _SelectedGamePanel extends StatelessWidget {
  const _SelectedGamePanel({required this.draft});

  final AdvancedConfigDraft draft;

  @override
  Widget build(BuildContext context) {
    final NodeGameItem? game = draft.selectedGame;
    if (game == null) return const SizedBox.shrink();
    if (!AdvancedConfigDraft.kImplementedGameKeys.contains(game.key)) {
      return const _ComingSoonNote();
    }
    final String section = game.section;
    return Column(
      key: ValueKey<String>('panel-${game.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: CyTokens.space3),
        _PanelHeader(item: game, onSwitch: draft.clearGame),
        _AdvTextField(
          key: ValueKey('$section-kicker'),
          label: '标题',
          hint: '给玩家看的一句话（32 字内）',
          maxLength: 32,
          initial: draft.text(section, 'kicker'),
          onChanged: (v) => draft.setText(section, 'kicker', v),
        ),
        switch (game.key) {
          'coin' => _CoinPanel(draft: draft, section: section),
          'dice' => _DicePanel(draft: draft, section: section),
          'react' => _ReactionPanel(draft: draft, section: section),
          'shake' => _BallShakePanel(draft: draft, section: section),
          'quiet' => _QuietPanel(draft: draft, section: section),
          'countdown' => _CountdownPanel(draft: draft, section: section),
          'stopwatch' => _StopwatchPanel(draft: draft, section: section),
          _ => const SizedBox.shrink(),
        },
        _AdvTextField(
          key: ValueKey('$section-xp'),
          label: '奖励分（选填）',
          hint: '0 表示不额外给分',
          number: true,
          initial: draft.number(section, 'xp'),
          onChanged: (v) => draft.setNumber(section, 'xp', v),
        ),
      ],
    );
  }
}

class _GameCatalogGrid extends StatelessWidget {
  const _GameCatalogGrid({required this.draft});

  final AdvancedConfigDraft draft;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final NodeGameGroup group in kNodeGameGroups) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(
              top: CyTokens.space3,
              bottom: CyTokens.space1,
            ),
            child: Text(
              group.title,
              style: CyType.footnote.copyWith(color: palette.textSecondary),
            ),
          ),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: <Widget>[
              for (final NodeGameItem item in group.items)
                _GameChip(draft: draft, item: item),
            ],
          ),
        ],
      ],
    );
  }
}

class _GameChip extends StatelessWidget {
  const _GameChip({required this.draft, required this.item});

  final AdvancedConfigDraft draft;
  final NodeGameItem item;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool implemented = AdvancedConfigDraft.kImplementedGameKeys.contains(
      item.key,
    );
    // bingo(主题级,无段)与未接面板的玩法一律禁用,避免「选了填不了」。
    final bool enabled = implemented && item.section.isNotEmpty;
    final bool selected = draft.gameKey == item.key;
    final String title = item.badge.isEmpty
        ? item.label
        : '${item.label} · ${item.badge}';
    // 禁用态**换色不降透明度**(与 CyChip 同一纪律):opacity 会把已调过
    // 对比度的文字整体压暗,且全站出现两套禁用视觉。
    final Color titleColor = enabled
        ? palette.textPrimary
        : palette.textPlaceholder;
    final Color subColor = enabled
        ? palette.textSecondary
        : palette.textTertiary;
    return CupertinoButton(
      key: Key('game-chip-${item.key}'),
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      pressedOpacity: MediaQuery.disableAnimationsOf(context) ? 1 : 0.6,
      onPressed: enabled ? () => draft.selectGame(item.key) : null,
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3,
          vertical: CyTokens.space2_5,
        ),
        decoration: BoxDecoration(
          color: selected ? palette.brandSoft : palette.bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(
            color: selected ? palette.brand : palette.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: CyType.subhead.copyWith(
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.sub,
              style: CyType.caption1.copyWith(color: subColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonNote extends StatelessWidget {
  const _ComingSoonNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Text(
        '这个玩法的配置面板将在后续批次接入。',
        style: CyType.footnote.copyWith(
          color: CyPalette.of(context).textTertiary,
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.item, required this.onSwitch});

  final NodeGameItem item;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            item.label,
            style: CyType.callout.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ),
        CupertinoButton(
          key: const Key('advanced-switch-game'),
          minimumSize: const Size(44, 44), // L9:触达区 ≥ 44pt
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space2,
            vertical: CyTokens.space1,
          ),
          onPressed: onSwitch,
          child: Text(
            '换一个',
            style: CyType.subhead.copyWith(color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _CoinPanel extends StatelessWidget {
  const _CoinPanel({required this.draft, required this.section});

  final AdvancedConfigDraft draft;
  final String section;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[_side('heads', '正面'), _side('tails', '反面')],
    );
  }

  Widget _side(String side, String label) {
    final Map<String, Object?> f = draft.nested(section, side);
    return Column(
      children: <Widget>[
        _AdvTextField(
          key: ValueKey('$section-$side-label'),
          label: '$label叫法',
          maxLength: 16,
          initial: '${f['label'] ?? ''}',
          onChanged: (v) => draft.setNested(section, side, 'label', v),
        ),
        _AdvTextField(
          key: ValueKey('$section-$side-action'),
          label: '$label要做什么（必填）',
          hint: '例如：这杯店家请',
          maxLength: 60,
          initial: '${f['action'] ?? ''}',
          onChanged: (v) => draft.setNested(section, side, 'action', v),
        ),
      ],
    );
  }
}

class _DicePanel extends StatelessWidget {
  const _DicePanel({required this.draft, required this.section});

  final AdvancedConfigDraft draft;
  final String section;

  @override
  Widget build(BuildContext context) {
    final List<Object?> faces = draft.faces();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CyField(
          label: '骰子颗数',
          child: CupertinoSlidingSegmentedControl<int>(
            key: const Key('dice-count'),
            groupValue:
                advNumber((draft.advanced['diceRoll'] as Map?)?['diceCount']) ==
                    2
                ? 2
                : 1,
            children: const <int, Widget>{
              1: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('1 颗', textAlign: TextAlign.center),
              ),
              2: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('2 颗·只报点数和', textAlign: TextAlign.center),
              ),
            },
            onValueChanged: (v) => draft.setDiceCount(v ?? 1),
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        for (int i = 0; i < 6; i++)
          _AdvTextField(
            key: ValueKey('dice-face-$i'),
            label: '第 ${i + 1} 面（必填）',
            hint: '写具体一点，玩家才知道要干嘛',
            maxLength: 60,
            initial: i < faces.length ? '${faces[i]}' : '',
            onChanged: (v) => draft.setFace(i, v),
          ),
      ],
    );
  }
}

class _ReactionPanel extends StatelessWidget {
  const _ReactionPanel({required this.draft, required this.section});

  final AdvancedConfigDraft draft;
  final String section;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _AdvTextField(
          key: ValueKey('$section-rounds'),
          label: '轮数',
          hint: '1 至 10',
          number: true,
          initial: draft.number(section, 'rounds'),
          onChanged: (v) => draft.setNumber(section, 'rounds', v),
        ),
        _AdvTextField(
          key: ValueKey('$section-goalMs'),
          label: '达标毫秒',
          hint: '120 至 2000',
          number: true,
          initial: draft.number(section, 'goalMs'),
          onChanged: (v) => draft.setNumber(section, 'goalMs', v),
        ),
      ],
    );
  }
}

class _BallShakePanel extends StatelessWidget {
  const _BallShakePanel({required this.draft, required this.section});

  final AdvancedConfigDraft draft;
  final String section;

  @override
  Widget build(BuildContext context) {
    final bool timed = (draft.advanced['ballShake'] as Map?)?['timed'] == true;
    return Column(
      children: <Widget>[
        _AdvTextField(
          key: ValueKey('$section-goal'),
          label: '撞击次数目标',
          hint: '1 至 200',
          number: true,
          initial: draft.number(section, 'goal'),
          onChanged: (v) => draft.setNumber(section, 'goal', v),
        ),
        _AdvSwitchRow(
          title: '限时一局',
          value: timed,
          onChanged: (v) => draft.setBool('ballShake', 'timed', v),
        ),
        if (timed)
          _AdvTextField(
            key: ValueKey('$section-seconds'),
            label: '限时秒数',
            hint: '3 至 300',
            number: true,
            initial: draft.number(section, 'seconds'),
            onChanged: (v) => draft.setNumber(section, 'seconds', v),
          ),
      ],
    );
  }
}

class _QuietPanel extends StatelessWidget {
  const _QuietPanel({required this.draft, required this.section});

  final AdvancedConfigDraft draft;
  final String section;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _AdvTextField(
          key: ValueKey('$section-sub'),
          label: '副标题',
          maxLength: 60,
          initial: draft.text(section, 'sub'),
          onChanged: (v) => draft.setText(section, 'sub', v),
        ),
        _AdvTextField(
          key: ValueKey('$section-seconds'),
          label: '安静时长（秒）',
          hint: '5 至 300',
          number: true,
          initial: draft.number(section, 'seconds'),
          onChanged: (v) => draft.setNumber(section, 'seconds', v),
        ),
      ],
    );
  }
}

class _CountdownPanel extends StatelessWidget {
  const _CountdownPanel({required this.draft, required this.section});

  final AdvancedConfigDraft draft;
  final String section;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _AdvTextField(
          key: ValueKey('$section-seconds'),
          label: '倒计时秒数',
          hint: '5 至 3600',
          number: true,
          initial: draft.number(section, 'seconds'),
          onChanged: (v) => draft.setNumber(section, 'seconds', v),
        ),
        _AdvTextField(
          key: ValueKey('$section-doneText'),
          label: '到点时说什么（必填）',
          hint: '例如：时间到。',
          maxLength: 60,
          initial: draft.text(section, 'doneText'),
          onChanged: (v) => draft.setText(section, 'doneText', v),
        ),
      ],
    );
  }
}

class _StopwatchPanel extends StatelessWidget {
  const _StopwatchPanel({required this.draft, required this.section});

  final AdvancedConfigDraft draft;
  final String section;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _AdvTextField(
          key: ValueKey('$section-targetSeconds'),
          label: '目标秒数',
          hint: '3 至 120',
          number: true,
          initial: draft.number(section, 'targetSeconds'),
          onChanged: (v) => draft.setNumber(section, 'targetSeconds', v),
        ),
        _AdvTextField(
          key: ValueKey('$section-toleranceMs'),
          label: '容差毫秒',
          hint: '50 至 5000，玩家得先知道才谈得上瞄准',
          number: true,
          initial: draft.number(section, 'toleranceMs'),
          onChanged: (v) => draft.setNumber(section, 'toleranceMs', v),
        ),
        _AdvTextField(
          key: ValueKey('$section-tries'),
          label: '可试次数',
          hint: '0 至 10，0 表示不限',
          number: true,
          initial: draft.number(section, 'tries'),
          onChanged: (v) => draft.setNumber(section, 'tries', v),
        ),
      ],
    );
  }
}

class _ModifierTimer extends StatelessWidget {
  const _ModifierTimer({required this.draft});

  final AdvancedConfigDraft draft;

  @override
  Widget build(BuildContext context) {
    final bool enabled = draft.isEnabled('timer');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '叠加修饰',
          style: CyType.footnote.copyWith(
            color: CyPalette.of(context).textTertiary,
          ),
        ),
        _AdvSwitchRow(
          key: const Key('modifier-timer-switch'),
          title: '限时挑战',
          value: enabled,
          onChanged: (v) => draft.setEnabled('timer', v),
        ),
        if (enabled)
          _AdvTextField(
            key: const ValueKey('timer-durationSeconds'),
            label: '计时时长（秒）',
            hint: '10 至 86400',
            number: true,
            initial: draft.number('timer', 'durationSeconds'),
            onChanged: (v) => draft.setNumber('timer', 'durationSeconds', v),
          ),
      ],
    );
  }
}

class _AdvTextField extends StatefulWidget {
  const _AdvTextField({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.hint,
    this.maxLength,
    this.number = false,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int? maxLength;
  final bool number;

  @override
  State<_AdvTextField> createState() => _AdvTextFieldState();
}

class _AdvTextFieldState extends State<_AdvTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 表单项走共用件 CyField(P3:label 规则 T2 —— Caption1 灰字)。
    return CyField(
      label: widget.label,
      child: CupertinoTextField(
        key: Key('field-${widget.label}'),
        controller: _controller,
        maxLength: widget.maxLength,
        keyboardType: widget.number ? TextInputType.number : TextInputType.text,
        placeholder: widget.hint,
        clearButtonMode: OverlayVisibilityMode.editing,
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space3,
          vertical: 12,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _AdvSwitchRow extends StatelessWidget {
  const _AdvSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 与同页 _CupertinoSwitchRow(#332 已复核)同一开关行形态:行高 ≥52、
    // 语义合并、开关开启色用品牌色(该页既有口径,不在此页混两套)。
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: CyType.body.copyWith(color: palette.textPrimary),
                ),
              ),
              const SizedBox(width: CyTokens.space3),
              ExcludeSemantics(
                child: CupertinoSwitch(
                  value: value,
                  activeTrackColor: palette.brand,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
