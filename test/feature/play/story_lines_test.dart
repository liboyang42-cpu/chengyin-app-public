import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/story_lines.dart';
import 'package:flutter_test/flutter_test.dart';

/// ★ 章节固件必须走 `PlayChapter.fromJson` 喂 `/api/play/nodes` 的**后端真实键**
/// (`name` / `imgArr` / `description` / `audioUrl`,**没有** meta/title/cover)——
/// 用构造函数直接造 PlayChapter 会绕过解析层,键名错配完全隐形
/// (这条分支上同一失效模式已出现三次)。
PlayChapter _chap({String? description, String? imgArr, String name = '旧书与唱片'}) =>
    PlayChapter.fromJson(<String, dynamic>{
      'chapterId': 100,
      'name': name,
      'description': description,
      'imgArr': imgArr,
    }, 1);

void main() {
  test('空 description 返回空列表 —— 调用方据此不开页', () {
    expect(buildStoryLines(_chap(description: '  ')), isEmpty);
  });

  test('多段:标题在首,图片插在第一段之后', () {
    final List<StoryLine> l = buildStoryLines(
      _chap(description: 'a\n\nb\n\nc', imgArr: 'http://x/1.jpg'),
    );
    expect(l.map((StoryLine e) => e.runtimeType).toList(), <Type>[
      StoryTitleLine,
      StoryTextLine,
      StoryImageLine,
      StoryTextLine,
      StoryTextLine,
    ]);
  });

  test('只有一段:图片排在它后面', () {
    final List<StoryLine> l = buildStoryLines(
      _chap(description: '只有一段', imgArr: 'http://x/1.jpg'),
    );
    expect(l.last, isA<StoryImageLine>());
  });

  test('章节无封面时退到节点首图', () {
    final List<StoryLine> l = buildStoryLines(
      _chap(description: 'a'),
      nodeImgUrl: 'http://x/a.jpg,http://x/b.jpg',
    );
    expect(l.whereType<StoryImageLine>().single.url, 'http://x/a.jpg');
  });

  test('章节自带封面时不被节点首图顶掉', () {
    final List<StoryLine> l = buildStoryLines(
      _chap(description: 'a', imgArr: 'http://x/chap.jpg,http://x/2.jpg'),
      nodeImgUrl: 'http://x/node.jpg',
    );
    expect(l.whereType<StoryImageLine>().single.url, 'http://x/chap.jpg');
  });

  test('两端都没有图时一行图都不渲 —— 空 url 的图行是个撑高度的黑块', () {
    final List<StoryLine> l = buildStoryLines(_chap(description: 'a\n\nb'));
    expect(l.whereType<StoryImageLine>(), isEmpty);
  });

  test('单换行也分段,空段丢掉', () {
    final List<StoryLine> l = buildStoryLines(
      _chap(description: 'a\nb\n\n   \n\nc'),
    );
    expect(
      l.whereType<StoryTextLine>().map((StoryTextLine e) => e.text).toList(),
      <String>['a', 'b', 'c'],
    );
  });

  test('标题行带上眉标与章节名', () {
    final StoryTitleLine t = buildStoryLines(
      _chap(description: 'a'),
    ).whereType<StoryTitleLine>().single;
    expect(t.meta, '第 2 章');
    expect(t.title, '旧书与唱片');
  });

  test('行 id 唯一 —— 重复 id 会让列表复用错行', () {
    final List<StoryLine> l = buildStoryLines(
      _chap(description: 'a\n\nb\n\nc', imgArr: 'http://x/1.jpg'),
    );
    final Set<String> ids = l.map((StoryLine e) => e.id).toSet();
    expect(ids.length, l.length);
  });
}
