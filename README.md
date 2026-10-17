# smart_upload_manager

A resilient, persistent, offline-tolerant file upload manager for Flutter with automatic retries, resumable chunked transfers, background notifications, and single & multi-file bundle upload support.

[![pub package](https://img.shields.io/badge/pub-v0.1.0-blue.svg)](https://pub.dev)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-v3.10+-teal.svg)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-purple.svg)](https://flutter.dev)

---

## 1. What problem does it solve?

Normally when building file uploads in mobile apps (videos, camera photos, large documents):

1. User selects a 200 MB video or a batch of photos.
2. Upload starts and reaches 65%.
3. Internet disconnects or cell reception drops.
4. Upload crashes with an unhandled network socket error.
5. User is forced to manually restart from 0%.
6. If the user exits or the OS terminates the app, all pending uploads are permanently lost.

**With `smart_upload_manager`:**
- 🛡️ **Survives App Restarts & Kills:** Upload tasks are persisted atomically to disk.
- 📡 **Survives Network Drops:** Uploads automatically pause when offline and seamlessly resume as soon as internet connectivity returns.
- 📦 **Single & Multi-File Bundles:** Upload 1 file or bundle multiple files together in a single multipart HTTP request (`uploadMultiple`).
- ⚡ **Resumable Chunk Transfers:** Compatible with byte ranges (`Content-Range`), **Tus.io** protocol, and **Amazon S3 Multipart** uploads.
- 🔔 **Ongoing Status Bar Notifications:** Live progress bar, upload speed (MB/s), and ETA right in the system notification drawer.
- 🔄 **Automatic Exponential Retries:** Smart backoff with randomized jitter prevents server hammering.
- 🎛️ **Priority Queue & Concurrency:** High-priority items upload first, with configurable worker slots (e.g. 2–3 active concurrent uploads).
- 🧩 **Ready-to-Use UI Widgets:** Drop in `UploadTaskTile` and `UploadProgressBar` without writing `StreamBuilder` boilerplate.

---

## 2. Architecture & Flow

```mermaid
graph TD
    A[User Selects File(s)] --> B[Enqueue Task: Single or Multi-File]
    B --> C[Atomic Disk Persistence]
    C --> D{Connectivity Monitor}
    D -- Online --> E[Upload Manager Queue]
    D -- Offline --> F[Auto-Pause & Await Reconnect]
    F -- Reconnected --> E
    E --> G[Upload Adapters]
    G --> H[Standard Multipart / Form-Data]
    G --> I[Resumable Byte-Range Chunks]
    G --> J[Tus.io Open Protocol]
    G --> K[AWS S3 Multipart]
    G --> L[Simulated Mock Transfer]
    E --> M[System Notification Bar - Progress & Speed]
    E --> N[UI Streams: Progress, Status, QueueSummary]
    E -- Success --> O[HTTP 200/201 -> Mark Completed]
    E -- Transient Error --> P[Exponential Backoff + Jitter Retry]
    P --> E
```

---

## 3. Platform Setup & Requirements

### Android Setup

1. **Add Permissions** in `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required for network requests -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <!-- Required for background progress notifications (Android 13+ / API 33+) -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    
    <!-- Optional: required if using foreground service notifications -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />

    <application ...>
        ...
    </application>
</manifest>
```

2. **Android 13+ Runtime Permission**:
Call `requestNotificationPermission()` when appropriate (e.g., on app start or before the first upload):

```dart
final granted = await SmartUploadManager.instance.requestNotificationPermission();
```

---

### iOS Setup

1. **Configure Notification Delegate in `ios/Runner/AppDelegate.swift`**:
To ensure upload progress notifications display properly when the app is in the foreground or background, set the `UNUserNotificationCenter` delegate inside `application(_:didFinishLaunchingWithOptions:)`:

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for iOS local notification presentation
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

*(If using Objective-C `AppDelegate.m`)*:
```objc
if (@available(iOS 10.0, *)) {
  [UNUserNotificationCenter currentNotificationCenter].delegate = (id<UNUserNotificationCenterDelegate>) self;
}
```

2. **Minimum Deployment Target**: iOS 13.0 or 14.0+.
Ensure your `ios/Podfile` specifies `platform :ios, '14.0'` (or `'13.0'`):

```ruby
platform :ios, '14.0'
```

And in the `post_install` block of `ios/Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
```

3. **Swift Version**: Swift 5.0+ (standard in all modern Flutter projects).

4. **Photo & File Access in `ios/Runner/Info.plist`**:
If you are picking files from the gallery or documents directory, add the required usage descriptions:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Allow access to select photos and videos for upload.</string>
<key>NSDocumentPickerUsageDescription</key>
<string>Allow access to upload selected documents.</string>
```

---

## 4. Step-by-Step Usage Guide

### Step 1: Install the Dependency

Add to your `pubspec.yaml`:

```yaml
dependencies:
  smart_upload_manager: ^0.1.0
```

Run:

```bash
flutter pub get
```

---

### Step 2: Initialize the Queue in `main()`

Initialize the singleton queue with notification settings and concurrency limits:

```dart
import 'package:flutter/material.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SmartUploadManager.initialize(
    maxConcurrentUploads: 2, // Maximum simultaneous uploads
    retryPolicy: const RetryPolicy(maxRetries: 3), // Exponential retry with jitter
    notificationConfig: const NotificationConfig(
      enabled: true,
      channelId: 'smart_upload_channel',
      channelName: 'File Uploads',
      channelDescription: 'Ongoing file upload progress and speed',
    ),
  );

  runApp(const MyApp());
}
```

> **Note on Disabling Notifications:**
> If you don't need system notifications (or want in-app UI only), simply pass:
> `notificationConfig: const NotificationConfig(enabled: false)`.

---

### Step 3: Upload a Single File

Use `SmartUploadManager.upload(...)` to upload a file in a single line:

```dart
import 'dart:io';
import 'package:smart_upload_manager/smart_upload_manager.dart';

