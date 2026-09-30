import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../data/models/publish_draft.dart';
import 'publish_draft_logic.dart';

typedef StoryMediaPicker = Future<String?> Function(StoryMediaType mediaType);

/// 城市定向故事流编辑器(对齐 fabu/index.wxml 的 story-editor 半屏 sheet)。
/// 唯一写入口:块间插入点加文字/图片/音频/节点;节点块单击编辑、长按选中、选中后 ✕ 删除;
/// 文字块聚焦即选中;清空后失焦自动移除。
Future<void> showStoryEditorSheet(
  BuildContext context, {
  required PublishDraft draft,
  required int chapterIndex,
  required ValueChanged<String> onChapterNameChanged,
  required ValueChanged<PublishChapter> onStoryChanged,
  required void Function(int insertAt) onInsertNodeAt,
  required void Function(String nodeLocalId) onEditNode,
  StoryMediaPicker? pickAndUploadMedia,
}) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.06,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _StoryEditorSheet(
              draft: draft,
              chapterIndex: chapterIndex,
              scrollController: scrollController,
              onChapterNameChanged: onChapterNameChanged,
              onStoryChanged: onStoryChanged,
              onInsertNodeAt: onInsertNodeAt,
              onEditNode: onEditNode,
              pickAndUploadMedia: pickAndUploadMedia,
            ),
  );
}

class _StoryEditorSheet extends ConsumerStatefulWidget {
  const _StoryEditorSheet({
    required this.draft,
    required this.chapterIndex,
    required this.scrollController,
    required this.onChapterNameChanged,
    required this.onStoryChanged,
    required this.onInsertNodeAt,
    required this.onEditNode,
    required this.pickAndUploadMedia,
  });

  final PublishDraft draft;
  final int chapterIndex;
  final ScrollController scrollController;
  final ValueChanged<String> onChapterNameChanged;
  final ValueChanged<PublishChapter> onStoryChanged;
  final void Function(int insertAt) onInsertNodeAt;
  final void Function(String nodeLocalId) onEditNode;
  final StoryMediaPicker? pickAndUploadMedia;

  @override
  ConsumerState<_StoryEditorSheet> createState() => _StoryEditorSheetState();
}

class _StoryEditorSheetState extends ConsumerState<_StoryEditorSheet> {
  int _insertMenuAt = -1;
  int _uploadingAt = -1;
  StoryMediaType? _uploadingType;
  String _selectedBlockKey = '';
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  late final TextEditingController _chapterNameCtrl = TextEditingController(
    text: widget.draft.chapters[widget.chapterIndex].name,
  );

