import 'package:flutter/cupertino.dart';

import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../data/models/checkin_models.dart';

Future<String?> showClassicAnswerTask({
  required BuildContext context,
  required PlayNode node,
  String initialAnswer = '',
  Widget? image,
}) => showCyNativeSheet<String>(
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  // 真源题面 topGap .22(约 78% 屏高),介于两档之间,取贴近的大档、内部滚动兜长内容。
  context,
  detents: CyNativeSheetDetents.large,
  builder: (BuildContext sheetContext) => ClassicAnswerTaskView(
    node: node,
    initialAnswer: initialAnswer,
    image: image,
    onClose: () => Navigator.of(sheetContext, rootNavigator: true).pop(),
    onSubmit: (String value) =>
        Navigator.of(sheetContext, rootNavigator: true).pop(value),
  ),
);

enum ClassicAnswerTaskAction { submit, hint, reveal }

class ClassicAnswerTaskResult {
  const ClassicAnswerTaskResult(this.action, [this.answer = '']);

  final ClassicAnswerTaskAction action;
  final String answer;
}

Future<ClassicAnswerTaskResult?> showClassicPuzzleAnswerTask({
  required BuildContext context,
  required PlayNode node,
  required List<String> usedHints,
  required int hintCount,
  required int scoreCap,
  String initialAnswer = '',
  Widget? image,
}) => showCyNativeSheet<ClassicAnswerTaskResult>(
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  context,
  // 同 showClassicAnswerTask:真源 topGap .22,取贴近的大档。
  detents: CyNativeSheetDetents.large,
  builder: (BuildContext sheetContext) => ClassicAnswerTaskView(
    node: node,
    initialAnswer: initialAnswer,
    image: image,
    usedHints: usedHints,
    hintCount: hintCount,
    scoreCap: scoreCap,
    onClose: () => Navigator.of(sheetContext, rootNavigator: true).pop(),
    onHint: usedHints.length < hintCount
        ? () => Navigator.of(
            sheetContext,
            rootNavigator: true,
          ).pop(const ClassicAnswerTaskResult(ClassicAnswerTaskAction.hint))
        : null,
    onReveal: hintCount > 0 && usedHints.length >= hintCount
        ? () => Navigator.of(
            sheetContext,
            rootNavigator: true,
          ).pop(const ClassicAnswerTaskResult(ClassicAnswerTaskAction.reveal))
        : null,
    onSubmit: (String value) => Navigator.of(
      sheetContext,
      rootNavigator: true,
    ).pop(ClassicAnswerTaskResult(ClassicAnswerTaskAction.submit, value)),
  ),
);

Future<bool?> showClassicProofTask({
  required BuildContext context,
  required String title,
  required String instruction,
  required ClassicProofMode mode,
  bool ready = false,
  Widget? preview,
}) => showCyNativeSheet<bool>(
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  context,
  // 同另两个题面:真源 topGap .22,取贴近的大档。
  detents: CyNativeSheetDetents.large,
  builder: (BuildContext sheetContext) => ClassicProofTaskView(
    title: title,
    instruction: instruction,
    mode: mode,
    ready: ready,
    preview: preview,
    onClose: () => Navigator.of(sheetContext, rootNavigator: true).pop(),
    onPrimary: () => Navigator.of(sheetContext, rootNavigator: true).pop(true),
    onSecondary: ready
        ? () => Navigator.of(sheetContext, rootNavigator: true).pop(false)
        : null,
  ),
);

/// 经典节点题面。题面字段全部来自 `/api/play/nodes`，输入与已选项只保留在
/// 当前 Sheet；答案仍由服务端判断。
class ClassicAnswerTaskView extends StatefulWidget {
  const ClassicAnswerTaskView({
    super.key,
    required this.node,
    required this.onSubmit,
    this.initialAnswer = '',
    this.image,
    this.scrollController,
    this.onClose,
    this.usedHints,
    this.hintCount,
    this.scoreCap,
    this.onHint,
    this.onReveal,
  });

  final PlayNode node;
  final String initialAnswer;
  final Widget? image;
  final ScrollController? scrollController;
  final VoidCallback? onClose;
  final List<String>? usedHints;
  final int? hintCount;
  final int? scoreCap;
  final VoidCallback? onHint;
  final VoidCallback? onReveal;
  final ValueChanged<String> onSubmit;

  @override
  State<ClassicAnswerTaskView> createState() => _ClassicAnswerTaskViewState();
}

