library flutter_upload_manager;

import 'dart:async';
import 'dart:io';

class UploadException extends Error {
  String errMsg() => 'Upload Faild';
}

//const int DEFAULT_CHUNK_SIZE = 93;
const int DEFAULT_CHUNK_SIZE = 1024 * 1024 * 5;

class ChunkState {
  static const IdKey = 'Id';
  static const StartIdxKey = 'startIdx';
  static const EndIdxKey = 'endIdx';
  static const StateKey = 'state';
  static const EtagKey = 'etag';

  /// chunkId
  int id;

  /// range start of file
  int startIdx;

  /// range end of file
  int endIdx;

  /// upload state 0=uploading 1=success 2
  int state;

  /// etag from upload result
  String etag;

  /// save object as a dictionary
  Map asMap() => {
        IdKey: id,
        StartIdxKey: startIdx,
        EndIdxKey: endIdx,
        StateKey: state,
        EtagKey: etag
      };

  /// Constructor for new
  ChunkState(this.id, this.startIdx, this.endIdx, this.state);

  /// Constructor for instance from storage
  ChunkState.fromMap(Map map) {
    this.id = map[IdKey];
    this.startIdx = map[StartIdxKey];
    this.endIdx = map[EndIdxKey];
    this.state = map[StateKey];
    this.etag = map[EtagKey];
  }
  @override
  String toString() =>
      "id:$id from:$startIdx to:$endIdx state:$state of etag:$etag";
}

class UpState {
  static const UploadIdKey = 'uploadId';
  static const FilepathKey = 'filepath';
  static const FilesizeKey = 'filesize';
  static const ChunksKey = 'chunks';
  static const SuccessCountKey = 'successCount';

  /// unique id of
  String uploadId;

  /// upload file path
  String filePath;

  /// file size used to caculate chunks
  int fileSize;

  /// upload chunks
  List<ChunkState> chunks;

  /// success chunks count
  int successCount;

  /// Constructor for new
  UpState(this.uploadId, this.filePath, this.fileSize, this.successCount,
      {int chunkSize: DEFAULT_CHUNK_SIZE}) {
    assert(this.fileSize <= chunkSize * 100);
    this.chunks = <ChunkState>[];
    for (var i = 0; i < 300; i++) {
      final startIdx = i * chunkSize;
      var endIdx = (i + 1) * chunkSize;
      if (endIdx > fileSize - 1) {
        endIdx = fileSize - 1;
      }
      this.chunks.add(new ChunkState(i + 1, startIdx, endIdx, 0));
      if (endIdx == fileSize - 1) {
        // be sure reach the end of file, quit loop
        break;
      }
    }
  }

  get etags => this.chunks.map((chunkState) => chunkState.etag).toList();

  /// Constructor for instance from storage
  UpState.fromMap(Map map) {
    this.uploadId = map[UploadIdKey];
    this.filePath = map[FilepathKey];
    this.fileSize = map[FilesizeKey];
    for (final ck in map[ChunksKey]) {
      this.chunks.add(ChunkState.fromMap(ck));
    }
    this.successCount = map[SuccessCountKey];
  }

  Map toMap(){
    return {
      UploadIdKey: this.uploadId,
      FilepathKey: this.filePath,
      FilesizeKey: this.fileSize,
      ChunksKey: this.chunks.map((e) => e.asMap()).toList(),
      SuccessCountKey: this.successCount
    }
  }

  @override
  String toString() =>
      "$filePath($fileSize) chunks:${chunks.map((c) => c.toString()).join('\n')} successCount:$successCount";
}

/// Delegate for implement state storage
abstract class StateDelegate {
  Future saveState(String filePath, UpState state);
  UpState loadByPath(String filePath);
  Future removeState(String filePath);
}

/// Delegate for implement upload
abstract class UploadDelegate {
  initUpload(UpState state);
  Future<List<int>> encrypt(List<int> rawData);
  Future<UpState> directUpload(UpState state, List<int> fileData);
  Future<UpState> initPartialUpload(UpState state);
  Future<String> uploadPart(UpState state, int idx, List<int> chunkData);
  Future<UpState> completePart(UpState state);
  updatePercentage(int total, int success);
  onFinished(UpState state);
}

/// Manager
class UpManager {
  /// executor
  UploadDelegate upExecutor;

  /// state
  StateDelegate stateStorage;

  /// Constructor
  UpManager(this.upExecutor, this.stateStorage);

  Future<List<int>> loadFile(filePath) async {
    final file = new File(filePath);
    return (await file.readAsBytes()).toList();
  }

  Future upfile(String filePath, int fileSize) async {
    UpState state = stateStorage.loadByPath(filePath);
    if (state != null && state.successCount == state.chunks.length) {
      // if have a old state, check if need reupload
      await _processOldState(state);
    } else {
      final fileData = await loadFile(filePath);
      if (state == null) {
        state = UpState('', filePath, fileSize, 0);
        upExecutor.initUpload(state);
        if (state.chunks.length < 2) {
          // if single chunk
          await _processOneChunk(state, fileData, filePath);
        } else {
          await _processMultiChunk(state, filePath, fileData);
        }
      } else {
        // 端点续传
        await _processBrokenState(state, fileData, filePath);
      }
    }
  }

  Future _processBrokenState(
      UpState state, List<int> fileData, String filePath) async {
    assert(state.uploadId.isNotEmpty);
    final ps = state.chunks
        .map((i) => i)
        .where((chunkState) => chunkState.state < 1)
        .map((e) => processUpPart(state, e.id - 1, fileData));
    await Future.wait(ps);
    await _checkResult(state, filePath);
  }

  Future _processMultiChunk(
      UpState state, String filePath, List<int> fileData) async {
    state = await upExecutor.initPartialUpload(state);
    final chunkIdxList = new List<int>.generate(state.chunks.length, (i) => i);
    // wait for each chunk uploaded
    await Future.wait(
        chunkIdxList.map((cid) => processUpPart(state, cid, fileData)));
    await _checkResult(state, filePath);
  }

  Future _checkResult(UpState state, String filePath) async {
    if (state.chunks.map((st) => st.state).reduce((v1, v2) => v1 + v2) !=
        state.chunks.length) {
      // if success count not equal to total means faild
      await stateStorage.saveState(filePath, state);
      upExecutor.onFinished(state);
    } else {
      await stateStorage.removeState(filePath);
      upExecutor.onFinished(state);
    }
  }

  Future processUpPart(UpState state, int chunkIdx, List<int> fileData) async {
    final chunkState = state.chunks[chunkIdx];
    List<int> chunkData =
        fileData.sublist(chunkState.startIdx, chunkState.endIdx);
    final etag = await upExecutor.uploadPart(
        state, chunkIdx, await this.upExecutor.encrypt(chunkData));
    if (etag.isNotEmpty) {
      chunkState.state = 1;
      chunkState.etag = etag;
      state.successCount += 1;
      upExecutor.updatePercentage(state.successCount, state.chunks.length);
    } else {
      throw new UploadException();
    }
  }

  Future _processOneChunk(
      UpState state, List<int> fileData, String filePath) async {
    state = await upExecutor.directUpload(
        state, await this.upExecutor.encrypt(fileData));
    if (state.successCount > 0) {
      await stateStorage.removeState(filePath);
      assert(state != null);
      upExecutor.onFinished(state);
    }
  }

  Future _processOldState(UpState state) async {
    // success direct and remove state
    await stateStorage.removeState(state.filePath);
  }
}
