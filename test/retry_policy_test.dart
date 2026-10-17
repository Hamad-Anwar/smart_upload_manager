import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_upload_manager/smart_upload_manager.dart';

void main() {
  group('RetryPolicy', () {
    test('computes exponential backoff within boundaries', () {
      const policy = RetryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
        multiplier: 2.0,
        useJitter: false, // disable jitter for deterministic math
      );

      expect(policy.calculateDelay(1), const Duration(seconds: 1));
      expect(policy.calculateDelay(2), const Duration(seconds: 2));
      expect(policy.calculateDelay(3), const Duration(seconds: 4));
      expect(policy.calculateDelay(4), const Duration(seconds: 8));
      expect(policy.calculateDelay(5), const Duration(seconds: 16));
      expect(policy.calculateDelay(6), const Duration(seconds: 30)); // clamped to max
    });

    test('retries transient 5xx server errors and socket drops', () {
      const policy = RetryPolicy(maxRetries: 3);

      final server500 = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(statusCode: 500, requestOptions: RequestOptions(path: '/')),
        type: DioExceptionType.badResponse,
      );

      final badGateway502 = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(statusCode: 502, requestOptions: RequestOptions(path: '/')),
        type: DioExceptionType.badResponse,
      );

      const socketException = SocketException('Connection reset by peer');

      expect(policy.shouldRetry(server500, 0), isTrue);
      expect(policy.shouldRetry(badGateway502, 1), isTrue);
      expect(policy.shouldRetry(socketException, 2), isTrue);
      expect(policy.shouldRetry(socketException, 3), isFalse); // exceeded maxRetries
    });

    test('does not retry 4xx fatal client errors', () {
      const policy = RetryPolicy(maxRetries: 3);

      final notFound404 = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(statusCode: 404, requestOptions: RequestOptions(path: '/')),
        type: DioExceptionType.badResponse,
      );

      final badRequest400 = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(statusCode: 400, requestOptions: RequestOptions(path: '/')),
        type: DioExceptionType.badResponse,
      );

      expect(policy.shouldRetry(notFound404, 0), isFalse);
      expect(policy.shouldRetry(badRequest400, 0), isFalse);
    });
  });
}
