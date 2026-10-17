import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/upload_task.dart';
import 'upload_adapter.dart';

/// Adapter supporting AWS S3 and S3-compatible (MinIO, Wasabi, Cloudflare R2) multipart uploads.
class S3MultipartUploadAdapter implements UploadAdapter {
  final Dio _dio;
  final int partSize;
  final Map<String, CancelToken> _cancelTokens = {};

  S3MultipartUploadAdapter({
    Dio? dio,
    this.partSize = 5 * 1024 * 1024, // S3 5 MB standard minimum part size
  }) : _dio = dio ?? Dio();

  @override
  String get id => 's3';

  @override
  bool get supportsResuming => true;

  @override
  Future<int> getConfirmedOffset(UploadTask task) async {
    // Offset calculation based on confirmed uploaded chunks
    final confirmedParts = task.uploadedChunks.length;
    return confirmedParts * partSize;
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
    final totalParts = (fileSize / partSize).ceil();
    final uploadedChunks = List<int>.from(task.uploadedChunks);

    final raf = await file.open(mode: FileMode.read);
    UploadResponse lastResponse = const UploadResponse(statusCode: 200);

    try {
      for (var partNumber = 1; partNumber <= totalParts; partNumber++) {
        if (cancelToken.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: task.url),
            type: DioExceptionType.cancel,
            message: 'S3 multipart upload cancelled',
          );
        }

        // Skip parts that were already uploaded in earlier attempts
        if (uploadedChunks.contains(partNumber)) {
          final sentSoFar = min(partNumber * partSize, fileSize);
          onProgress(sentSoFar, fileSize);
          continue;
        }

        final startByte = (partNumber - 1) * partSize;
        final currentPartSize = min(partSize, fileSize - startByte);

        await raf.setPosition(startByte);
        final bytes = await raf.read(currentPartSize);

        // Put request for this part
        final response = await _dio.put<dynamic>(
          task.url,
          queryParameters: {
            'partNumber': partNumber,
            'uploadId': task.resumableSessionId ?? '',
          },
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: {
              ...task.headers,
              'Content-Length': bytes.length.toString(),
            },
            validateStatus: (status) => status != null && status < 300,
          ),
          cancelToken: cancelToken,
          onSendProgress: (sent, _) {
            onProgress(startByte + sent, fileSize);
          },
        );

        uploadedChunks.add(partNumber);
        final sentTotal = min(startByte + bytes.length, fileSize);
        onProgress(sentTotal, fileSize);

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
      token.cancel('S3 upload cancelled by user');
    }
  }

  @override
  Future<void> pause(String taskId) async {
    final token = _cancelTokens.remove(taskId);
    if (token != null && !token.isCancelled) {
      token.cancel('S3 upload paused');
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
