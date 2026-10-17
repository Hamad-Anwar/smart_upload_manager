import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize SmartUploadManager with background progress notifications.
  await SmartUploadManager.initialize(
    maxConcurrentUploads: 2,
    retryPolicy: const RetryPolicy(maxRetries: 3),
    notificationConfig: const NotificationConfig(
      enabled: true,
      channelId: 'smart_upload_channel',
      channelName: 'File Upload Progress',
    ),
  );

  runApp(const SmartUploadApp());
}

class SmartUploadApp extends StatelessWidget {
  const SmartUploadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Upload Manager Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const UploadDemoScreen(),
    );
  }
}

/// Backwards compatibility alias
typedef ReliableUploadApp = SmartUploadApp;

class UploadDemoScreen extends StatefulWidget {
  const UploadDemoScreen({super.key});

  @override
  State<UploadDemoScreen> createState() => _UploadDemoScreenState();
}

class _UploadDemoScreenState extends State<UploadDemoScreen> {
  // Configurable upload URL (defaults to httpbin.org which echoes back multipart form-data)
  final TextEditingController _urlController = TextEditingController(
    text: 'https://httpbin.org/post',
  );

  UploadTask? _latestTask;
  bool _isPicking = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Flow 1: Upload a single file using [SmartUploadManager.upload]
  Future<void> _pickAndUploadSingle() async {
    setState(() => _isPicking = true);

    try {
      final picked = await FilePicker.pickFile();
      if (picked == null || picked.path == null) {
        setState(() => _isPicking = false);
        return;
      }

      final file = File(picked.path!);

      final task = await SmartUploadManager.upload(
        file: file,
        url: _urlController.text.trim(),
        protocol: UploadProtocol.standard,
        fileFieldName: 'file',
        onProgress: (progress, speed, eta) {
          if (mounted) setState(() {});
        },
        onSuccess: (completedTask) {
          if (mounted) {
            setState(() => _latestTask = completedTask);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File uploaded successfully!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onError: (failedTask, error) {
          if (mounted) {
            setState(() => _latestTask = failedTask);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Upload failed: $error'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      );

      setState(() {
        _latestTask = task;
        _isPicking = false;
      });
    } catch (e) {
      setState(() => _isPicking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Flow 2: Upload multiple files in ONE multipart HTTP request using [SmartUploadManager.uploadMultiple]
  Future<void> _pickAndUploadMultiple() async {
    setState(() => _isPicking = true);

    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) {
        setState(() => _isPicking = false);
        return;
      }

      final validPaths = files
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();

      if (validPaths.isEmpty) {
        setState(() => _isPicking = false);
        return;
      }

      final task = await SmartUploadManager.uploadMultiple(
        files: validPaths,
        url: _urlController.text.trim(),
        fileFieldName: 'files',
        onProgress: (progress, speed, eta) {
          if (mounted) setState(() {});
        },
        onSuccess: (completedTask) {
          if (mounted) {
            setState(() => _latestTask = completedTask);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${validPaths.length} files uploaded together in one request!',
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onError: (failedTask, error) {
          if (mounted) {
            setState(() => _latestTask = failedTask);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Upload failed: $error'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      );

      setState(() {
        _latestTask = task;
        _isPicking = false;
      });
    } catch (e) {
      setState(() => _isPicking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Flow 3: Start a simulated 50 MB upload to test live progress, speed & notification drawer offline
  Future<void> _startSimulatedUpload() async {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/simulated_demo_video.mp4');
    if (!await file.exists()) {
      await file.writeAsBytes(List.filled(1024, 0));
    }

    final task = await SmartUploadManager.upload(
      file: file,
      url: 'https://api.example.com/uploads/video.mp4',
      protocol: UploadProtocol.simulated,
      simulatedFileSize: 50 * 1024 * 1024, // 50 MB
      onProgress: (progress, speed, eta) {
        if (mounted) setState(() {});
      },
    );

    setState(() => _latestTask = task);
  }

  /// Test notification bar dispatching
  Future<void> _sendTestNotification() async {
    try {
      final granted =
          await SmartUploadManager.instance.requestNotificationPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification permission denied by user.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await SmartUploadManager.instance.sendTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test notification dispatched to drawer!'),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Upload Manager'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Target URL Input Field
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Target Upload URL',
                      hintText: 'https://httpbin.org/post or your backend API',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.link, size: 20),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Upload Action Buttons
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: _isPicking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file, size: 20),
                    label: const Text('Pick 1 File'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _isPicking ? null : _pickAndUploadSingle,
                  ),
                  FilledButton.icon(
                    icon: _isPicking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.file_copy_outlined, size: 20),
                    label: const Text('Pick Multi Files (1 Request)'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _isPicking ? null : _pickAndUploadMultiple,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Testing Helpers
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.speed, size: 16),
                    label: const Text('Simulate 50 MB (No Server Needed)'),
                    onPressed: _startSimulatedUpload,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 16,
                    ),
                    label: const Text('Test Notification Bar'),
                    onPressed: _sendTestNotification,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Queue Summary Dashboard
              StreamBuilder<QueueSummary>(
                stream: SmartUploadManager.instance.queueSummaryStream,
                initialData: SmartUploadManager.instance.summary,
                builder: (context, snapshot) {
                  final summary =
                      snapshot.data ?? SmartUploadManager.instance.summary;
                  if (summary.totalTasks == 0 && summary.completedTasks == 0) {
                    return const SizedBox.shrink();
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryItem(
                              'Active',
                              '${summary.activeTasks}',
                              Colors.blue,
                            ),
                            _buildSummaryItem(
                              'Pending',
                              '${summary.enqueuedTasks}',
                              Colors.orange,
                            ),
                            _buildSummaryItem(
                              'Paused',
                              '${summary.pausedTasks}',
                              Colors.amber,
                            ),
                            _buildSummaryItem(
                              'Completed',
                              '${summary.completedTasks}',
                              Colors.green,
                            ),
                          ],
                        ),
                        if (summary.totalActiveAndPending > 0 ||
                            summary.hasPaused ||
                            summary.completedTasks > 0) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              if (summary.isUploading)
                                TextButton.icon(
                                  icon: const Icon(Icons.pause, size: 16),
                                  label: const Text('Pause All'),
                                  onPressed: () =>
                                      SmartUploadManager.instance.pauseAll(),
                                ),
                              if (summary.hasPaused)
                                TextButton.icon(
                                  icon: const Icon(Icons.play_arrow, size: 16),
                                  label: const Text('Resume All'),
                                  onPressed: () =>
                                      SmartUploadManager.instance.resumeAll(),
                                ),
                              TextButton.icon(
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 16,
                                ),
                                label: const Text('Clear All'),
                                onPressed: () async {
                                  await SmartUploadManager.instance
                                      .cancelAll();
                                  await SmartUploadManager.instance
                                      .clearCompleted();
                                  setState(() => _latestTask = null);
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              // Active & Pending Tasks List using pre-built UploadTaskTile
              StreamBuilder<QueueSummary>(
                stream: SmartUploadManager.instance.queueSummaryStream,
                initialData: SmartUploadManager.instance.summary,
                builder: (context, _) {
                  final tasks = SmartUploadManager.instance.allTasks;
                  if (tasks.isEmpty) return const SizedBox.shrink();

                  final displayTasks = tasks.take(5).toList();

                  return Column(
                    children: [
                      for (final task in displayTasks)
                        UploadTaskTile(
                          key: ValueKey(task.id),
                          task: task,
                          onDismiss: () async {
                            await SmartUploadManager.instance.deleteTask(
                              task.id,
                            );
                            if (_latestTask?.id == task.id) {
                              setState(() => _latestTask = null);
                            }
                          },
                        ),
                    ],
                  );
                },
              ),

              // Response Preview Card
              if (_latestTask != null) ...[
                const SizedBox(height: 16),
                StreamBuilder<UploadTask>(
                  stream: SmartUploadManager.instance.watch(_latestTask!.id),
                  initialData: _latestTask,
                  builder: (context, snapshot) {
                    final current = snapshot.data ?? _latestTask!;

                    if (current.status == UploadStatus.completed) {
                      return _buildCompletedCard(current);
                    } else if (current.status == UploadStatus.failed) {
                      return _buildFailedCard(current);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCompletedCard(UploadTask task) {
    String responseText = '';
    if (task.response != null) {
      if (task.response is Map || task.response is List) {
        try {
          responseText =
              const JsonEncoder.withIndent('  ').convert(task.response);
        } catch (_) {
          responseText = task.response.toString();
        }
      } else {
        responseText = task.response.toString();
      }
    }

    return Card(
      elevation: 0,
      color: Colors.green.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.isMultiFile
                        ? 'All ${task.filePaths.length} files uploaded in 1 request!'
                        : 'Upload completed successfully!',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            if (responseText.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Server Response:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  responseText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFailedCard(UploadTask task) {
    return Card(
      elevation: 0,
      color: Colors.red.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.error ?? 'Upload failed',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
