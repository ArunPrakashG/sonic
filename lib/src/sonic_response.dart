// ignore_for_file: public_member_api_docs, sort_constructors_first
part of 'sonic_base.dart';

@immutable
class SonicResponse<T> {
  const SonicResponse._({
    this.extra,
    this.headers,
    this.data,
    required this.statusCode,
    this.message,
    this.sonicError,
  });

  final Map<String, dynamic>? extra;
  final Map<String, List<String>>? headers;
  final T? data;
  final int statusCode;
  final String? message;
  final SonicError? sonicError;

  /// Specifies if the request is a success.
  ///
  /// status code >= 200 and status code <= 299
  bool get isSuccess => statusCode >= 200 && statusCode <= 299;

  /// Specifies if the response contains an error.
  bool get hasError => sonicError != null;

  /// Transforms this instance of [SonicResponse] to [Y] type with [callback]
  Y to<Y>(Y Function(SonicResponse<T> data) callback) {
    return callback(this);
  }

  /// An easier syntax than writting if conditions to return instances based on response.
  Y on<Y>(
    Y Function(T? data) onData,
    Y Function(SonicError? error) onError,
  ) {
    if (hasError || (!isSuccess && data == null)) {
      return onError(sonicError);
    }

    return onData(data);
  }

  @override
  bool operator ==(covariant SonicResponse<T> other) {
    if (identical(this, other)) {
      return true;
    }

    final mapEquals = const DeepCollectionEquality().equals;

    return mapEquals(other.extra, extra) &&
        mapEquals(other.headers, headers) &&
        other.data == data &&
        other.statusCode == statusCode &&
        other.message == message &&
        other.sonicError == sonicError;
  }

  @override
  int get hashCode {
    return extra.hashCode ^
        headers.hashCode ^
        data.hashCode ^
        statusCode.hashCode ^
        message.hashCode ^
        sonicError.hashCode;
  }

  /// Build a new request builder for the next page using Link headers (if any).
  /// Requires providing a Sonic instance to construct the builder.
  SonicRequestBuilder<T>? nextPage(Sonic sonic,
      {HttpMethod method = HttpMethod.get}) {
    final h = headers;
    if (h == null) {
      return null;
    }
    final links = parseLinkHeaderFromMap(h);
    final next = links['next'];
    if (next == null) {
      return null;
    }
    return sonic.create<T>(url: next, method: method);
  }

  /// Build a new request builder for the previous page using Link headers.
  SonicRequestBuilder<T>? prevPage(Sonic sonic,
      {HttpMethod method = HttpMethod.get}) {
    final h = headers;
    if (h == null) {
      return null;
    }
    final links = parseLinkHeaderFromMap(h);
    final prev = links['prev'];
    if (prev == null) {
      return null;
    }
    return sonic.create<T>(url: prev, method: method);
  }

  /// Cursor helpers for common JSON body styles.
  /// Provide the cursor path (e.g., 'meta.nextCursor') and the query param name (e.g., 'cursor').
  SonicRequestBuilder<T>? nextCursor(
    Sonic sonic, {
    required String cursorPath,
    String param = 'cursor',
    HttpMethod method = HttpMethod.get,
  }) {
    final baseUrl = extra?['requestUrl'] as String?;
    final body = data;
    if (baseUrl == null || body == null) {
      return null;
    }
    final cursor = pluckValue(body, cursorPath);
    if (cursor == null) {
      return null;
    }
    final url = addOrReplaceQueryParam(baseUrl, param, cursor.toString());
    return sonic.create<T>(url: url, method: method);
  }

  SonicRequestBuilder<T>? prevCursor(
    Sonic sonic, {
    required String cursorPath,
    String param = 'cursor',
    HttpMethod method = HttpMethod.get,
  }) {
    final baseUrl = extra?['requestUrl'] as String?;
    final body = data;
    if (baseUrl == null || body == null) {
      return null;
    }
    final cursor = pluckValue(body, cursorPath);
    if (cursor == null) {
      return null;
    }
    final url = addOrReplaceQueryParam(baseUrl, param, cursor.toString());
    return sonic.create<T>(url: url, method: method);
  }

  /// Build a Paged<T> from this response's body/headers using a simple item decoder.
  ///
  /// Provide:
  /// - itemDecoder: converts a single item JSON to T
  /// - itemsPath: where list of items live in the body (defaults to root)
  /// - nextCursorPath/prevCursorPath: optional paths to cursors in body
  /// - cursorParam: the name of the query param to use when building cursor URLs
  Paged<T> toPaged({
    required T Function(dynamic json) itemDecoder,
    String? itemsPath,
    String? nextCursorPath,
    String? prevCursorPath,
    String cursorParam = 'cursor',
  }) {
    return makePaged<T>(
      body: data,
      headers: headers,
      requestUrl: extra?['requestUrl'] as String?,
      itemDecoder: itemDecoder,
      itemsPath: itemsPath,
      nextCursorPath: nextCursorPath,
      prevCursorPath: prevCursorPath,
      cursorParam: cursorParam,
    );
  }
}
