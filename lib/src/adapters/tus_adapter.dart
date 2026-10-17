import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/upload_task.dart';
import 'upload_adapter.dart';

/// Adapter implementing the open Tus.io resumable upload protocol (v1.0.0).
///
/// Handles creation (POST), offset checking (HEAD), and chunk streaming (PATCH).
class TusUploadAdapter implements UploadAdapter {
  final Dio _dio;
  final int chunkSize;
  final Map<String, CancelToken> _cancelTokens = {};

  TusUploadAdapter({
    Dio? dio,
    this.chunkSize = 1024 * 1024 * 2, // 2 MB chunks
  }) : _dio = dio ?? Dio();

  @override
  String get id => 'tus';

  @override
  bool get supportsResuming => true;

  @override
  Future<int> getConfirmedOffset(UploadTask task) async {
    final uploadUrl = task.resumableSessionId ?? task.url;
    try {
      final response = await _dio.head<dynamic>(
        uploadUrl,
        options: Options(
          headers: {
            ...task.headers,
            'Tus-Resumable': '1.0.0',
          },
        ),
      );
      final offsetHeader = response.headers.value('upload-offset');
      if (offsetHeader != null) {
        return int.tryParse(offsetHeader) ?? task.resumableOffset;
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
    var uploadUrl = task.resumableSessionId;

    // 1. Creation step if no upload URL exists yet
    if (uploadUrl == null || uploadUrl.isEmpty) {
      final encodedFilename = base64Encode(utf8.encode(task.fileName));
      final initHeaders = <String, dynamic>{
        ...task.headers,
        'Tus-Resumable': '1.0.0',
        'Upload-Length': fileSize.toString(),
        'Upload-Metadata': 'filename $encodedFilename',
      };

      final createResponse = await _dio.post<dynamic>(
        task.url,
        options: Options(
          headers: initHeaders,
          validateStatus: (status) => status != null && (status == 201 || status == 200),
        ),
        cancelToken: cancelToken,
      );

      final location = createResponse.headers.value('location');
      if (location != null && location.isNotEmpty) {
        uploadUrl = Uri.parse(task.url).resolve(location).toString();
      } else {
        uploadUrl = task.url;
      }
    }

    // 2. Check current offset
    var offset = await getConfirmedOffset(task);
    if (offset < 0 || offset > fileSize) {
      offset = 0;
    }

    final raf = await file.open(mode: FileMode.read);
    UploadResponse lastResponse = const UploadResponse(statusCode: 204);

    try {
      while (offset < fileSize) {
        if (cancelToken.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: uploadUrl),
            type: DioExceptionType.cancel,
            message: 'Tus upload cancelled',
          );
        }

        final currentChunk = min(chunkSize, fileSize - offset);
        await raf.setPosition(offset);
        final bytes = await raf.read(currentChunk);

        final patchHeaders = <String, dynamic>{
          ...task.headers,
          'Tus-Resumable': '1.0.0',
          'Upload-Offset': offset.toString(),
          'Content-Type': 'application/offset+octet-stream',
          'Content-Length': bytes.length.toString(),
        };

        final response = await _dio.patch<dynamic>(
          uploadUrl,
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: patchHeaders,
            validateStatus: (status) => status != null && (status == 204 || status == 200),
          ),
          cancelToken: cancelToken,
          onSendProgress: (sent, _) {
            onProgress(offset + sent, fileSize);
          },
        );

        final newOffsetHeader = response.headers.value('upload-offset');
        if (newOffsetHeader != null) {
          offset = int.tryParse(newOffsetHeader) ?? (offset + bytes.length);
        } else {
          offset += bytes.length;
        }

        onProgress(offset, fileSize);

        final headersMap = <String, List<String>>{};
        response.headers.forEach((key, values) {
          headersMap[key] = values;
        });

        lastResponse = UploadResponse(
          statusCode: response.statusCode ?? 204,
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
      token.cancel('Tus upload cancelled by user');
    }
  }

  @override
  Future<void> pause(String taskId) async {
    final token = _cancelTokens.remove(taskId);
    if (token != null && !token.isCancelled) {
      token.cancel('Tus upload paused');
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
