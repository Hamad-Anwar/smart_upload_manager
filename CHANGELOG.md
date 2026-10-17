## 1.0.1

* Updated dependencies to latest stable versions (`dio: ^5.11.1`, `connectivity_plus: ^7.3.2`, `flutter_local_notifications: ^22.3.2`, `uuid: ^4.6.0`, `crypto: ^3.0.7`, `path_provider: ^2.1.6`, `path: ^1.9.1`, `meta: ^1.17.0`).
* Added support for `flutter_local_notifications` 22.x named parameters.
* Handled new `DioExceptionType.transformTimeout` error type.
* Tightened dependency constraint lower bounds to ensure 100% clean downgrade analysis.

## 1.0.0

* Initial release of `smart_upload_manager`.
* Persistent atomic file storage (`FileQueueStorage`) ensuring queue survives app crashes and restarts.
* Strongly-typed `UploadProtocol` enum (`standard`, `resumable`, `tus`, `s3Multipart`, `simulated`, `custom`) eliminating raw strings.
* Simplified 1-line `SmartUploadManager.upload(...)` and `File.upload(...)` extension methods with direct callbacks (`onProgress`, `onSuccess`, `onError`).
* Zero-configuration automatic lazy initialization on first use.
* Drop-in UI widgets: `UploadProgressBar` and `UploadTaskTile` with built-in animations and task controls.
* Resumable chunked upload support with pluggable adapters:
  - `DioUploadAdapter`: standard multipart/binary streaming uploads.
  - `ResumableUploadAdapter`: byte-range chunks with `Content-Range`.
  - `TusUploadAdapter`: implementation of the open tus.io resumable protocol.
  - `S3MultipartUploadAdapter`: Amazon S3 multipart uploads.
  - `SimulatedUploadAdapter`: realistic offline/speed testing adapter.
* Priority-based queue scheduling (`TaskPriority.critical`, `high`, `normal`, `low`) with FIFO ordering.
* Network connectivity monitor with auto-pause on disconnect and auto-resume on reconnect.
* Dynamic auth token / header provider for token refresh during long uploads.
* Exponential backoff retry policy with randomized jitter.
* Background upload notifications with real-time progress bar, speed (MB/s), and ETA using `flutter_local_notifications`.
* Comprehensive interactive example application with online/offline simulation.
