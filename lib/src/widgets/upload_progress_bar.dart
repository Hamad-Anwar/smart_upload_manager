import 'package:flutter/material.dart';
import '../../smart_upload_manager.dart';

/// A plug-and-play progress bar widget that automatically listens to an [UploadTask]'s progress.
class UploadProgressBar extends StatelessWidget {
  /// The ID of the task to track.
  final String taskId;

  /// Height of the progress bar.
  final double height;

  /// Custom active color. Defaults to theme's primary color.
  final Color? color;

  /// Custom track background color.
  final Color? backgroundColor;

  /// Whether to show speed and ETA text below the progress bar.
  final bool showMetrics;

  const UploadProgressBar({
    super.key,
    required this.taskId,
    this.height = 6.0,
    this.color,
    this.backgroundColor,
    this.showMetrics = true,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UploadTask>(
      stream: SmartUploadManager.instance.watch(taskId),
      builder: (context, snapshot) {
        final task =
            snapshot.data ?? SmartUploadManager.instance.getTask(taskId);
        if (task == null) {
          return const SizedBox.shrink();
        }

        final activeColor = color ?? Theme.of(context).colorScheme.primary;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: height,
                valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                backgroundColor:
                    backgroundColor ?? Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            if (showMetrics && task.status == UploadStatus.running) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${task.progressPercent}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (task.speed > 0)
                    Text(
                      '${task.formattedSpeed} • ETA ${task.formattedEta}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
