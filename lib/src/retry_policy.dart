import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';

/// Configuration and logic for retrying failed upload tasks.
class RetryPolicy {
  /// Maximum number of retry attempts before giving up.
  final int maxRetries;

  /// The initial backoff delay before the first retry.
  final Duration initialDelay;

  /// The ceiling delay between retry attempts.
  final Duration maxDelay;

  /// Exponential backoff multiplier factor (e.g. 2.0 doubles delay each step).
  final double multiplier;

  /// Whether to add randomized jitter (±20%) to prevent simultaneous retries.
  final bool useJitter;

  /// Optional custom predicate to determine if a specific error is retryable.
  final bool Function(dynamic error, int attemptCount)? customRetryPredicate;

  const RetryPolicy({
    this.maxRetries = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.multiplier = 2.0,
    this.useJitter = true,
    this.customRetryPredicate,
  });

  /// Computes the backoff duration for the given [attemptCount] (1-based).
  Duration calculateDelay(int attemptCount) {
    if (attemptCount <= 0) return initialDelay;

    final exponentialMillis =
        initialDelay.inMilliseconds * pow(multiplier, attemptCount - 1);
    var clampedMillis =
        min(exponentialMillis, maxDelay.inMilliseconds.toDouble());

    if (useJitter) {
      final random = Random();
      // Jitter factor between 0.8 and 1.2
      final jitterFactor = 0.8 + (random.nextDouble() * 0.4);
      clampedMillis = (clampedMillis * jitterFactor).clamp(
        initialDelay.inMilliseconds.toDouble(),
        maxDelay.inMilliseconds.toDouble(),
      );
    }

    return Duration(milliseconds: clampedMillis.round());
  }

  /// Evaluates whether an upload failure should be retried.
  bool shouldRetry(dynamic error, int attemptCount, {int? maxRetriesOverride}) {
    final effectiveMax = maxRetriesOverride ?? maxRetries;
    if (attemptCount >= effectiveMax) {
      return false;
    }

    if (customRetryPredicate != null) {
      return customRetryPredicate!(error, attemptCount);
    }

    // Default error inspection
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.transformTimeout:
          return true;

        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          if (statusCode == null) return true;

          // 5xx Server Errors, 408 Request Timeout, 429 Rate Limit
          if (statusCode >= 500 || statusCode == 408 || statusCode == 429) {
            return true;
          }
          // 4xx Client Errors are usually non-transient
          return false;

        case DioExceptionType.cancel:
          return false;

        case DioExceptionType.badCertificate:
        case DioExceptionType.unknown:
          if (error.error is SocketException || error.error is HttpException) {
            return true;
          }
          return false;
      }
    }

    if (error is SocketException || error is HttpException) {
      return true;
    }

    return false;
  }
}
