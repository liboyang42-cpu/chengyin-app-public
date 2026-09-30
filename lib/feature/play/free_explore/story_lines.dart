// 章节故事流的分段构造。**纯函数,不碰 widget** —— 分段与插图位置最容易「看着对、
// 其实排错」,必须能脱离 widget 树断言。语义逐条照搬小程序 `openChapStory`
// (pages/play/index.js:1013-1030)。唯一的例外是 [StoryKitLine]:它只是占位标记,
// 内容由页面(会话视图)供给。

import '../../../data/models/checkin_models.dart';

/// 故事流里的一行。三种形态共用同一套显形动效 ——
/// 用户 09-06 原话:「章节里有图片,也要和文字一样的样式」。
sealed class StoryLine {
  const StoryLine(this.id);

  final String id;
}

/// 抬头行:眉标(第 N 章)+ 章节名。
///
/// ★ 为什么要有它:样机靠 22vh 的上留白把第一段推到屏幕中段,
///   空着不写东西就只是一片黑。它也吃同一套显形动效。
class StoryTitleLine extends StoryLine {
  const StoryTitleLine(super.id, {this.meta, required this.title});

  final String? meta;
  final String title;
}

class StoryTextLine extends StoryLine {
  const StoryTextLine(super.id, this.text);

  final String text;
}

class StoryImageLine extends StoryLine {
  const StoryImageLine(super.id, this.url);

  final String url;
}

/// 内嵌玩法段(契约 §1.5):服务端会话视图 `present=inline` 的 kit 铺在故事流里。
///
/// ★ 它**不**由 [buildStoryLines] 产出 —— 那是章节数据的纯函数,而内嵌 kit
///   来自高级玩法会话视图(异步、随动作刷新)。页面在数据到位后把它追加到
///   行尾:真源把 kit 铺在「第一个未完成节点块」处,而章节 description 的
///   服务端投影本来就停在首个 node 块(`ChapterFlowCompiler:beforeFirstNode`),
///   行尾 = 那个位置;真源兜底那条(没有未完成节点)也是接在末尾。
class StoryKitLine extends StoryLine {
  const StoryKitLine(super.id);
}

/// 章节正文 → 逐行。
///
/// 自由探索的章节走「章节概述」那条路(不是城市定向的块化故事流),所以正文就是
/// `chapter.description` 一个文本域:多了按空行分段、少了就一句,不硬凑。
///
/// ⚠️ **正文为空返回空列表**,调用方据此提示「这一章还没写剧情」并且**不开页**
///   (样机 index.js:1016)—— 开一页空白比不开更像坏了。
///
/// [nodeImgUrl] 是节点的 `imgUrl`(可能是逗号串)。章节自己没有封面时退到它的首段,
/// 与样机 `chapCover: (chap && chap.cover) || node.imgUrl.split(',')[0]`
/// (index.js:1545)同源。
List<StoryLine> buildStoryLines(PlayChapter chapter, {String? nodeImgUrl}) {
  final String text = (chapter.description ?? '').trim();
  if (text.isEmpty) return const <StoryLine>[];

  final List<String> paras = text
      .split(RegExp(r'\n\s*\n|\r?\n'))
      .map((String x) => x.trim())
      .where((String x) => x.isNotEmpty)
      .toList();

  final String cover = _cover(chapter, nodeImgUrl);
  // 图片块插在第一段之后;只有一段时 at 越界,落到末尾那条分支排在它后面。
  final int at = paras.length > 1 ? 1 : paras.length;

  final List<StoryLine> lines = <StoryLine>[];
  final String title = (chapter.title ?? '').trim();
  if (title.isNotEmpty) {
    lines.add(StoryTitleLine('ttl', meta: chapter.meta, title: title));
  }
  for (int i = 0; i < paras.length; i++) {
    if (i == at && cover.isNotEmpty) lines.add(StoryImageLine('img', cover));
    lines.add(StoryTextLine('p$i', paras[i]));
  }
  if (at >= paras.length && cover.isNotEmpty) {
    lines.add(StoryImageLine('img', cover));
  }
  return lines;
}

String _cover(PlayChapter chapter, String? nodeImgUrl) {
  final String own = (chapter.cover ?? '').trim();
  if (own.isNotEmpty) return own;
  return (nodeImgUrl ?? '').split(',').first.trim();
}
