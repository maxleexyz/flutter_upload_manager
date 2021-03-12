import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_upload_manager/flutter_upload_manager.dart';
import 'package:http_client/console.dart' as console;
import 'package:oss_flutter/oss_flutter.dart';

class Storage implements StateDelegate {
  Storage();
  UpState old;
  Storage.fromOldState(UpState state) {
    old = state;
  }
  @override
  UpState loadByPath(String filePath) {
    // TODO: implement loadByPath
    return old;
  }

  @override
  Future removeState(String filePath) {
    // TODO: implement removeState
    print('do remove state:$filePath');
  }

  @override
  Future saveState(String filePath, UpState state) {
    // TODO: implement saveState
    print('do save state:$state');
  }
}

class Uploader implements UploadDelegate {
  final http = console.ConsoleClient(autoUncompress: true);
  final client = Client.static(
      'LTAItrC9kXkItCLK', 'bmElAFgKQNQLjKdnuI8BpG9xuQ5fvn', 'ap-northeast-1');

  @override
  Future<UpState> completePart(String fileKey, UpState state) async {
    // TODO: implement cpmletePart

    final cplReq = client.completePartUpload(
        'codiario', fileKey, state.uploadId, state.etags);
    final cplRequest = new console.Request(cplReq.method, cplReq.Url,
        headers:
            console.Headers((cplReq.headers ?? {}).cast<String, dynamic>()),
        body: cplReq.fileData);
    final console.Response cplResponse = await http.send(cplRequest);
    print('${await cplResponse.readAsString()}');
    print("complete");
    return state;
  }

  @override
  Future<UpState> directUpload(
      String fileKey, UpState state, List<int> fileData) async {
    // TODO: implement directUpload
    print("will upload: $state");
    print("data len:${fileData.length}");
    await Future.delayed(Duration(seconds: 1));
    print('uploaded');
    state.chunks[0].state = 1;
    state.successCount += 1;
    return state;
  }

  @override
  Future<UpState> initPartialUpload(String fileKey, UpState state) async {
    // TODO: implement initPartialUpload
    final req = client.initMultipartUpload('codiario', fileKey);
    final request = new console.Request(req.method, req.url,
        headers: console.Headers((req.headers ?? {}).cast<String, dynamic>()),
        body: req.fileData);
    final console.Response response = await http.send(request);
    final ossresp = OSSResponse(await response.readAsString());
    ossresp.raise_exception();
    final uploadId = ossresp.getKey('UploadId');
    state.uploadId = uploadId;
    print("part upload inited");
    return state;
  }

  @override
  initUpload(UpState state) {
    // TODO: implement initUpload
    print('init upload:$state');
    return state;
  }

  @override
  onFinished(UpState state) {
    // TODO: implement onFinished
    print("upload finished with state:$state");
  }

  @override
  updatePercentage(int success, int total) {
    // TODO: implement updatePercentage
    print("$success/$total");
  }

  @override
  Future<String> uploadPart(
      String fileKey, UpState state, int idx, List<int> chunkData) async {
    // TODO: implement uploadPart
    final upReq =
        client.uploadPart('codiario', fileKey, state.uploadId, idx, chunkData);
    final upRequest = new console.Request(upReq.method, upReq.Url,
        headers: console.Headers((upReq.headers ?? {}).cast<String, dynamic>()),
        body: upReq.fileData);
    print('up url:${upReq.url}');
    final console.Response upResponse = await http.send(upRequest);
    final etag = upResponse.headers['ETag'];
    print("idx $idx uploaded ${chunkData.length} bytes");
    return etag.first;
  }

  @override
  Future<List<int>> encrypt(List<int> rawData) async {
    // TODO: implement encrypt
    await Future.delayed(Duration(seconds: 1));
    return rawData;
  }
}

void main() {
  test('new state', () {
    UpState state = new UpState('', 'path', 100, 0, '');
    final list = new List<int>.generate(100, (i) => i + 1);
    var splitList = [];
    for (var i = 0; i < state.chunks.length; i++) {
      final chunkstate = state.chunks[i];
      splitList.add(list.sublist(chunkstate.startIdx, chunkstate.endIdx));
    }
    for (var j = 0; j < splitList.length - 1; j++) {
      final r1 = splitList[j];
      final r2 = splitList[j + 1];
      expect(r1.last + 1, r2.first);
    }
  });
  test("single upload", () async {
    final stateStorage = new Storage();
    final executor = new Uploader();
    final manager = new UpManager(executor, stateStorage);
    final state = await manager.upfile(
        '',
        "/Users/alex/Projects/workspace/flutter_upload_manager/flutter_upload_manager/test/test_data.txt",
        1070);
  });

  test("Multiple upload", () async {
    final stateStorage = new Storage();
    final executor = new Uploader();
    final manager = new UpManager(executor, stateStorage);
    final file = new File('/Users/alex/Documents/novel/jzj.txt');
    final state = await manager.upfile('test/sjzj.txt',
        "/Users/alex/Documents/novel/jzj.txt", file.lengthSync());
    print('$state');
  });

  test("Broken upload", () async {
    final filePath = "/Users/alex/Documents/novel/jzj.txt";
    final file = new File(filePath);
    final fileLength = file.lengthSync();
    final fileContent = await file.readAsBytes();
    expect(fileContent.length, fileLength);
    final upState =
        new UpState("test_id", filePath, fileLength, 3, '', chunkSize: 501001);
    print(upState);
    final chunks = <List<int>>[];
    var total_length = 0;
    for (var chunkState in upState.chunks) {
      final slice = fileContent.sublist(chunkState.startIdx, chunkState.endIdx);
      total_length += slice.length;
      chunks.add(slice);
    }
    print('slice total=:$total_length');
    expect(total_length, fileLength);
  });
}
