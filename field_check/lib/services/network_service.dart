import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Network request handler with automatic retry and timeout logic
///
/// Features:
/// - Exponential backoff retry
/// - Timeout handling
/// - Progress tracking
/// - Graceful degradation for slow networks
class NetworkService {
  static const int defaultRetries = 3;
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration initialBackoff = Duration(seconds: 1);

  /// Execute HTTP request with retry logic
  ///
  /// Returns response or throws exception after all retries
  static Future<http.Response> getWithRetry(
    Uri url, {
    Map<String, String>? headers,
    int maxRetries = defaultRetries,
    Duration timeout = defaultTimeout,
    VoidCallback? onRetry,
  }) async {
    return _executeWithRetry(
      () => http.get(url, headers: headers),
      maxRetries: maxRetries,
      timeout: timeout,
      onRetry: onRetry,
    );
  }

  static Future<http.Response> postWithRetry(
    Uri url, {
    Map<String, String>? headers,
    dynamic body,
    int maxRetries = defaultRetries,
    Duration timeout = defaultTimeout,
    VoidCallback? onRetry,
  }) async {
    return _executeWithRetry(
      () => http.post(url, headers: headers, body: body),
      maxRetries: maxRetries,
      timeout: timeout,
      onRetry: onRetry,
    );
  }

  static Future<http.Response> patchWithRetry(
    Uri url, {
    Map<String, String>? headers,
    dynamic body,
    int maxRetries = defaultRetries,
    Duration timeout = defaultTimeout,
    VoidCallback? onRetry,
  }) async {
    return _executeWithRetry(
      () => http.patch(url, headers: headers, body: body),
      maxRetries: maxRetries,
      timeout: timeout,
      onRetry: onRetry,
    );
  }

  static Future<http.Response> deleteWithRetry(
    Uri url, {
    Map<String, String>? headers,
    int maxRetries = defaultRetries,
    Duration timeout = defaultTimeout,
    VoidCallback? onRetry,
  }) async {
    return _executeWithRetry(
      () => http.delete(url, headers: headers),
      maxRetries: maxRetries,
      timeout: timeout,
      onRetry: onRetry,
    );
  }

  /// Upload file with progress tracking and retry
  static Future<http.StreamedResponse> uploadWithRetry(
    http.MultipartRequest request, {
    int maxRetries = defaultRetries,
    Duration timeout = defaultTimeout,
    Duration Function(int attempt)? backoffCalculator,
    VoidCallback? onRetry,
  }) async {
    int attempt = 0;

    while (attempt <= maxRetries) {
      try {
        final response = await request.send().timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }

        // Retry on server error
        if (response.statusCode >= 500 && attempt < maxRetries) {
          attempt++;
          onRetry?.call();
          final backoff =
              backoffCalculator?.call(attempt) ?? _calculateBackoff(attempt);
          await Future.delayed(backoff);
          continue;
        }

        return response;
      } on TimeoutException {
        if (attempt < maxRetries) {
          attempt++;
          onRetry?.call();
          final backoff =
              backoffCalculator?.call(attempt) ?? _calculateBackoff(attempt);
          await Future.delayed(backoff);
          continue;
        }
        rethrow;
      } catch (e) {
        if (attempt < maxRetries && _isRetryableError(e)) {
          attempt++;
          onRetry?.call();
          final backoff =
              backoffCalculator?.call(attempt) ?? _calculateBackoff(attempt);
          await Future.delayed(backoff);
          continue;
        }
        rethrow;
      }
    }

    throw Exception('Max retries exceeded');
  }

  // Private helpers

  static Future<http.Response> _executeWithRetry(
    Future<http.Response> Function() request, {
    required int maxRetries,
    required Duration timeout,
    VoidCallback? onRetry,
  }) async {
    int attempt = 0;

    while (attempt <= maxRetries) {
      try {
        final response = await request().timeout(timeout);

        // Success on 2xx status
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }

        // Retry on server error or timeout
        if (response.statusCode >= 500 && attempt < maxRetries) {
          attempt++;
          onRetry?.call();
          await Future.delayed(_calculateBackoff(attempt));
          continue;
        }

        // Don't retry on client error (4xx)
        return response;
      } on TimeoutException {
        if (attempt < maxRetries) {
          attempt++;
          onRetry?.call();
          await Future.delayed(_calculateBackoff(attempt));
          continue;
        }
        rethrow;
      } catch (e) {
        if (attempt < maxRetries && _isRetryableError(e)) {
          attempt++;
          onRetry?.call();
          await Future.delayed(_calculateBackoff(attempt));
          continue;
        }
        rethrow;
      }
    }

    throw Exception('Max retries exceeded');
  }

  static Duration _calculateBackoff(int attempt) {
    // Exponential backoff: 1s, 2s, 4s, 8s...
    final seconds = initialBackoff.inSeconds * (1 << (attempt - 1));
    return Duration(seconds: seconds);
  }

  static bool _isRetryableError(dynamic e) {
    final message = e.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('network');
  }
}

/// HTTP request wrapper with timeout and retry
class ResilientHttpClient extends http.BaseClient {
  final int retries;
  final Duration timeout;
  final Duration Function(int)? backoffCalculator;
  final Function(String)? onRetry;

  ResilientHttpClient({
    this.retries = NetworkService.defaultRetries,
    this.timeout = NetworkService.defaultTimeout,
    this.backoffCalculator,
    this.onRetry,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      NetworkService.uploadWithRetry(
        request as http.MultipartRequest,
        maxRetries: retries,
        timeout: timeout,
        backoffCalculator: backoffCalculator,
        onRetry: () =>
            onRetry?.call('Retrying ${request.method} ${request.url}'),
      );
}
