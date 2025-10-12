import 'package:dio/dio.dart';

typedef PageDecoder<T> = T Function(dynamic json);

class Paged<T> {
  Paged({
    required this.items,
    this.next,
    this.prev,
  });

  final List<T> items;
  final SonicPageRef<T>? next;
  final SonicPageRef<T>? prev;
}

class SonicPageRef<T> {
  SonicPageRef({
    required this.url,
    required this.decoder,
  });

  final String url;
  final PageDecoder<List<T>> decoder;
}

/// Parse HTTP Link header for rel="next"/"prev" URLs.
Map<String, String> parseLinkHeader(Headers headers) {
  final link = headers.value('link');
  if (link == null) {
    return const {};
  }
  final parts = link.split(',');
  final map = <String, String>{};
  for (final p in parts) {
    final m = RegExp(r'<([^>]+)>;\s*rel="([^"]+)"').firstMatch(p.trim());
    if (m != null) {
      map[m.group(2)!] = m.group(1)!;
    }
  }
  return map;
}

Map<String, String> parseLinkHeaderFromMap(Map<String, List<String>> headers) {
  final link = headers['link']?.first;
  if (link == null) {
    return const {};
  }
  final parts = link.split(',');
  final map = <String, String>{};
  for (final p in parts) {
    final m = RegExp(r'<([^>]+)>;\s*rel="([^"]+)"').firstMatch(p.trim());
    if (m != null) {
      map[m.group(2)!] = m.group(1)!;
    }
  }
  return map;
}

/// Lightweight JSON plucker: supports dot paths and `[index]` for lists.
dynamic pluckValue(dynamic data, String path) {
  if (path.isEmpty) {
    return data;
  }
  final segments = path.split('.').where((e) => e.trim().isNotEmpty);
  dynamic current = data;
  for (final seg in segments) {
    // Parse "key" or "key[index]"
    var key = seg;
    int? idx;
    final lb = seg.indexOf('[');
    if (lb != -1 && seg.endsWith(']')) {
      key = seg.substring(0, lb);
      final idxStr = seg.substring(lb + 1, seg.length - 1);
      idx = int.tryParse(idxStr);
      if (idx == null) {
        return null;
      }
    }
    if (key.isNotEmpty) {
      if (current is Map) {
        current = current[key];
      } else {
        return null;
      }
    }
    if (idx != null) {
      if (current is List && idx >= 0 && idx < current.length) {
        current = current[idx];
      } else {
        return null;
      }
    }
  }
  return current;
}

String addOrReplaceQueryParam(String url, String key, String value) {
  final u = Uri.parse(url);
  final qp = Map<String, String>.from(u.queryParameters);
  qp[key] = value;
  return u.replace(queryParameters: qp).toString();
}

/// Build a Paged<T> from common response shapes.
/// - If itemsPath is provided, items are plucked from the body at that path.
/// - For next/prev: prefer cursor paths if provided; otherwise look for RFC Link headers.
/// - cursorParam controls the query key used when constructing URLs from cursors.
Paged<T> makePaged<T>({
  required dynamic body,
  required Map<String, List<String>>? headers,
  required String? requestUrl,
  required T Function(dynamic json) itemDecoder,
  String? itemsPath,
  String? nextCursorPath,
  String? prevCursorPath,
  String cursorParam = 'cursor',
}) {
  final listNode = itemsPath != null ? pluckValue(body, itemsPath) : body;
  final rawList = (listNode is List) ? listNode : const [];
  final items = <T>[];
  for (final e in rawList) {
    items.add(itemDecoder(e));
  }

  String? nextUrl;
  String? prevUrl;
  if (nextCursorPath != null && requestUrl != null) {
    final c = pluckValue(body, nextCursorPath);
    if (c != null) {
      nextUrl = addOrReplaceQueryParam(requestUrl, cursorParam, c.toString());
    }
  }
  if (prevCursorPath != null && requestUrl != null) {
    final c = pluckValue(body, prevCursorPath);
    if (c != null) {
      prevUrl = addOrReplaceQueryParam(requestUrl, cursorParam, c.toString());
    }
  }

  if (headers != null) {
    final links = parseLinkHeaderFromMap(headers);
    nextUrl ??= links['next'];
    prevUrl ??= links['prev'];
  }

  List<T> listDecoder(dynamic json) {
    final node = itemsPath != null ? pluckValue(json, itemsPath) : json;
    final list = (node is List) ? node : const [];
    return list.map<T>((e) => itemDecoder(e)).toList();
  }

  return Paged<T>(
    items: items,
    next: nextUrl != null
        ? SonicPageRef<T>(url: nextUrl, decoder: listDecoder)
        : null,
    prev: prevUrl != null
        ? SonicPageRef<T>(url: prevUrl, decoder: listDecoder)
        : null,
  );
}

String advanceOffsetLimit({
  required String url,
  required int pageSize,
  String offsetKey = 'offset',
  String limitKey = 'limit',
  bool next = true,
}) {
  final u = Uri.parse(url);
  final qp = Map<String, String>.from(u.queryParameters);
  final currentOffset = int.tryParse(qp[offsetKey] ?? '0') ?? 0;
  final limit = int.tryParse(qp[limitKey] ?? '$pageSize') ?? pageSize;
  final newOffset =
      next ? currentOffset + limit : (currentOffset - limit).clamp(0, 1 << 31);
  qp[offsetKey] = newOffset.toString();
  qp[limitKey] = limit.toString();
  return u.replace(queryParameters: qp).toString();
}

String advancePageNumber({
  required String url,
  String pageKey = 'page',
  bool next = true,
}) {
  final u = Uri.parse(url);
  final qp = Map<String, String>.from(u.queryParameters);
  final current = int.tryParse(qp[pageKey] ?? '1') ?? 1;
  final newPage = next ? current + 1 : (current - 1 <= 0 ? 1 : current - 1);
  qp[pageKey] = newPage.toString();
  return u.replace(queryParameters: qp).toString();
}
