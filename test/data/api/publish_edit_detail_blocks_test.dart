import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/publish/publish_draft_logic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('edit-detail 无损恢复 text/image/audio/node，重新提交语义等价', () async {
    final PublishApi api = _buildApi(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'topic': <String, dynamic>{'name': '梧桐故事', 'productType': 1},
        'chapters': <dynamic>[
          <String, dynamic>{
            'id': 31,
            'name': '第一章',
            'description': '旧摘要不应覆盖 blocks',
            'cmsTopicNodeList': <dynamic>[
              <String, dynamic>{'id': 101, 'name': '老书店', 'sortID': 1},
              <String, dynamic>{'id': 102, 'name': '街角咖啡', 'sortID': 2},
            ],
            'blocks': <dynamic>[
              <String, dynamic>{'type': 'text', 'content': '开场\n第二段'},
              <String, dynamic>{
                'type': 'image',
                'url': 'https://cdn.example/story.jpg',
              },
              <String, dynamic>{
                'type': 'audio',
                'url': 'https://cdn.example/story.m4a',
              },
              <String, dynamic>{'type': 'node', 'nodeId': 102},
              <String, dynamic>{'type': 'future-video', 'url': 'ignore'},
              <String, dynamic>{'type': 'image', 'url': ''},
              <String, dynamic>{'type': 'node', 'nodeId': 999},
              <String, dynamic>{'type': 'node', 'nodeId': 101},
            ],
          },
        ],
        'tickets': <dynamic>[],
      },
    });

    final (PublishDraft draft, _) = await api.editDetail(7);
    final PublishChapter chapter = draft.chapters.single;
    expect(chapter.description, '旧摘要不应覆盖 blocks');
    expect(chapter.blocks, isNotNull);
    expect(chapter.blocks!.map((StoryBlock block) => block.type), <String>[
      'text',
      'image',
      'audio',
      'node',
      'node',
    ]);
    expect(chapter.blocks![0].content, '开场\n第二段');
    expect(chapter.blocks![1].url, 'https://cdn.example/story.jpg');
    expect(chapter.blocks![2].url, 'https://cdn.example/story.m4a');
    expect(chapter.blocks![3].nodeKey, chapter.nodes[1].localId);
    expect(chapter.blocks![4].nodeKey, chapter.nodes[0].localId);
    expect(
      chapter.blocks!.map((StoryBlock block) => block.key).toSet(),
      hasLength(5),
    );
    expect(
      chapter.blocks!.every((StoryBlock block) => block.key.isNotEmpty),
      isTrue,
    );

    final Map<String, dynamic> payload = buildTopicPayload(draft);
    final Map<String, dynamic> sentChapter =
        (payload['chapters'] as List<dynamic>).single as Map<String, dynamic>;
    expect(sentChapter['blocks'], <dynamic>[
      <String, dynamic>{'type': 'text', 'content': '开场\n第二段'},
      <String, dynamic>{
        'type': 'image',
        'url': 'https://cdn.example/story.jpg',
      },
      <String, dynamic>{
        'type': 'audio',
        'url': 'https://cdn.example/story.m4a',
      },
      <String, dynamic>{'type': 'node', 'nodeIndex': 0},
      <String, dynamic>{'type': 'node', 'nodeIndex': 1},
    ]);
    expect(
      (sentChapter['nodes'] as List<dynamic>).map(
        (dynamic node) => (node as Map<String, dynamic>)['name'],
      ),
      <String>['街角咖啡', '老书店'],
    );

    final PublishApi reopenedApi = _buildApi(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'topic': <String, dynamic>{'name': '梧桐故事', 'productType': 1},
        'chapters': <dynamic>[sentChapter],
        'tickets': <dynamic>[],
      },
    });
    final (PublishDraft reopened, _) = await reopenedApi.editDetail(7);
    expect(
      reopened.chapters.single.blocks!.map(
        (StoryBlock block) => <String, String>{
          'type': block.type,
          'content': block.content,
          'url': block.url,
          'node': block.type == 'node'
              ? reopened.chapters.single.nodes
                    .singleWhere(
                      (PublishNode node) => node.localId == block.nodeKey,
                    )
                    .name
              : '',
        },
      ),
      <Map<String, String>>[
        <String, String>{
          'type': 'text',
          'content': '开场\n第二段',
          'url': '',
          'node': '',
        },
        <String, String>{
          'type': 'image',
          'content': '',
          'url': 'https://cdn.example/story.jpg',
          'node': '',
        },
        <String, String>{
          'type': 'audio',
          'content': '',
          'url': 'https://cdn.example/story.m4a',
          'node': '',
        },
        <String, String>{
          'type': 'node',
          'content': '',
          'url': '',
          'node': '街角咖啡',
        },
        <String, String>{
          'type': 'node',
          'content': '',
          'url': '',
          'node': '老书店',
        },
      ],
    );
  });

  test('旧 detail 没有 blocks 时继续保留 description + nodes 兼容路径', () async {
    final PublishApi api = _buildApi(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'topic': <String, dynamic>{'name': '存量主题', 'productType': 1},
        'chapters': <dynamic>[
          <String, dynamic>{
            'id': 41,
            'name': '存量章节',
            'description': '存量文字',
            'cmsTopicNodeList': <dynamic>[
              <String, dynamic>{'id': 201, 'name': '存量节点', 'sortID': 1},
            ],
          },
        ],
        'tickets': <dynamic>[],
      },
    });

    final (PublishDraft draft, _) = await api.editDetail(8);
    final PublishChapter chapter = draft.chapters.single;
    expect(chapter.description, '存量文字');
    expect(chapter.nodes.single.name, '存量节点');
    expect(chapter.blocks, isNull);

    final Map<String, dynamic> sentChapter =
        (buildTopicPayload(draft)['chapters'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(sentChapter['description'], '存量文字');
    expect(sentChapter.containsKey('blocks'), isFalse);
    expect(sentChapter['nodes'], hasLength(1));
  });
}

PublishApi _buildApi(Map<String, dynamic> reply) {
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = _StubAdapter(reply);
  return PublishApi(client);
}

class _StubAdapter implements HttpClientAdapter {
  const _StubAdapter(this.reply);

  final Map<String, dynamic> reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
