/// The transport protocol or adapter used for uploading files.
enum UploadProtocol {
  /// Standard HTTP upload (multipart/form-data or binary PUT/PATCH stream).
  standard,

  /// Resumable byte-range chunked upload using HTTP `Content-Range` headers.
  resumable,

  /// Open Tus.io resumable upload protocol (v1.0.0).
  tus,

  /// Amazon AWS S3 or S3-compatible (MinIO, Wasabi, Cloudflare R2) multipart upload.
  s3Multipart,

  /// Simulated network transfer for testing, offline demos, and speed verification.
  simulated,

  /// Custom registered adapter.
  custom,
}

/// Extension methods for [UploadProtocol].
extension UploadProtocolX on UploadProtocol {
  /// Internal adapter key used in the adapter registry.
  String get adapterKey {
    switch (this) {
      case UploadProtocol.standard:
        return 'dio';
      case UploadProtocol.resumable:
        return 'resumable';
      case UploadProtocol.tus:
        return 'tus';
      case UploadProtocol.s3Multipart:
        return 's3';
      case UploadProtocol.simulated:
        return 'simulated';
      case UploadProtocol.custom:
        return 'custom';
    }
  }

  /// User-friendly display name.
  String get displayName {
    switch (this) {
      case UploadProtocol.standard:
        return 'Standard HTTP';
      case UploadProtocol.resumable:
        return 'Resumable (Byte Range)';
      case UploadProtocol.tus:
        return 'Tus.io Protocol';
      case UploadProtocol.s3Multipart:
        return 'AWS S3 Multipart';
      case UploadProtocol.simulated:
        return 'Simulated Transfer';
      case UploadProtocol.custom:
        return 'Custom Adapter';
    }
  }
}
