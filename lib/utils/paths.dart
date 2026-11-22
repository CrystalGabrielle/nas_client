String normalizeRemote(String path) {
  if (path.isEmpty || path == '/') return '/';
  var value = path.replaceAll('\\', '/').trim();
  if (value.isEmpty) return '/';
  if (!value.startsWith('/')) value = '/$value';
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

String joinRemote(String parent, String name) {
  final cleanName = name.trim();
  final base = normalizeRemote(parent);
  if (base == '/') return '/$cleanName';
  return '$base/$cleanName';
}

String parentRemote(String path) {
  final value = normalizeRemote(path);
  if (value == '/') return '/';
  final index = value.lastIndexOf('/');
  if (index <= 0) return '/';
  return value.substring(0, index);
}

String? validateEntryName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return '请输入名称';
  if (name == '.' || name == '..') return '这个名称不能使用';
  if (name.contains('/') || name.contains('\\')) return '名称里不能包含斜杠';
  if (RegExp(r'[*:?"<>|]').hasMatch(name)) return '名称不能包含 : * ? " < > |';
  return null;
}

class PathCrumb {
  const PathCrumb({required this.label, required this.path});

  final String label;
  final String path;
}

List<PathCrumb> breadcrumbs(String root, String path) {
  final normalizedRoot = normalizeRemote(root);
  final normalizedPath = normalizeRemote(path);
  final items = <PathCrumb>[PathCrumb(label: '根目录', path: normalizedRoot)];
  if (normalizedPath == normalizedRoot) return items;

  var relative = normalizedPath;
  if (normalizedRoot != '/' && normalizedPath.startsWith('$normalizedRoot/')) {
    relative = normalizedPath.substring(normalizedRoot.length);
  }

  var current = normalizedRoot == '/' ? '' : normalizedRoot;
  for (final part in relative.split('/')) {
    if (part.isEmpty) continue;
    current = current.isEmpty ? '/$part' : '$current/$part';
    items.add(PathCrumb(label: part, path: current));
  }
  return items;
}
