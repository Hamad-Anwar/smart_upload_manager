/// Priority levels for upload tasks.
/// Tasks with higher priority will be dequeued and uploaded before lower priority tasks.
enum TaskPriority {
  /// Low priority - background sync or non-urgent uploads.
  low,

  /// Default normal priority for standard user uploads.
  normal,

  /// High priority uploads (e.g. active screen submission).
  high,

  /// Critical priority - immediately prioritized at the front of the queue.
  critical,
}

/// Extension for [TaskPriority] comparison and display.
extension TaskPriorityX on TaskPriority {
  /// Numeric value for comparison (higher = more urgent).
  int get value {
    switch (this) {
      case TaskPriority.low:
        return 0;
      case TaskPriority.normal:
        return 1;
      case TaskPriority.high:
        return 2;
      case TaskPriority.critical:
        return 3;
    }
  }

  /// Whether this priority is higher than [other].
  bool isHigherThan(TaskPriority other) => value > other.value;

  /// String display name.
  String get displayName {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.normal:
        return 'Normal';
      case TaskPriority.high:
        return 'High';
      case TaskPriority.critical:
        return 'Critical';
    }
  }
}
