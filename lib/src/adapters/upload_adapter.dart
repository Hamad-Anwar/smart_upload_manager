import 'dart:async';
import 'package:dio/dio.dart';
import '../models/upload_task.dart';

/// Progress callback receiving current sent bytes and total file bytes.
typedef UploadProgressCallback = void Function(int sentBytes, int totalBytes);

/// Standardized response returned by any [UploadAdapter].
class UploadResponse {
  /// HTTP response status code.
  final int statusCode;

  /// Response body returned by server (parsed JSON, String, etc.).
  final dynamic data;

  /// Response headers returned by server.
  final Map<String, List<String>> headers;

  const UploadResponse({
    required this.statusCode,
    this.data,
    this.headers = const {},
  });

  /// Whether the request completed with a 2xx HTTP success code.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  @override
  String toString() => 'UploadResponse(statusCode: $statusCode, isSuccess: $isSuccess)';
}

/// Abstract contract for implementing upload transport mechanisms.
///
/// Custom adapters can be plugged in for REST APIs, S3 multipart, Tus, GraphQL, etc.
abstract class UploadAdapter {
  /// Unique identifier of this adapter (e.g. 'dio', 'resumable', 'tus', 's3').
  String get id;

  /// Whether this adapter supports resuming from a previously confirmed byte offset.
  bool get supportsResuming => false;

  /// Performs the actual file upload for [task].
  ///
  /// Must report progress via [onProgress] and honor [cancelToken].
  Future<UploadResponse> upload({
    required UploadTask task,
    required UploadProgressCallback onProgress,
    required CancelToken cancelToken,
  });

  /// Queries the remote server for the number of bytes already uploaded for [task].
  ///
  /// Returns 0 if resuming is not supported or no bytes have been uploaded yet.
  Future<int> getConfirmedOffset(UploadTask task) async => 0;

  /// Cancels an active upload associated with [taskId].
  Future<void> cancel(String taskId);

  /// Pauses an active upload associated with [taskId].
  Future<void> pause(String taskId);

  /// Closes and releases any adapter network clients or resources.
  Future<void> dispose() async {}
}
