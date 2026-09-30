import 'package:chengyin_app/data/models/square_draft.dart';
import 'package:chengyin_app/feature/square/square_local_draft_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('网络失败前的未完成草稿可以本地恢复并清除', () async {
    const store = SquareLocalDraftStore(FlutterSecureStorage());
    const draft = SquareDraft(
      workflowId: 'stable-request-1',
      contents: '还没写完',
      commentPolicy: 'MENTIONED',
      pics: <String>['https://img.test/a.jpg'],
      picByteSizes: <int>[123],
      picMimeTypes: <String>['image/jpeg'],
      picUploadReceipts: <String>['receipt-1'],
    );

    expect(await store.save(8, draft), isTrue);
    final restored = await store.read(8);
    expect(restored?.workflowId, 'stable-request-1');
    expect(restored?.contents, '还没写完');
    expect(restored?.commentPolicy, 'MENTIONED');
    expect(restored?.pics, <String>['https://img.test/a.jpg']);

    expect(await store.clear(8), isTrue);
    expect(await store.read(8), isNull);
  });

  test('草稿按账号隔离且完整恢复编辑身份与已有媒体', () async {
    const store = SquareLocalDraftStore(FlutterSecureStorage());
    const draft = SquareDraft(
      workflowId: 'edit-21',
      id: 21,
      expectedVersion: 4,
      sourceLifecycle: 'PUBLISHED',
      contents: '私密位置草稿',
      existingMediaIds: <int>[91, 92],
      existingPicCount: 2,
      longitude: '121.47',
      latitude: '31.23',
    );

    expect(await store.save(8, draft), isTrue);
    expect(await store.read(9, postId: 21), isNull);
    final restored = await store.read(8, postId: 21);
    expect(restored?.id, 21);
    expect(restored?.expectedVersion, 4);
    expect(restored?.sourceLifecycle, 'PUBLISHED');
    expect(restored?.existingMediaIds, <int>[91, 92]);
    expect(restored?.existingPicCount, 2);
  });

  test('已发布帖文的本机修改稿按 postId 分槽，打开 B 不覆盖 A', () async {
    const store = SquareLocalDraftStore(FlutterSecureStorage());
    const draftA = SquareDraft(
      workflowId: 'edit-post-a',
      id: 21,
      sourceLifecycle: 'PUBLISHED',
      contents: 'A 的本机修改稿',
    );
    const draftB = SquareDraft(
      workflowId: 'edit-post-b',
      id: 22,
      sourceLifecycle: 'PUBLISHED',
      contents: 'B 的本机修改稿',
    );

    expect(await store.save(8, draftA), isTrue);
    expect(await store.save(8, draftB), isTrue);
    expect((await store.read(8, postId: 21))?.contents, 'A 的本机修改稿');
    expect((await store.read(8, postId: 22))?.contents, 'B 的本机修改稿');
    expect(await store.clear(8, postId: 22), isTrue);
    expect((await store.read(8, postId: 21))?.contents, 'A 的本机修改稿');
  });

  test('listFor 枚举本账号的新稿与修改稿，按账号隔离', () async {
    const store = SquareLocalDraftStore(FlutterSecureStorage());
    expect(
      await store.save(
        8,
        const SquareDraft(workflowId: 'w-new', contents: '新帖草稿'),
      ),
      isTrue,
    );
    expect(
      await store.save(
        8,
        const SquareDraft(
          workflowId: 'w-21',
          id: 21,
          sourceLifecycle: 'PUBLISHED',
          contents: '21 的修改稿',
        ),
      ),
      isTrue,
    );
    expect(
      await store.save(
        9,
        const SquareDraft(workflowId: 'w-9', contents: '别人的'),
      ),
      isTrue,
    );

    final entries = await store.listFor(8);
    expect(entries.map((e) => e.postId), <int?>[null, 21]);
    expect(entries.first.draft.contents, '新帖草稿');
    expect(entries.last.draft.sourceLifecycle, 'PUBLISHED');

    expect(await store.clear(8, postId: 21), isTrue);
    expect((await store.listFor(8)).map((e) => e.postId), <int?>[null]);
    expect(await store.listFor(9), hasLength(1));
  });

  test('listFor 跳过损坏槽位与陌生后缀，游客得到空清单', () async {
    const store = SquareLocalDraftStore(FlutterSecureStorage());
    await store.save(8, const SquareDraft(workflowId: 'w-ok', contents: '好的'));
    const raw = FlutterSecureStorage();
    await raw.write(
      key: 'community_post_local_draft_v4:8:post:9',
      value: '不是 JSON',
    );
    await raw.write(
      key: 'community_post_local_draft_v4:8:别的后缀',
      value: '{"memberId":8}',
    );

    final entries = await store.listFor(8);
    expect(entries.map((e) => e.draft.contents), <String>['好的']);
    expect(await store.listFor(0), isEmpty);
  });
}
