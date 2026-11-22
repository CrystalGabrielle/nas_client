class ByteRange {
  const ByteRange(this.start, this.endInclusive);

  final int start;
  final int endInclusive;

  int get length => endInclusive - start + 1;
}

/// Parses an HTTP Range header against a known total size.
/// An empty header means the whole file. Returns null when the range cannot
/// be satisfied.
ByteRange? byteRangeFromHeader(String? header, int total) {
  if (total <= 0) return null;
  if (header == null || header.trim().isEmpty) {
    return ByteRange(0, total - 1);
  }
  final match = RegExp(
    r'^bytes=(\d*)-(\d*)$',
    caseSensitive: false,
  ).firstMatch(header.trim());
  if (match == null) return null;
  final startText = match.group(1)!;
  final endText = match.group(2)!;
  if (startText.isEmpty && endText.isEmpty) return null;
  if (startText.isEmpty) {
    final suffix = int.tryParse(endText);
    if (suffix == null || suffix <= 0) return null;
    final length = suffix > total ? total : suffix;
    return ByteRange(total - length, total - 1);
  }
  final start = int.tryParse(startText);
  if (start == null || start < 0 || start >= total) return null;
  final parsedEnd = endText.isEmpty ? total - 1 : int.tryParse(endText);
  if (parsedEnd == null) return null;
  final end = parsedEnd >= total ? total - 1 : parsedEnd;
  if (end < start) return null;
  return ByteRange(start, end);
}
