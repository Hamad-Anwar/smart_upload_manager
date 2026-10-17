import 'package:flutter/material.dart';
import '../../smart_upload_manager.dart';

/// A drop-in ListTile widget that renders an upload task with real-time progress and controls.
class UploadTaskTile extends StatelessWidget {
  /// The upload task to display.
  final UploadTask task;

  /// Whether to show the pause/resume/cancel action buttons.
  final bool showControls;

  /// Callback when user taps to delete or cancel.
  final VoidCallback? onDismiss;

  const UploadTaskTile({
    super.key,
    required this.task,
    this.showControls = true,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UploadTask>(
      stream: SmartUploadManager.instance.watch(task.id),
      initialData: task,
      builder: (context, snapshot) {
        final current = snapshot.data ?? task;
        final statusColor = _getStatusColor(current.status);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getFileIcon(current),
                      color: statusColor,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${current.formattedTotalSize} • ${current.status.displayName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showControls) ...[
                      if (current.status == UploadStatus.running)
                        IconButton(
                          icon: const Icon(Icons.pause, size: 20),
                          tooltip: 'Pause',
                          onPressed: () =>
                              SmartUploadManager.instance.pause(current.id),
                        ),
                      if (current.status == UploadStatus.paused)
                        IconButton(
                          icon: const Icon(Icons.play_arrow, size: 20),
                          tooltip: 'Resume',
                          onPressed: () =>
                              SmartUploadManager.instance.resume(current.id),
                        ),
                      if (current.status == UploadStatus.failed)
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Retry',
                          onPressed: () =>
                              SmartUploadManager.instance.retry(current.id),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Cancel',
                        onPressed:
                            onDismiss ??
                            () => SmartUploadManager.instance.deleteTask(
                              current.id,
                            ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: current.progress,
                  minHeight: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                ),
                if (current.status == UploadStatus.running &&
                    current.speed > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${current.progressPercent}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        '${current.formattedSpeed} • ETA: ${current.formattedEta}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.running:
        return Colors.blue;
      case UploadStatus.enqueued:
        return Colors.indigo;
      case UploadStatus.paused:
        return Colors.amber;
      case UploadStatus.completed:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
      case UploadStatus.cancelled:
        return Colors.grey;
    }
  }

  IconData _getFileIcon(UploadTask task) {
    if (task.isMultiFile) {
      return Icons.collections_bookmark_outlined;
    }
    final lower = task.fileName.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) {
      return Icons.movie_outlined;
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
