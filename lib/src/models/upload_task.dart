import 'package:path/path.dart' as p;
import 'task_priority.dart';
import 'upload_protocol.dart';
import 'upload_status.dart';

/// Represents a single file upload task in the queue.
class UploadTask {
  /// Unique identifier for this task.
  final String id;

  /// Local path of the primary file to be uploaded.
  final String filePath;

  /// List of file paths if this task uploads multiple files in a single request.
  final List<String> filePaths;

  /// Target HTTP endpoint URL.
  final String url;

  /// HTTP method (e.g., 'POST', 'PUT', 'PATCH'). Defaults to 'POST'.
  final String method;

  /// Additional HTTP headers to attach to the upload request.
  final Map<String, String> headers;

  /// Optional extra data / form fields.
  final Map<String, dynamic> data;

  /// The form field name used when sending multipart requests. Defaults to 'file' (or 'files').
  final String fileFieldName;

  /// Priority of this upload task in the queue.
  final TaskPriority priority;

  /// Current lifecycle state of the upload.
  final UploadStatus status;

  /// Total size of all files in bytes.
  final int totalBytes;

  /// Confirmed number of bytes uploaded so far.
  final int uploadedBytes;

  /// Current upload speed in bytes per second.
  final double speed;

  /// Estimated time remaining to complete the upload.
  final Duration? eta;

  /// Number of times this task has been retried after failures.
  final int retryCount;

  /// Optional maximum retries override for this specific task.
  final int? maxRetries;

  /// Last error message, if failed.
  final String? error;

  /// Timestamp when the task was created.
  final DateTime createdAt;

  /// Timestamp when the task was last updated.
  final DateTime updatedAt;

  /// Timestamp when the task completed successfully.
  final DateTime? completedAt;

  /// Optional tag or group identifier (e.g. 'avatar', 'story', 'document').
  final String? tag;

  /// Custom metadata attached by the developer (e.g. userId, documentId).
  final Map<String, dynamic> metadata;

  /// Strongly-typed transport protocol used for this upload (e.g. [UploadProtocol.standard], [UploadProtocol.tus]).
  final UploadProtocol protocol;

  /// Optional custom adapter identifier if using [UploadProtocol.custom].
  final String? customAdapterId;

  /// Resumable session ID or upload URL returned by the server.
  final String? resumableSessionId;

  /// Confirmed byte offset for resumable/chunked uploads.
  final int resumableOffset;

  /// List of confirmed chunk indices uploaded (for chunked/multipart uploads).
  final List<int> uploadedChunks;

  /// Response payload returned by the server upon successful upload completion.
  final dynamic response;

  UploadTask({
    required this.id,
    String? filePath,
    List<String>? filePaths,
    required this.url,
    this.method = 'POST',
    this.headers = const {},
    this.data = const {},
    this.fileFieldName = 'file',
    this.priority = TaskPriority.normal,
    this.status = UploadStatus.enqueued,
    this.totalBytes = 0,
    this.uploadedBytes = 0,
    this.speed = 0.0,
    this.eta,
    this.retryCount = 0,
    this.maxRetries,
    this.error,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedAt,
    this.tag,
    this.metadata = const {},
    UploadProtocol? protocol,
    String? adapterType,
    this.customAdapterId,
    this.resumableSessionId,
    this.resumableOffset = 0,
    this.uploadedChunks = const [],
    this.response,
  }) : filePaths =
           filePaths ??
           (filePath != null && filePath.isNotEmpty ? [filePath] : const []),
       filePath =
           filePath ??
           (filePaths != null && filePaths.isNotEmpty ? filePaths.first : ''),
       protocol =
           protocol ??
           (adapterType != null
               ? _parseProtocol(adapterType)
               : UploadProtocol.standard),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Whether this task uploads multiple files simultaneously in one request.
  bool get isMultiFile => filePaths.length > 1;

  /// Internal adapter key lookup.
  String get adapterType => customAdapterId ?? protocol.adapterKey;