final file = File('/path/to/my_video.mp4');

final task = await SmartUploadManager.upload(
  file: file, // Accepts File object or String path
  url: 'https://api.example.com/upload/single',
  fileFieldName: 'file', // Multipart form field name (default: 'file')
  headers: {
    'Authorization': 'Bearer YOUR_AUTH_TOKEN',
  },
  data: {
    'folder': 'user_uploads',
  },
  onProgress: (progress, speed, eta) {
    print('Progress: ${(progress * 100).toInt()}% • Speed: $speed • ETA: $eta');
  },
  onSuccess: (completedTask) {
    print('Upload succeeded! Server response: ${completedTask.response}');
  },
  onError: (failedTask, error) {
    print('Upload failed: $error');
  },
);
```

Or call the extension method directly on any `File`:

```dart
await file.upload(url: 'https://api.example.com/upload');
```

---

### Step 4: Upload Multiple Files in ONE Request (`uploadMultiple`)

When your API expects multiple files bundled together in a single multipart HTTP request (e.g., `POST /upload/multiple` with multiple `files` form entries):

```dart
final task = await SmartUploadManager.uploadMultiple(
  files: [
    '/storage/photos/img_1.png',
    '/storage/photos/img_2.png',
    '/storage/photos/img_3.png',
  ], // Accepts List<File> or List<String>
  url: 'https://api.example.com/upload/multiple',
  fileFieldName: 'files', // Multipart form field name (default: 'files')
  headers: {
    'Authorization': 'Bearer YOUR_AUTH_TOKEN',
  },
  onProgress: (progress, speed, eta) {
    print('Total bundle progress: ${(progress * 100).toInt()}%');
  },
  onSuccess: (completedTask) {
    print('All files uploaded together in 1 request! Response: ${completedTask.response}');
  },
  onError: (failedTask, error) {
    print('Multi-upload failed: $error');
  },
);
```

> **Smart Content-Type Detection:**
> `smart_upload_manager` automatically resolves exact MIME types (`image/png`, `image/jpeg`, `application/pdf`, etc.) for every file in the bundle, preventing backend `415 Unsupported Media Type` errors.

---

### Step 5: Ready-to-Use UI Widgets

No need to write tedious `StreamBuilder` code:

```dart
import 'package:smart_upload_manager/smart_upload_manager.dart';

