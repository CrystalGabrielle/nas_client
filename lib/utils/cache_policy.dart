const defaultCacheBudget = 512 * 1024 * 1024;
const defaultCacheAge = Duration(days: 3);

class CacheEntry {
  const CacheEntry({
    required this.id,
    required this.bytes,
    required this.modified,
  });

  final String id;
  final int bytes;
  final DateTime modified;
}

/// Oldest files past [maxAge] are removed first. If the rest still exceed
/// [maxBytes], the oldest remaining files are removed until the budget fits.
List<String> cacheVictims(
  List<CacheEntry> entries, {
  required DateTime now,
  int maxBytes = defaultCacheBudget,
  Duration maxAge = defaultCacheAge,
}) {
  final sorted = [...entries]..sort((a, b) => a.modified.compareTo(b.modified));
  var total = 0;
  for (final entry in sorted) {
    total += entry.bytes;
  }
  final victims = <String>[];
  for (final entry in sorted) {
    final aged = now.difference(entry.modified) > maxAge;
    if (!aged && total <= maxBytes) continue;
    victims.add(entry.id);
    total -= entry.bytes;
  }
  return victims;
}