  /// Normalized progress from 0.0 to 1.0.
  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (uploadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// Integer progress percentage (0 - 100).
  int get progressPercent => (progress * 100).round();

  /// Filename extracted from [filePath] or multi-file summary.
  String get fileName {
    if (isMultiFile) {
      return '${filePaths.length} files';
    }
    return p.basename(filePath);
  }

  /// Human-readable total file size (e.g. "12.4 MB").
  String get formattedTotalSize => formatBytes(totalBytes);

  /// Human-readable uploaded size (e.g. "8.2 MB").
  String get formattedUploadedSize => formatBytes(uploadedBytes);

  /// Human-readable upload speed (e.g. "1.5 MB/s").
  String get formattedSpeed => '${formatBytes(speed.round())}/s';

  /// Human-readable estimated time remaining (e.g. "1m 30s").
  String get formattedEta {
    if (eta == null) return '--';
    final seconds = eta!.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainingSecs = seconds % 60;
    return '${minutes}m ${remainingSecs}s';
  }

  /// Creates a copy of this task with specified fields replaced.
  UploadTask copyWith({
    String? id,
    String? filePath,
    List<String>? filePaths,
    String? url,
    String? method,
    Map<String, String>? headers,
    Map<String, dynamic>? data,
    String? fileFieldName,
    TaskPriority? priority,
    UploadStatus? status,
    int? totalBytes,
    int? uploadedBytes,
    double? speed,
    Duration? eta,
    int? retryCount,
    int? maxRetries,
    String? error,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    String? tag,
    Map<String, dynamic>? metadata,
    UploadProtocol? protocol,
    String? customAdapterId,
    String? adapterType,
    String? resumableSessionId,
    int? resumableOffset,
    List<int>? uploadedChunks,
    dynamic response,
  }) {
    return UploadTask(
      id: id ?? this.id,
      filePath:
          filePath ??
          (filePaths != null && filePaths.isNotEmpty
              ? filePaths.first
              : this.filePath),
      filePaths: filePaths ?? this.filePaths,
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      data: data ?? this.data,
      fileFieldName: fileFieldName ?? this.fileFieldName,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      completedAt: completedAt ?? this.completedAt,
      tag: tag ?? this.tag,
      metadata: metadata ?? this.metadata,
      protocol:
          protocol ??
          (adapterType != null ? _parseProtocol(adapterType) : this.protocol),
      customAdapterId: customAdapterId ?? this.customAdapterId,
      resumableSessionId: resumableSessionId ?? this.resumableSessionId,
      resumableOffset: resumableOffset ?? this.resumableOffset,
      uploadedChunks: uploadedChunks ?? this.uploadedChunks,
      response: response ?? this.response,
    );
  }

  /// Converts the task to a JSON-serializable Map for persistence.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'filePaths': filePaths,
      'url': url,
      'method': method,
      'headers': headers,
      'data': data,
      'fileFieldName': fileFieldName,
      'priority': priority.index,
      'status': status.index,
      'totalBytes': totalBytes,
      'uploadedBytes': uploadedBytes,
      'speed': speed,
      'etaSeconds': eta?.inSeconds,
      'retryCount': retryCount,
      'maxRetries': maxRetries,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'tag': tag,
      'metadata': metadata,
      'protocol': protocol.name,
      'customAdapterId': customAdapterId,
      'adapterType': adapterType,
      'resumableSessionId': resumableSessionId,
      'resumableOffset': resumableOffset,
      'uploadedChunks': uploadedChunks,
      'response': response,
    };
  }

  /// Deserializes an [UploadTask] from a stored JSON Map.
  factory UploadTask.fromJson(Map<String, dynamic> json) {
    final protocolRaw = json['protocol'] as String?;
    final adapterTypeRaw = json['adapterType'] as String?;
    final resolvedProtocol = _parseProtocol(protocolRaw ?? adapterTypeRaw);

    final rawFilePaths = json['filePaths'] as List?;
    final filePathsList = rawFilePaths != null
        ? List<String>.from(rawFilePaths)
        : (json['filePath'] != null && (json['filePath'] as String).isNotEmpty
              ? [json['filePath'] as String]
              : <String>[]);

    return UploadTask(
      id: json['id'] as String,
      filePath:
          json['filePath'] as String? ??
          (filePathsList.isNotEmpty ? filePathsList.first : ''),
      filePaths: filePathsList,
      url: json['url'] as String,
      method: json['method'] as String? ?? 'POST',
      headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      fileFieldName: json['fileFieldName'] as String? ?? 'file',
      priority: TaskPriority
          .values[json['priority'] as int? ?? TaskPriority.normal.index],
      status: UploadStatus
          .values[json['status'] as int? ?? UploadStatus.enqueued.index],
      totalBytes: json['totalBytes'] as int? ?? 0,
      uploadedBytes: json['uploadedBytes'] as int? ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      eta: json['etaSeconds'] != null
          ? Duration(seconds: json['etaSeconds'] as int)
          : null,
      retryCount: json['retryCount'] as int? ?? 0,
      maxRetries: json['maxRetries'] as int?,
      error: json['error'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      tag: json['tag'] as String?,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
      protocol: resolvedProtocol,
      customAdapterId: json['customAdapterId'] as String?,
      resumableSessionId: json['resumableSessionId'] as String?,
      resumableOffset: json['resumableOffset'] as int? ?? 0,
      uploadedChunks: List<int>.from(json['uploadedChunks'] as List? ?? []),
      response: json['response'],
    );
  }

  static UploadProtocol _parseProtocol(String? key) {
    if (key == null) return UploadProtocol.standard;
    for (final p in UploadProtocol.values) {
      if (p.name == key || p.adapterKey == key) return p;
    }
    return UploadProtocol.custom;
  }

  /// Utility function to format raw byte counts into human readable strings.
  static String formatBytes(num bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  @override
  String toString() =>
      'UploadTask(id: $id, file: $fileName, protocol: ${protocol.name}, status: ${status.name}, progress: $progressPercent%)';
}
