import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../models/upload_task.dart';
import 'upload_adapter.dart';

/// Standard HTTP upload adapter using [Dio].
///
/// Supports multipart/form-data (default) and raw binary streaming (for PUT/PATCH).
class DioUploadAdapter implements UploadAdapter {
  final Dio _dio;
  final Map<String, CancelToken> _cancelTokens = {};

  DioUploadAdapter({Dio? dio}) : _dio = dio ?? Dio();

  @override
  String get id => 'dio';

  @override
  bool get supportsResuming => false;

  @override
  Future<UploadResponse> upload({
    required UploadTask task,
    required UploadProgressCallback onProgress,
    required CancelToken cancelToken,
  }) async {
    _cancelTokens[task.id] = cancelToken;

    final paths = task.filePaths.isNotEmpty ? task.filePaths : [task.filePath];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('File not found at path: $path');
      }
    }

    var totalCalculatedSize = 0;
    for (final path in paths) {
      totalCalculatedSize += await File(path).length();
    }
    final effectiveTotalSize =
        task.totalBytes > 0 ? task.totalBytes : totalCalculatedSize;

    final options = Options(
      method: task.method,
      headers: Map<String, dynamic>.from(task.headers),
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status < 500,
    );

    dynamic bodyData;
    if (task.method.toUpperCase() == 'PUT' ||
        task.headers['Content-Type'] == 'application/octet-stream') {
      // Direct raw binary stream upload
      final file = File(paths.first);
      bodyData = file.openRead();
      options.headers?['Content-Length'] = effectiveTotalSize;
    } else if (paths.length > 1) {
      // Multi-file multipart form data upload
      final formData = FormData();
      for (final path in paths) {
        final contentType = _resolveContentType(path, task.metadata);
        final filename = p.basename(path);
        final multipartFile = await MultipartFile.fromFile(
          path,
          filename: filename,
          contentType: contentType,
        );
        formData.files.add(MapEntry(task.fileFieldName, multipartFile));
      }

      for (final entry in task.data.entries) {
        formData.fields.add(MapEntry(entry.key, entry.value.toString()));
      }

      bodyData = formData;
      options.headers?.removeWhere(
        (key, _) => key.toLowerCase() == 'content-type',
      );
    } else {
      // Single-file multipart form data upload
      final path = paths.first;
      final contentType = _resolveContentType(path, task.metadata);

      final multipartFile = await MultipartFile.fromFile(
        path,
        filename: p.basename(path),
        contentType: contentType,
      );

      final formMap = <String, dynamic>{
        task.fileFieldName: multipartFile,
        ...task.data,
      };
      bodyData = FormData.fromMap(formMap);
      // Remove any explicit Content-Type from headers when using multipart, so Dio sets boundary correctly
      options.headers?.removeWhere(
        (key, _) => key.toLowerCase() == 'content-type',
      );
    }

    try {
      final response = await _dio.request<dynamic>(
        task.url,
        data: bodyData,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          final effectiveTotal = total > 0 ? total : effectiveTotalSize;
          onProgress(sent, effectiveTotal);
        },
      );

      final headersMap = <String, List<String>>{};
      response.headers.forEach((key, values) {
        headersMap[key] = values;
      });

      return UploadResponse(
        statusCode: response.statusCode ?? 200,
        data: response.data,
        headers: headersMap,
      );
    } finally {
      _cancelTokens.remove(task.id);
    }
  }

  static DioMediaType? _resolveContentType(
    String path,
    Map<String, dynamic> metadata,
  ) {
    final customMime = metadata['mimeType'] as String? ??
        metadata['contentType'] as String?;
    if (customMime != null) {
      try {
        return DioMediaType.parse(customMime);
      } catch (_) {}
    }

    final ext = p.extension(path).toLowerCase();
    const mimeMap = <String, String>{
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
      '.avif': 'image/avif',
      '.pdf': 'application/pdf',
      '.csv': 'text/csv',
      '.mp4': 'video/mp4',
      '.mov': 'video/quicktime',
      '.mp3': 'audio/mpeg',
      '.doc': 'application/msword',
      '.docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };

    final detected = mimeMap[ext];
    if (detected != null) {
      try {
        return DioMediaType.parse(detected);
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<int> getConfirmedOffset(UploadTask task) async => 0;

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
