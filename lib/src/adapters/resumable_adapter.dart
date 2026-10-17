import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/upload_task.dart';
import 'upload_adapter.dart';

/// Resumable chunked upload adapter.
///
/// Uploads files in byte-range chunks and resumes from the last confirmed server byte offset
/// instead of restarting from 0% if interrupted.
class ResumableUploadAdapter implements UploadAdapter {
  final Dio _dio;
  final int chunkSize;
  final Map<String, CancelToken> _cancelTokens = {};

  ResumableUploadAdapter({
    Dio? dio,
    this.chunkSize = 1024 * 1024, // 1 MB default chunks
  }) : _dio = dio ?? Dio();

  @override
  String get id => 'resumable';

  @override
  bool get supportsResuming => true;

  @override
  Future<int> getConfirmedOffset(UploadTask task) async {
    // If the server supports HEAD or GET to query offset
    try {
      final response = await _dio.head<dynamic>(
        task.url,
        options: Options(headers: task.headers),
      );
      final rangeHeader = response.headers.value('range') ??
          response.headers.value('upload-offset');
      if (rangeHeader != null) {
        final parsed = int.tryParse(rangeHeader.replaceAll(RegExp(r'[^0-9]'), ''));
        if (parsed != null) return parsed;
      }
    } catch (_) {}
    return task.resumableOffset;
  }

  @override
  Future<UploadResponse> upload({
    required UploadTask task,
    required UploadProgressCallback onProgress,
    required CancelToken cancelToken,
  }) async {
    _cancelTokens[task.id] = cancelToken;

    final file = File(task.filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found at path: ${task.filePath}');
    }

    final fileSize = await file.length();
    var offset = task.resumableOffset;
    if (offset < 0 || offset > fileSize) {
      offset = 0;
    }

    final raf = await file.open(mode: FileMode.read);
    UploadResponse lastResponse = const UploadResponse(statusCode: 200);

    try {
      while (offset < fileSize) {
        if (cancelToken.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: task.url),
            type: DioExceptionType.cancel,
            message: 'Upload was cancelled',
          );
        }

        final currentChunkSize = min(chunkSize, fileSize - offset);
        await raf.setPosition(offset);
        final bytes = await raf.read(currentChunkSize);

        final end = offset + bytes.length - 1;
        final headers = <String, dynamic>{
          ...task.headers,
          'Content-Range': 'bytes $offset-$end/$fileSize',
          'Content-Length': bytes.length,
          'Content-Type': 'application/octet-stream',
        };

        if (task.resumableSessionId != null) {
          headers['Upload-Session-Id'] = task.resumableSessionId!;
        }

        final response = await _dio.request<dynamic>(
          task.url,
          data: Stream.fromIterable([bytes]),
          options: Options(
            method: task.method,
            headers: headers,
            responseType: ResponseType.json,
            validateStatus: (status) => status != null && status < 500,
          ),
          cancelToken: cancelToken,
          onSendProgress: (sent, _) {
            onProgress(offset + sent, fileSize);
          },
        );

        if (response.statusCode != null &&
            (response.statusCode! < 200 || response.statusCode! >= 300)) {
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            message: 'Server returned HTTP ${response.statusCode} during chunk upload',
          );
        }

        offset += bytes.length;
        onProgress(offset, fileSize);

        final headersMap = <String, List<String>>{};
        response.headers.forEach((key, values) {
          headersMap[key] = values;
        });

        lastResponse = UploadResponse(
          statusCode: response.statusCode ?? 200,
          data: response.data,
          headers: headersMap,
        );
      }

      return lastResponse;
    } finally {
      await raf.close();
      _cancelTokens.remove(task.id);
    }
  }

  @override
  Future<void> cancel(String taskId) async {
    final token = _cancelTokens.remove(taskId);
    if (token != null && !token.isCancelled) {
      token.cancel('Task cancelled by user');
    }
  }

  @override
  Future<void> pause(String taskId) async {
    final token = _cancelTokens.remove(taskId);
    if (token != null && !token.isCancelled) {
      token.cancel('Task paused');
    }
  }

  @override
  Future<void> dispose() async {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('Adapter disposed');
      }
    }
    _cancelTokens.clear();
  }
}
