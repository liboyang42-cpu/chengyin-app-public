import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_net_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_image_source_sheet.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/registration_api.dart';
import '../../data/models/profile_detail.dart';
import '../../data/models/category.dart';
import '../../data/models/profile_edit.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../club/club_image_picker.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

final myProfileProvider = FutureProvider.autoDispose<ProfileDetail>((ref) {
  return ref.watch(registrationApiProvider).userDetail();
});

/// 编辑个人资料。对齐小程序 `pages/gerenziliao`。
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _introductionController = TextEditingController();
  ProfileEditForm? _original;
  ProfileEditForm _form = const ProfileEditForm();
  bool _saving = false;
  bool _uploading = false;

  /// 「资料没有保存」那行行内错误(真源 cy-inline-error)。保存失败只弹 toast 时,
  /// 用户划走了提示就再也不知道上一次到底存没存上。
  String? _saveError;

  /// 路线偏好 —— 表单只存 id(tagIds),名字是回显用的缓存。
  List<Category> _routePreferences = const <Category>[];

  void _removeRoutePreference(int id) {
    setState(() {
      _routePreferences = _routePreferences
          .where((Category category) => category.id != id)
          .toList(growable: false);
      _form = _form.copyWith(
        tagIds: _routePreferences
            .map((Category category) => category.id)
            .toList(growable: false),
      );
    });
  }

  Future<void> _pickRoutePreferences() async {
    final List<Category>? picked = await showProfileRoutePreferenceSheet(
      context,
      ref,
      selected: _routePreferences,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _routePreferences = picked;
      _form = _form.copyWith(
        tagIds: picked
            .map((Category category) => category.id)
            .toList(growable: false),
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _introductionController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(BuildContext avatarContext) async {
    // 选图走共用层 action sheet(对照表 #31):真源 `app.chooseImage` 是
    // `sourceType: ['album','camera']`,App 之前直接进相册、没有拍照这一路。
    // S4:锚点 = 触发元素(那个头像)自己的矩形。
    final CyImagePickSource? source = await cyChooseImageSource(
      context,
      sourceRect: cySourceRectOf(avatarContext),
    );
    if (source == null || !mounted) return;
    final XFile? file = await ImagePicker().pickImage(
      source: source == CyImagePickSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(playApiProvider).uploadImage(file.path);
      if (!mounted) return;
      setState(() => _form = _form.copyWith(avatar: url));
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        '头像没传上去:${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 探索作品:一次可多选,上限 9 张(真源 `uploadCasePics` 的 remainingCount 口径)。
  Future<void> _pickCasePics() async {
    const int maxPics = 9;
    final int remaining = maxPics - _form.casePics.length;
    if (remaining <= 0) {
      CyNativeNotice.show(context, '最多只能上传9张图片');
      return;
    }
    await _uploadInto(
      maxCount: remaining,
      onUploaded: (List<String> urls) {
        final List<String> next = <String>[..._form.casePics, ...urls];
        setState(
          () => _form = _form.copyWith(
            casePics: next.take(maxPics).toList(growable: false),
          ),
        );
      },
    );
  }

  /// 联系二维码:单张。真源把它存在 `wechat` 字段里(存储的是图片 URL)。
  Future<void> _pickWechat() async {
    await _uploadInto(
      maxCount: 1,
      onUploaded: (List<String> urls) {
        if (urls.isEmpty) return;
        setState(() => _form = _form.copyWith(wechat: urls.first));
      },
    );
  }

  Future<void> _uploadInto({
    required int maxCount,
    required ValueChanged<List<String>> onUploaded,
  }) async {
    final List<String> urls = await pickAndUploadImages(
      context,
      ref,
      maxCount: maxCount,
    );
    if (!mounted || urls.isEmpty) return;
    onUploaded(urls);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref.read(registrationApiProvider).updateProfile(_form);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, '已保存');
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      // ★ 内容被审核拒了,重试没用 —— 要让用户去改文字。
      //   统统说「保存失败,请重试」,用户会一直重试一段永远过不了的文案。
      if (e is ProfileUpdateException && e.contentRejected) {
        setState(() => _saveError = e.message);
        await cyConfirm(
          context,
          title: '内容没能通过审核',
          content: '${e.message}\n\n请修改昵称或简介后再保存。',
          confirmText: '去修改',
          showCancel: false,
        );
        return;
      }
      final String message = e.toString().replaceFirst('Exception: ', '');
      setState(() => _saveError = message);
      CyNativeNotice.show(context, message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 游客深链先挡(报告 #217 P1):这一页整页要登录(真源 gerenziliao 只从
    // 登录后的「我的」进),但路由对游客开放。不挡的话下面立刻打
    // `/api/user/info`,401 落进错误态 —— 显示的是裸 `DioException` 英文,
    // 只有「重试/回首页」,而重试多少次都还是 401(死路)。
    // 口径照同域 /profile 的游客态:就地给登录引导,登完留在本页。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return CupertinoPageScaffold(
        // 导航栏与系统返回留着 —— 游客能原路退回去,不是被关在这一屏。
        navigationBar: const CupertinoNavigationBar(middle: Text('编辑资料')),
        child: StatusView(
          message: '登录后编辑我的资料',
          sub: '昵称、头像、城市签名都在这里修改',
          icon: CupertinoIcons.person_crop_circle,
          large: true,
          onRetry: () => showLoginSheet(context),
          retryLabel: '登录 / 注册',
        ),
      );
    }
    final async = ref.watch(myProfileProvider);
    final textTheme = Theme.of(context).textTheme;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('编辑资料')),
      child: SafeArea(
        top: false,
        child: async.when(
          loading: () => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CupertinoActivityIndicator(),
                const SizedBox(height: CyTokens.space2),
                Text(
                  // 真源 gerenziliao.wxml:7-15 —— 首次进来是「正在读取个人资料」,
                  // 已有内容时的刷新态才是「正在核对个人资料…」。两句都不能省:
                  // 刷新时不说这句,用户会以为刚填的东西被清空了。
                  _original == null ? '正在读取个人资料' : '正在核对个人资料…',
                  style: textTheme.bodySmall?.copyWith(
                    color: CyTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          error: (Object e, _) => StatusView(
            message: '个人资料没能加载出来',
            sub: e.toString().replaceFirst('Exception: ', ''),
            large: true,
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
          data: (ProfileDetail me) {
            // 首次拿到资料时初始化表单与「原始值」。
            if (_original == null) {
              final init = ProfileEditForm(
                name: me.nickname,
                avatar: me.avatar,
                introduction: me.introduction,
                wechat: me.wechat,
                casePics: me.casePics,
                tagIds: me.routePreferences
                    .map((Category category) => category.id)
                    .toList(growable: false),
              );
              _original = init;
              _form = init;
              _routePreferences = me.routePreferences;
              _nameController.text = init.name;
              _introductionController.text = init.introduction;
            }
            final blocker = _form.blocker;
            final changed = _form.changedFrom(_original!);

            return Column(
              children: <Widget>[
                // 刷新中(已有内容还在屏幕上)真源的顶部一句
                // 「正在核对个人资料…」(gerenziliao.wxml:15)。不说这句,
                // 用户刚点完保存会以为没反应。
                if (async.isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space2),
                    child: Text(
                      '正在核对个人资料…',
                      style: textTheme.bodySmall?.copyWith(
                        color: CyTokens.textSecondary,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(CyTokens.pageX),
                    children: <Widget>[
                      Center(
                        child: Builder(
                          builder: (BuildContext avatarContext) =>
                              CupertinoButton(
                                onPressed: _uploading
                                    ? null
                                    : () => _pickAvatar(avatarContext),
                                minimumSize: const Size(44, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CyTokens.space3,
                                  vertical: CyTokens.space2,
                                ),
                                child: Column(
                                  children: <Widget>[
                                    CyAvatar(
                                      url: _form.avatar.isEmpty
                                          ? null
                                          : _form.avatar,
                                      fallback: _form.name.isEmpty
                                          ? null
                                          : _form.name.characters.first,
                                      size: 72,
                                    ),
                                    const SizedBox(height: CyTokens.space1),
                                    Text(
                                      _uploading ? '上传中…' : '换头像',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: CyTokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(height: CyTokens.space4),
                      CyField(
                        label: '昵称',
                        child: CupertinoTextField(
                          key: const Key('profile-name-field'),
                          controller: _nameController,
                          placeholder: '填写昵称',
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                          autofillHints: const <String>[AutofillHints.nickname],
                          clearButtonMode: OverlayVisibilityMode.editing,
                          padding: const EdgeInsets.all(CyTokens.space3),
                          onChanged: (String v) =>
                              setState(() => _form = _form.copyWith(name: v)),
                        ),
                      ),
                      CyField(
                        // ★ 小程序这一处叫「城市签名」不叫「简介」
                        //   (pages/gerenziliao/gerenziliao.wxml:24)。
                        //   这是**产品词汇**不是通用字段名 —— 同一件东西
                        //   在两个客户端叫两个名字,用户会以为是两回事。
                        //   ⚠️ 只改这一处:小程序的俱乐部/模板/发布都叫「简介」,
                        //     全局替换会把那三处也改错。
                        label: '城市签名',
                        child: CupertinoTextField(
                          key: const Key('profile-introduction-field'),
                          controller: _introductionController,
                          maxLines: 3,
                          minLines: 3,
                          placeholder: '写一句你喜欢的城市探索方式',
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          autocorrect: true,
                          clearButtonMode: OverlayVisibilityMode.editing,
                          padding: const EdgeInsets.all(CyTokens.space3),
                          onChanged: (String v) => setState(
                            () => _form = _form.copyWith(introduction: v),
                          ),
                        ),
                      ),
                      // 探索作品 / 联系二维码 / 路线偏好 —— 真源 gerenziliao.wxml
                      // 的 8 个区块里 App 缺的三个(手机号那格见页面注释)。
                      CyField(
                        label: '探索作品',
                        child: _CasePicsField(
                          pics: _form.casePics,
                          busy: _uploading,
                          onAdd: _pickCasePics,
                          onRemove: (int index) => setState(() {
                            final List<String> next = List<String>.of(
                              _form.casePics,
                            )..removeAt(index);
                            _form = _form.copyWith(casePics: next);
                          }),
                        ),
                      ),
                      CyField(
                        label: '联系二维码',
                        child: _SingleImageField(
                          key: const Key('profile-wechat-field'),
                          url: _form.wechat,
                          busy: _uploading,
                          actionLabel: '上传联系二维码',
                          onPick: _pickWechat,
                          onRemove: () => setState(
                            () => _form = _form.copyWith(wechat: ''),
                          ),
                        ),
                      ),
                      CyField(
                        label: '路线偏好',
                        child: _RoutePreferenceField(
                          key: const Key('profile-route-preference-field'),
                          categories: _routePreferences,
                          onEdit: _pickRoutePreferences,
                          onRemove: _removeRoutePreference,
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.pageX,
                      CyTokens.space2,
                      CyTokens.pageX,
                      CyTokens.space3,
                    ),
                    child: Column(
                      children: <Widget>[
                        if (_saveError != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: CyTokens.space2,
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  CupertinoIcons.exclamationmark_circle,
                                  size: CyTokens.space4,
                                  color: CyPalette.of(context).statusWarning,
                                ),
                                const SizedBox(width: CyTokens.space2),
                                Expanded(
                                  child: Text(
                                    // 真源 cy-inline-error title + sub:标题点名
                                    // 「资料没有保存」,副行说清这次为什么。
                                    '资料没有保存：$_saveError',
                                    key: const Key('profile-save-error'),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: CyPalette.of(
                                        context,
                                      ).statusWarning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (blocker != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: CyTokens.space2,
                            ),
                            child: Text(
                              blocker,
                              style: textTheme.bodySmall?.copyWith(
                                color: CyTokens.statusWarning,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: CyNativeButton(
                            // ★ 没改动就不给保存 —— 白提交一次会触发一次内容审核,
                            //   可能因为历史文案被拒,平白多一次失败。
                            onPressed: (!_form.canSubmit || !changed || _saving)
                                ? null
                                : _save,
                            label: _saving ? '正在保存' : (changed ? '保存' : '没有改动'),
                            loading: _saving,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 探索作品:缩略图网格 + 「上传路线照片」占位格。
/// 最多 9 张(满 9 张占位格不出,真源 `wx:if="{{tempCasePics.length < 9}}"`)。
class _CasePicsField extends StatelessWidget {
  const _CasePicsField({
    required this.pics,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> pics;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  static const int maxPics = 9;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    if (pics.isEmpty) {
      return _EmptySlot(
        key: const Key('profile-case-pics-empty'),
        label: '上传路线照片',
        hint: '未填写',
        busy: busy,
        onTap: onAdd,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            for (final (int index, String url) in pics.indexed)
              _PictureThumb(
                url: url,
                semanticLabel: '删除这张作品图',
                onRemove: () => onRemove(index),
              ),
            if (pics.length < maxPics)
              _EmptySlot(
                key: const Key('profile-case-pics-add'),
                label: '上传路线照片',
                busy: busy,
                onTap: onAdd,
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          '${pics.length}/$maxPics 张',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
        ),
      ],
    );
  }
}

/// 联系二维码:一张图 + 上传/删除。
class _SingleImageField extends StatelessWidget {
  const _SingleImageField({
    super.key,
    required this.url,
    required this.busy,
    required this.actionLabel,
    required this.onPick,
    required this.onRemove,
  });

  final String url;
  final bool busy;
  final String actionLabel;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _EmptySlot(
        key: const Key('profile-wechat-empty'),
        label: actionLabel,
        hint: '未填写',
        busy: busy,
        onTap: onPick,
      );
    }
    return _PictureThumb(
      url: url,
      semanticLabel: '清除联系二维码',
      onRemove: onRemove,
    );
  }
}

/// 路线偏好:chip 列表(每个带删除)+ 编辑入口。空态写「未填写」。
class _RoutePreferenceField extends StatelessWidget {
  const _RoutePreferenceField({
    super.key,
    required this.categories,
    required this.onEdit,
    required this.onRemove,
  });

  final List<Category> categories;
  final VoidCallback onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (categories.isEmpty)
          Text(
            '未填写',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
          )
        else
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space2,
            children: <Widget>[
              // ★ 传分类 id,不是下标 —— 按下标删会删错(甚至一个都删不掉)。
              for (final Category category in categories)
                _PreferenceChip(
                  name: category.name,
                  onRemove: () => onRemove(category.id),
                ),
            ],
          ),
        const SizedBox(height: CyTokens.space2),
        CupertinoButton(
          key: const Key('profile-route-preference-edit'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          alignment: Alignment.centerLeft,
          onPressed: onEdit,
          child: Text(
            '编辑路线偏好',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({required this.name, required this.onRemove});

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2,
        vertical: CyTokens.space1,
      ),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            name,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(width: CyTokens.space2),
          Semantics(
            button: true,
            label: '移除该分类',
            child: CupertinoButton(
              key: Key('profile-preference-remove-$name'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
              onPressed: onRemove,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: CyTokens.space4,
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PictureThumb extends StatelessWidget {
  const _PictureThumb({
    required this.url,
    required this.semanticLabel,
    required this.onRemove,
  });

  final String url;
  final String semanticLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            child: SizedBox(
              width: 72,
              height: 72,
              child: CyNetImage(url, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            right: -CyTokens.space1,
            top: -CyTokens.space1,
            child: Semantics(
              button: true,
              label: semanticLabel,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(28, 28),
                onPressed: onRemove,
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: CyTokens.space5,
                  color: palette.bgPage,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    super.key,
    required this.label,
    this.hint,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final String? hint;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Row(
      children: <Widget>[
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: busy ? null : onTap,
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            child: Icon(
              busy ? CupertinoIcons.time : CupertinoIcons.add,
              color: palette.textTertiary,
            ),
          ),
        ),
        const SizedBox(width: CyTokens.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                busy ? '上传中…' : label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 路线偏好选择半屏(真源 `components/cy/category-sheet`):
/// 标题「选择分类」,多选打勾,底部「保存」。拉不到分类时说清「先别保存」。
Future<List<Category>?> showProfileRoutePreferenceSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<Category> selected,
}) {
  return showCupertinoSheet<List<Category>>(
    context: context,
    showDragHandle: true,
    topGap: 0.24,
    scrollableBuilder:
        (BuildContext sheetContext, ScrollController scrollController) =>
            _RoutePreferenceSheet(
              ref: ref,
              selected: selected,
              scrollController: scrollController,
            ),
  );
}

class _RoutePreferenceSheet extends ConsumerStatefulWidget {
  const _RoutePreferenceSheet({
    required this.ref,
    required this.selected,
    required this.scrollController,
  });

  final WidgetRef ref;
  final List<Category> selected;
  final ScrollController scrollController;

  @override
  ConsumerState<_RoutePreferenceSheet> createState() =>
      _RoutePreferenceSheetState();
}

class _RoutePreferenceSheetState extends ConsumerState<_RoutePreferenceSheet> {
  bool _loading = true;
  String? _error;
  List<Category> _categories = const <Category>[];
  late List<Category> _selected = List<Category>.of(widget.selected);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Category> list = await widget.ref
          .read(categoryApiProvider)
          .list(type: '1');
      if (!mounted) return;
      setState(() {
        _categories = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _toggle(Category category) {
    setState(() {
      final int index = _selected.indexWhere(
        (Category item) => item.id == category.id,
      );
      if (index >= 0) {
        _selected = List<Category>.of(_selected)..removeAt(index);
      } else {
        _selected = <Category>[..._selected, category];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                CyTokens.space1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '选择分类',
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '关闭分类选择',
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        CupertinoIcons.xmark,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: _body(context)),
            Padding(
              padding: const EdgeInsets.all(CyTokens.pageX),
              child: SizedBox(
                width: double.infinity,
                child: CyNativeButton(
                  key: const Key('profile-preference-save'),
                  label: '保存',
                  onPressed: _loading || _error != null
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return StatusView(
        message: '分类没拉出来',
        sub: '$_error\n分类没拉到时先别保存，可重试',
        onRetry: _load,
        retryLabel: '重试',
      );
    }
    if (_categories.isEmpty) {
      // 真源 cy-empty 的 sub 是「当前类型下还没有配置分类，可稍后再试。」——
      // 「再试」两个字会被 test/status_view_retry_gate_test.dart 判成
      // 「承诺了动作却没给按钮」。空态本来就没有出路(后台没配分类,重试也一样),
      // 所以这里只砍掉那半句承诺,不改立场。
      return const StatusView(message: '暂无可选分类', sub: '当前类型下还没有配置分类。');
    }
    return ListView.builder(
      controller: widget.scrollController,
      shrinkWrap: true,
      itemCount: _categories.length,
      itemBuilder: (BuildContext context, int index) {
        final Category category = _categories[index];
        final bool checked = _selected.any(
          (Category item) => item.id == category.id,
        );
        return CupertinoListTile(
          key: Key('profile-preference-${category.id}'),
          title: Text(category.name),
          trailing: checked
              ? Icon(
                  CupertinoIcons.checkmark_alt,
                  color: CyPalette.of(context).brand,
                )
              : null,
          onTap: () => _toggle(category),
        );
      },
    );
  }
}
