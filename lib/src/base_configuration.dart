import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

import 'constants.dart';

@immutable
class BaseConfiguration {
  const BaseConfiguration({
    required this.baseUrl,
    this.path,
    this.connectTimeout = MAX_CONNECT_TIMEOUT,
    this.receiveTimeout = MAX_RECEIVE_TIMEOUT,
    this.sendTimeout = MAX_SEND_TIMEOUT,
    this.defaultHeaders,
    this.defaultQueryParameters,
    this.extra,
    this.debugMode = false,
    this.allowConcurrency = true,
    this.followRedirects = true,
    this.maxRedirects = MAX_REDIRECTS,
  });

  factory BaseConfiguration.defaultConfig() {
    return const BaseConfiguration(baseUrl: '');
  }

  final String baseUrl;
  final String? path;
  final int connectTimeout;
  final int receiveTimeout;
  final int sendTimeout;
  final bool debugMode;
  final Map<String, dynamic>? defaultHeaders;
  final Map<String, dynamic>? defaultQueryParameters;
  final Map<String, dynamic>? extra;
  final bool followRedirects;
  final bool allowConcurrency;
  final int maxRedirects;

  String get _baseUrl => join(baseUrl, path);

  BaseOptions toDioBaseOptions() {
    return BaseOptions(
      baseUrl: _baseUrl,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      headers: defaultHeaders,
      queryParameters: defaultQueryParameters,
      extra: extra,
    );
  }

  BaseConfiguration copyWith({
    String? baseUrl,
    String? path,
    int? connectTimeout,
    int? receiveTimeout,
    int? sendTimeout,
    Map<String, dynamic>? defaultHeaders,
    Map<String, dynamic>? defaultQueryParameters,
    Map<String, dynamic>? extra,
    bool? followRedirects,
    int? maxRedirects,
  }) {
    return BaseConfiguration(
      baseUrl: baseUrl ?? this.baseUrl,
      path: path ?? this.path,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      defaultQueryParameters:
          defaultQueryParameters ?? this.defaultQueryParameters,
      extra: extra ?? this.extra,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
    );
  }

  @override
  bool operator ==(covariant BaseConfiguration other) {
    if (identical(this, other)) {
      return true;
    }

    final mapEquals = const DeepCollectionEquality().equals;

    return other.baseUrl == baseUrl &&
        other.path == path &&
        other.connectTimeout == connectTimeout &&
        other.receiveTimeout == receiveTimeout &&
        other.sendTimeout == sendTimeout &&
        other.debugMode == debugMode &&
        mapEquals(other.defaultHeaders, defaultHeaders) &&
        mapEquals(other.defaultQueryParameters, defaultQueryParameters) &&
        mapEquals(other.extra, extra) &&
        other.followRedirects == followRedirects &&
        other.maxRedirects == maxRedirects;
  }

  @override
  int get hashCode {
    return baseUrl.hashCode ^
        path.hashCode ^
        connectTimeout.hashCode ^
        receiveTimeout.hashCode ^
        sendTimeout.hashCode ^
        debugMode.hashCode ^
        defaultHeaders.hashCode ^
        defaultQueryParameters.hashCode ^
        extra.hashCode ^
        followRedirects.hashCode ^
        maxRedirects.hashCode;
  }
}