  @override
  void dispose() {
    _chapterNameCtrl.dispose();
    for (final TextEditingController controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _textControllerFor(StoryBlock block) {
    return _textControllers.putIfAbsent(
      block.key,
      () => TextEditingController(text: block.content),
    );
  }

  PublishChapter get _chapter => widget.draft.chapters[widget.chapterIndex];
  List<StoryBlock> get _blocks => _chapter.blocks ?? const <StoryBlock>[];

  void _apply(StoryCommand command) {
    try {
      final result = applyStoryCommand(_chapter, command);
      widget.onStoryChanged(result.chapter);
      if (mounted) setState(() {});
    } catch (e) {
      _toast(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  /// 纯告知不弹 alert(S7):页内轻提示,失败态留在弹层里可以接着改。
  void _toast(String text) => CyNativeNotice.show(context, text, isError: true);

  void _removeNode(StoryBlock block) {
    _apply(RemoveNodeCommand(blockKey: block.key));
    setState(() {
      _selectedBlockKey = '';
      _insertMenuAt = -1;
    });
  }

  void _removeText(StoryBlock block) {
    _textControllers.remove(block.key)?.dispose();
    _apply(RemoveTextCommand(blockKey: block.key));
    setState(() {
      _selectedBlockKey = '';
      _insertMenuAt = -1;
    });
  }

  void _removeMedia(StoryBlock block) {
    _apply(RemoveMediaCommand(blockKey: block.key));
    setState(() {
      _selectedBlockKey = '';
      _insertMenuAt = -1;
    });
  }

  Future<String?> _pickAndUploadMedia(StoryMediaType mediaType) async {
    switch (mediaType) {
      case StoryMediaType.image:
        final XFile? file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (file == null) return null;
        final String url = await ref
            .read(publishApiProvider)
            .uploadImage(file.path);
        if (url.trim().isEmpty) throw StateError('上传没有返回文件地址');
        return url;
      case StoryMediaType.audio:
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const <String>['mp3', 'm4a', 'aac'],
          allowMultiple: false,
        );
        final PlatformFile? file = result?.files.singleOrNull;
        final String? path = file?.path;
        if (file == null || path == null) return null;
        final String? extension = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : null;
        final String url = await ref
            .read(publishApiProvider)
            .uploadFile(path, fileType: extension, fileName: file.name);
        if (url.trim().isEmpty) throw StateError('上传没有返回文件地址');
        return url;
    }
  }

  Future<void> _pickAndInsertMedia(StoryMediaType mediaType, int index) async {
    if (_uploadingAt >= 0) return;
    setState(() {
      _insertMenuAt = -1;
      _uploadingAt = index;
      _uploadingType = mediaType;
    });
    try {
      final String? rawUrl =
          await (widget.pickAndUploadMedia ?? _pickAndUploadMedia)(mediaType);
      if (!mounted || rawUrl == null) return;
      final String url = rawUrl.trim();
      if (url.isEmpty) throw StateError('上传没有返回文件地址');
      _apply(
        InsertMediaAtCommand(
          index: index,
          blockKey: _newKey(),
          mediaType: mediaType,
          url: url,
        ),
      );
    } catch (e) {
      if (mounted) {
        _toast(
          e
              .toString()
              .replaceFirst('Bad state: ', '')
              .replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAt = -1;
          _uploadingType = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: Text('第${widget.chapterIndex + 1}章 · 故事流'),
        leading: Semantics(
          label: '关闭故事流编辑器',
          button: true,
          child: CupertinoButton(
            key: const Key('story-editor-back'),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const ExcludeSemantics(
              child: Icon(CupertinoIcons.chevron_back),
            ),
          ),
        ),
        trailing: CupertinoButton(
          key: const Key('story-editor-done'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          // 小程序同钮 aria-label=「完成故事流编辑」:只读「完成」听不出完成的是什么。
          child: Semantics(
            label: '完成故事流编辑',
            button: true,
            excludeSemantics: true,
            child: const Text('完成'),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                CyTokens.space2,
              ),
              child: CupertinoTextField(
                key: const Key('story-editor-chapter-name'),
                controller: _chapterNameCtrl,
                onChanged: widget.onChapterNameChanged,
                maxLength: 30,
                textInputAction: TextInputAction.done,
                placeholder: '章节名称',
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space3,
                  vertical: CyTokens.space2,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: palette.textPrimary),
                decoration: BoxDecoration(
                  color: palette.inputBgFilled,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  border: Border.all(color: palette.borderSubtle),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  CyTokens.space4,
                ),
                children: <Widget>[
                  for (var i = 0; i < _blocks.length; i++) _blockWithInsert(i),
                  _insertPoint(_blocks.length),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _blockWithInsert(int index) {
    final block = _blocks[index];
    return Column(
      children: <Widget>[
        _insertPoint(index),
        if (block.type == 'text')
          _textBlock(block)
        else if (block.type == 'node')
          _nodeBlock(block)
        else
          _mediaBlock(block),
      ],
    );
  }

  Widget _insertPoint(int index) {
    final open = _insertMenuAt == index;
    final uploading = _uploadingAt == index;
    final bool isLast = index >= _blocks.length;
    return Column(
      children: <Widget>[
        Container(
          height: 1,
          margin: EdgeInsets.symmetric(vertical: CyTokens.space1_5),
          color: CyPalette.of(context).borderSubtle,
        ),
        if (uploading)
          Semantics(
            liveRegion: true,
            label: _uploadingType == StoryMediaType.image ? '图片上传中' : '音频上传中',
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const CupertinoActivityIndicator(),
                  const SizedBox(width: 8),
                  Text(
                    _uploadingType == StoryMediaType.image
                        ? '图片上传中…'
                        : '音频上传中…',
                  ),
                ],
              ),
            ),
          )
        else if (!open)
          // 小程序缝点有 aria-label(末尾缝是「在故事流末尾添加内容」);
          // 这个钮一行一个,不给标签读屏只读得到一个「+」。
          Semantics(
            label: isLast ? '在故事流末尾添加内容' : '在第${index + 1}段前添加内容',
            button: true,
            excludeSemantics: true,
            child: CupertinoButton(
              key: Key('story-insert-$index'),
              onPressed: () => setState(() {
                _insertMenuAt = _insertMenuAt == index ? -1 : index;
              }),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              // ★ 热区撑到 44pt(最小触达尺寸),视觉仍是那个 18pt 的加号。
              //   原来是 18 + space1×2 = 26pt —— 这个钮在长列表里每段之间
              //   都出现一次,点不中就会误触到相邻段落。
              child: SizedBox(
                height: 44,
                width: 44,
                child: Center(
                  child: Icon(
                    CupertinoIcons.add_circled,
                    size: 18,
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
              ),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 四颗小钮各带小程序同款 aria-label —— 可见文字只有一个字,
                // 读屏读「＋ 文字」听不出是插一个文字块。
                Semantics(
                  container: true,
                  button: true,
                  label: '添加文字块',
                  excludeSemantics: true,
                  onTap: () {
                    setState(() => _insertMenuAt = -1);
                    _apply(
                      InsertTextAtCommand(index: index, blockKey: _newKey()),
                    );
                  },
                  child: CupertinoButton.tinted(
                    key: Key('story-insert-text-$index'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () {
                      setState(() => _insertMenuAt = -1);
                      _apply(
                        InsertTextAtCommand(index: index, blockKey: _newKey()),
                      );
                    },
                    child: const Text('＋ 文字'),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  container: true,
                  button: true,
                  label: '添加图片块',
                  excludeSemantics: true,
                  onTap: () => _pickAndInsertMedia(StoryMediaType.image, index),
                  child: CupertinoButton.tinted(
                    key: Key('story-insert-image-$index'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () =>
                        _pickAndInsertMedia(StoryMediaType.image, index),
                    child: const Text('＋ 图片'),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  container: true,
                  button: true,
                  label: '添加音频块',
                  excludeSemantics: true,
                  onTap: () => _pickAndInsertMedia(StoryMediaType.audio, index),
                  child: CupertinoButton.tinted(
                    key: Key('story-insert-audio-$index'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () =>
                        _pickAndInsertMedia(StoryMediaType.audio, index),
                    child: const Text('＋ 音频'),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  container: true,
                  button: true,
                  label: '添加节点块',
                  excludeSemantics: true,
                  onTap: () {
                    setState(() => _insertMenuAt = -1);
                    widget.onInsertNodeAt(index);
                  },
                  child: CupertinoButton.tinted(
                    key: Key('story-insert-node-$index'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () {
                      setState(() => _insertMenuAt = -1);
                      widget.onInsertNodeAt(index);
                    },
                    child: const Text('＋ 节点'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _newKey() => 'b${DateTime.now().microsecondsSinceEpoch}';

  Widget _textBlock(StoryBlock block) {
    final selected = _selectedBlockKey == block.key;
    return Stack(
      children: <Widget>[
        Focus(
          onFocusChange: (focused) {
            if (focused) {
              if (_selectedBlockKey != block.key) {
                setState(() => _selectedBlockKey = block.key);
              }
            } else {
              // 清空后失焦自动移除:内容全删光,块本身就该消失。
              if (block.content.trim().isEmpty) {
                _removeText(block);
              }
            }
          },
          child: CupertinoTextField(
            key: ValueKey<String>(block.key),
            controller: _textControllerFor(block),
            onChanged: (v) =>
                _apply(EditTextCommand(blockKey: block.key, content: v)),
            maxLines: null,
            minLines: 2,
            maxLength: 5000,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            placeholder: '写下这一段故事…',
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: selected
                  ? CyPalette.of(context).bgSurfaceSubtle
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              border: Border.all(
                color: selected
                    ? CyPalette.of(context).borderStrong
                    : CyPalette.of(context).borderSubtle,
              ),
            ),
          ),
        ),
        if (selected)
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              container: true,
              label: '删除文字块',
              button: true,
              excludeSemantics: true,
              onTap: () => _removeText(block),
              child: CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: () => _removeText(block),
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 16,
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _nodeBlock(StoryBlock block) {
    final selected = _selectedBlockKey == block.key;
    final nodes = _chapter.nodes;
    final nodeIndex = nodes.indexWhere((n) => n.localId == block.nodeKey);
    if (nodeIndex < 0) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: CyTokens.space2),
        child: Text(
          '节点块引用已失效',
          style: TextStyle(
            color: CyPalette.of(context).statusDanger,
            fontSize: CyTokens.typeLabel,
          ),
        ),
      );
    }
    final node = nodes[nodeIndex];
    var number = 0;
    for (final b in _blocks) {
      if (b.type != 'node') continue;
      number++;
      if (b.key == block.key) break;
    }
    final hasGame = hasGameplay(node);
    final photos = node.imgList;
    void edit() => widget.onEditNode(node.localId);
    void select() => setState(() => _selectedBlockKey = block.key);
    return Semantics(
      container: true,
      button: true,
      label: '编辑节点 ${node.name.isEmpty ? '未命名' : node.name}',
      hint: '轻点编辑，长按选中后可删除',
      onTap: edit,
      onLongPress: select,
      excludeSemantics: !selected,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: edit,
        onLongPress: select,
        child: Container(
          margin: EdgeInsets.only(bottom: CyTokens.space2),
          padding: EdgeInsets.all(CyTokens.space3),
          decoration: BoxDecoration(
            color: CyPalette.of(context).bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            border: selected
                ? Border.all(color: CyPalette.of(context).brand)
                : Border.all(color: CyPalette.of(context).borderSubtle),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CyPalette.of(context).bgElevated,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textPrimary,
                  ),
                ),
              ),
              SizedBox(width: CyTokens.space3),
              if (photos.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    photos.first,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 44, height: 44),
                  ),
                )
              else
                Icon(
                  Icons.image_outlined,
                  size: 28,
                  color: CyPalette.of(context).textTertiary,
                ),
              SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      node.name.isEmpty ? '未命名' : node.name,
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${node.address.isEmpty ? '点击选择地点' : node.address}'
                      '${node.address.isEmpty ? '' : (hasGame ? ' · 玩法已配' : ' · 玩法待配')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Semantics(
                  container: true,
                  label: '删除节点块 ${node.name.isEmpty ? '未命名' : node.name}',
                  button: true,
                  onTap: () => _removeNode(block),
                  excludeSemantics: true,
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => _removeNode(block),
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 16,
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaBlock(StoryBlock block) {
    final bool selected = _selectedBlockKey == block.key;
    final bool isImage = block.type == 'image';
    void select() => setState(() => _selectedBlockKey = block.key);
    return Semantics(
      label: isImage ? '图片片段' : '音频片段',
      hint: '长按选中后可删除',
      selected: selected,
      onLongPress: select,
      excludeSemantics: !selected,
      child: GestureDetector(
        key: Key('story-media-${block.key}'),
        excludeFromSemantics: true,
        onLongPress: select,
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: CyTokens.space2),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CyPalette.of(context).bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            border: Border.all(
              color: selected
                  ? CyPalette.of(context).brand
                  : CyPalette.of(context).borderSubtle,
            ),
          ),
          child: Stack(
            children: <Widget>[
              if (isImage)
                CyNetImage(
                  block.url,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                )
              else
                const SizedBox(
                  height: 72,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: CyTokens.space3),
                    child: Row(
                      children: <Widget>[
                        Icon(CupertinoIcons.play_circle_fill, size: 32),
                        SizedBox(width: CyTokens.space3),
                        Text('音频片段'),
                      ],
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Semantics(
                    container: true,
                    label: isImage ? '删除图片块' : '删除音频块',
                    button: true,
                    child: CupertinoButton(
                      key: Key('story-media-remove-${block.key}'),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      onPressed: () => _removeMedia(block),
                      child: ExcludeSemantics(
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: CyPalette.of(context).textSecondary,
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

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space3,
      ),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        border: Border(
          top: BorderSide(color: CyPalette.of(context).borderSubtle),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: CupertinoButton.tinted(
              minimumSize: const Size.fromHeight(44),
              onPressed: () => _apply(
                InsertTextAtCommand(index: _blocks.length, blockKey: _newKey()),
              ),
              child: const Text('＋ 加一段文字'),
            ),
          ),
          SizedBox(width: CyTokens.space3),
          Expanded(
            child: CupertinoButton(
              minimumSize: const Size.fromHeight(44),
              color: CyPalette.of(context).actionPrimaryBg,
              foregroundColor: CyPalette.of(context).actionPrimaryFg,
              onPressed: () => widget.onInsertNodeAt(_blocks.length),
              child: const Text('＋ 创建节点'),
            ),
          ),
        ],
      ),
    );
  }
}