class _ClassicAnswerTaskViewState extends State<ClassicAnswerTaskView> {
  late final TextEditingController _controller;
  late String _selected;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAnswer);
    _selected = widget.node.options?.containsKey(widget.initialAnswer) == true
        ? widget.initialAnswer
        : '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String>? options = widget.node.options;
    final bool choice = options != null && options.isNotEmpty;
    final bool canSubmit = choice
        ? _selected.isNotEmpty
        : _controller.text.trim().isNotEmpty;
    final List<String> shownHints = widget.usedHints ?? widget.node.usedHints;
    final int totalHints = widget.hintCount ?? widget.node.hintCount;
    final int currentScore = widget.scoreCap ?? widget.node.puzzleScoreCap;
    // 解谜入口(showClassicPuzzleAnswerTask)必带 usedHints:gp2 的找字题;
    // 普通答题对应 mp-sheet 的「写下你的答案」。
    final bool puzzle = widget.usedHints != null;
    return CupertinoPageScaffold(
      key: const Key('classic-answer-task'),
      // 原生 sheet 承载时透明,透出系统材质(S3);回退路径维持真源底。
      backgroundColor: isCyNativeSheet(context)
          ? CupertinoColors.transparent
          : CyTokens.bgPage,
      child: SafeArea(
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space5,
          ),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.node.name,
                        style: const TextStyle(
                          color: CyTokens.textPrimary,
                          fontSize: CyTokens.typeSectionTitle,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.onClose != null)
                      Semantics(
                        button: true,
                        label: '关闭任务',
                        child: CupertinoButton(
                          minimumSize: const Size.square(44),
                          padding: EdgeInsets.zero,
                          onPressed: widget.onClose,
                          child: const Icon(
                            CupertinoIcons.xmark,
                            color: CyTokens.textPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: CyTokens.space4),
                _QuestionCard(
                  question: widget.node.question ?? widget.node.name,
                  image: widget.image,
                  child: choice
                      ? _choices(options)
                      : Semantics(
                          // 小程序 mp-sheet 的 input 带 aria-label="填写任务答案"。
                          label: puzzle ? null : '填写任务答案',
                          child: CupertinoTextField(
                            key: const Key('play-answer-text-input'),
                            controller: _controller,
                            placeholder: puzzle ? '把你找到的字填在这里' : '写下你的答案',
                            clearButtonMode: OverlayVisibilityMode.editing,
                            textInputAction: TextInputAction.done,
                            padding: const EdgeInsets.all(CyTokens.space3),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                ),
                if (shownHints.isNotEmpty ||
                    widget.node.puzzleScoring) ...<Widget>[
                  const SizedBox(height: CyTokens.space3),
                  for (final String hint in shownHints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space1),
                      child: Text(
                        hint,
                        style: const TextStyle(
                          color: CyTokens.textSecondary,
                          fontSize: CyTokens.typeLabel,
                        ),
                      ),
                    ),
                  if (widget.node.puzzleScoring)
                    Text(
                      '当前最高 $currentScore 解谜分 · 不影响探索值',
                      style: const TextStyle(
                        color: CyTokens.textSecondary,
                        fontSize: CyTokens.typeCaption,
                      ),
                    ),
                ],
                if (widget.onHint != null ||
                    widget.onReveal != null) ...<Widget>[
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    children: <Widget>[
                      if (widget.onHint != null)
                        Expanded(
                          child: CupertinoButton(
                            minimumSize: const Size(44, 44),
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                            onPressed: widget.onHint,
                            child: Text(
                              '看提示（${shownHints.length + 1}/$totalHints）',
                              style: const TextStyle(
                                color: CyTokens.textSecondary,
                                fontSize: CyTokens.typeLabel,
                              ),
                            ),
                          ),
                        ),
                      if (widget.onReveal != null)
                        Expanded(
                          child: CupertinoButton(
                            minimumSize: const Size(44, 44),
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerRight,
                            onPressed: widget.onReveal,
                            child: const Text(
                              '实在解不出，揭示答案',
                              style: TextStyle(
                                color: CyTokens.textSecondary,
                                fontSize: CyTokens.typeLabel,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: CyTokens.space5),
                CyNativeButton(
                  key: const Key('classic-task-submit'),
                  label: '提交',
                  width: double.infinity,
                  onPressed: canSubmit ? _submit : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _choices(Map<String, String> options) {
    final List<String> keys = options.keys.toList()..sort();
    return Column(
      children: <Widget>[
        for (final String key in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space2),
            child: CupertinoButton(
              key: Key('classic-task-option-$key'),
              minimumSize: const Size(double.infinity, 52),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
              color: _selected == key
                  ? CyTokens.bgSurfaceSubtle
                  : CyTokens.bgPage,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              onPressed: () => setState(() => _selected = key),
              child: Row(
                children: <Widget>[
                  Text(
                    key,
                    style: TextStyle(
                      color: _selected == key
                          ? CyTokens.textPrimary
                          : CyTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space3),
                  Expanded(
                    child: Text(
                      options[key] ?? '',
                      style: const TextStyle(color: CyTokens.textPrimary),
                    ),
                  ),
                  if (_selected == key)
                    const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: CyTokens.textPrimary,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _submit() {
    final String value = widget.node.options?.isNotEmpty == true
        ? _selected
        : _controller.text.trim();
    if (value.isNotEmpty) widget.onSubmit(value);
  }
}

enum ClassicProofMode { photo, scan }

class ClassicProofTaskView extends StatelessWidget {
  const ClassicProofTaskView({
    super.key,
    required this.title,
    required this.instruction,
    required this.mode,
    required this.onPrimary,
    this.ready = false,
    this.preview,
    this.onSecondary,
    this.onClose,
  });

  final String title;
  final String instruction;
  final ClassicProofMode mode;
  final bool ready;
  final Widget? preview;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    key: const Key('classic-proof-task'),
    // 原生 sheet 承载时透明,透出系统材质(S3);回退路径维持真源底。
    backgroundColor: isCyNativeSheet(context)
        ? CupertinoColors.transparent
        : CyTokens.bgPage,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.pageX,
          CyTokens.space4,
          CyTokens.pageX,
          CyTokens.space5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: CyTokens.textPrimary,
                      fontSize: CyTokens.typeSectionTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onClose != null)
                  Semantics(
                    button: true,
                    label: '关闭任务',
                    child: CupertinoButton(
                      minimumSize: const Size.square(44),
                      padding: EdgeInsets.zero,
                      onPressed: onClose,
                      child: const Icon(
                        CupertinoIcons.xmark,
                        color: CyTokens.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: CyTokens.space4),
            Text(
              instruction,
              style: const TextStyle(
                color: CyTokens.textPrimary,
                fontSize: CyTokens.typeBody,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              height: 280,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CyTokens.bgSurface,
                  borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                  border: Border.all(color: CyTokens.borderSubtle),
                ),
                child:
                    preview ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          mode == ClassicProofMode.photo
                              ? CupertinoIcons.camera
                              : CupertinoIcons.viewfinder,
                          color: CyTokens.textSecondary,
                          size: 42,
                        ),
                        const SizedBox(height: CyTokens.space2),
                        Text(
                          mode == ClassicProofMode.photo && ready
                              ? '已拍摄，点击重拍'
                              : mode == ClassicProofMode.photo
                              ? '拍照上传'
                              : '扫描现场二维码',
                          style: const TextStyle(color: CyTokens.textSecondary),
                        ),
                      ],
                    ),
              ),
            ),
            const Spacer(),
            const SizedBox(height: CyTokens.space3),
            if (onSecondary != null) ...<Widget>[
              CyNativeButton(
                label: mode == ClassicProofMode.photo ? '重新拍摄' : '取消',
                role: CyNativeButtonRole.secondary,
                width: double.infinity,
                onPressed: onSecondary,
              ),
              const SizedBox(height: CyTokens.space2),
            ],
            CyNativeButton(
              key: const Key('classic-proof-primary'),
              label: mode == ClassicProofMode.photo ? '提交' : '扫码',
              width: double.infinity,
              icon: CyNativeButtonIcon(
                sfSymbol: mode == ClassicProofMode.photo
                    ? 'paperplane.fill'
                    : 'qrcode.viewfinder',
                fallback: mode == ClassicProofMode.photo
                    ? CupertinoIcons.paperplane_fill
                    : CupertinoIcons.viewfinder,
              ),
              onPressed: onPrimary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.child,
    this.image,
  });

  final String question;
  final Widget child;
  final Widget? image;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CyTokens.space3),
    decoration: BoxDecoration(
      color: CyTokens.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          question,
          style: const TextStyle(
            color: CyTokens.textPrimary,
            fontSize: CyTokens.typeBody,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (image != null) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            child: SizedBox(height: 170, child: image),
          ),
        ],
        const SizedBox(height: CyTokens.space3),
        child,
      ],
    ),
  );
}