// Pre-built task tile with file icon, animated linear progress bar, speed, ETA, and pause/resume/cancel controls
UploadTaskTile(
  task: task,
  onDismiss: () => SmartUploadManager.instance.deleteTask(task.id),
)

// Standalone auto-updating progress bar
UploadProgressBar(taskId: task.id)
```

---

### Step 6: Queue Management & Global Controls

Monitor queue summary state and control all tasks with one tap:

```dart
// Stream real-time queue snapshot (Active, Pending, Paused, Completed)
StreamBuilder<QueueSummary>(
  stream: SmartUploadManager.instance.queueSummaryStream,
  builder: (context, snapshot) {
    final summary = snapshot.data ?? SmartUploadManager.instance.summary;
    return Text(
      'Active: ${summary.activeTasks} • Pending: ${summary.enqueuedTasks} • Completed: ${summary.completedTasks}',
    );
  },
);

// Global control actions:
SmartUploadManager.instance.pauseAll();     // Pause all ongoing uploads
SmartUploadManager.instance.resumeAll();    // Resume all paused uploads
SmartUploadManager.instance.cancelAll();    // Cancel all active & pending tasks
SmartUploadManager.instance.clearCompleted(); // Purge finished tasks from storage
```

---

### Step 7: Offline & Testing Mode (Simulated Upload)

Test progress bars, upload speed calculations, network drop recovery, and system notifications without needing a real server:

```dart
final task = await SmartUploadManager.upload(
  file: localFile,
  url: 'https://api.example.com/demo',
  protocol: UploadProtocol.simulated,
  simulatedFileSize: 60 * 1024 * 1024, // Simulates a 60 MB file transfer
);
```

---

## 5. Protocols & Resumable Adapters

Choose the transport protocol via the `protocol` parameter:

| Protocol | Enum | Best For |
| :--- | :--- | :--- |
| **Standard Multipart** | `UploadProtocol.standard` | Standard REST APIs (`multipart/form-data` or binary `POST`/`PUT`). |
| **Resumable Chunks** | `UploadProtocol.resumable` | Custom servers supporting byte ranges (`Content-Range: bytes 0-1048575/total`). |
| **Tus.io Protocol** | `UploadProtocol.tus` | Open [tus.io](https://tus.io) servers (Vimeo, Cloudflare, tusd). |
| **AWS S3 Multipart** | `UploadProtocol.s3Multipart` | Direct AWS S3 chunked uploads using Initiate, UploadPart, and CompleteMultipartUpload. |
| **Simulated** | `UploadProtocol.simulated` | Offline demos, automated tests, and UI verification. |

### Dynamic Auth Token Refresh

To avoid uploads failing when JWT tokens expire during long uploads:

```dart
await SmartUploadManager.initialize(
  headerProvider: (UploadTask task) async {
    final freshToken = await myAuthService.getValidToken();
    return {'Authorization': 'Bearer $freshToken'};
  },
);
```

---

## 6. Background Uploads & Lifecycle

| App State | Package Behavior |
| :--- | :--- |
| **Foreground** | Uploads with real-time UI streams and notifications. |
| **Minimized** | Uploads continue with ongoing system notification progress in status bar. |
| **Internet Lost** | Uploads automatically pause; state and confirmed byte offsets are preserved. |
| **Reconnected** | Automatically resumes uploads without starting over from 0%. |
| **App Terminated / Killed** | Queue state is safely preserved on disk in atomic storage. |
| **App Reopened** | Queue reloads all tasks and resumes pending uploads automatically. |

---

## 7. Interactive Example App

The `example/` folder contains a complete runnable app showcasing:
- Picking single files & multi-file bundles.
- Configurable upload endpoint (defaults to `https://httpbin.org/post`).
- Simulated 50 MB upload mode to test speed and notification bar without a server.
- Live queue dashboard with Active, Pending, Paused, and Completed counters.
- Pause All, Resume All, and Clear All controls.
- Auto-updating `UploadTaskTile` list with cancellation and dismissals.

To run:

```bash
cd example
flutter run
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
