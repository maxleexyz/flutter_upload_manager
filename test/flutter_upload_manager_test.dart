import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_upload_manager/flutter_upload_manager.dart';

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
  @override
  Future<UpState> completePart(String fileKey, UpState state) async {
    // TODO: implement cpmletePart
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
    await Future.delayed(Duration(seconds: 1));
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
    await Future.delayed(Duration(seconds: 1));
    print("idx $idx uploaded ${chunkData.length} bytes");
    return '${new DateTime.now().millisecondsSinceEpoch}';
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
    final state = await manager.upfile(
        '',
        "/Users/alex/Projects/workspace/flutter_upload_manager/flutter_upload_manager/test/test_data.txt",
        1070);
  });

  test("Broken upload", () async {
    final filePath =
        "/Users/alex/Projects/workspace/flutter_upload_manager/flutter_upload_manager/test/test_data.txt";
    final upState = new UpState("test_id", filePath, 1070, 3, '');
    upState.chunks[0].state = 1;
    upState.chunks[1].state = 1;
    upState.chunks[2].state = 1;

    final stateStorage = Storage.fromOldState(upState);
    final executor = new Uploader();
    final manager = new UpManager(executor, stateStorage);
    final state = await manager.upfile('', filePath, 1070);
  });
}
