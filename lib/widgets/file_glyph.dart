import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/local_files.dart';
import '../theme/app_theme.dart';

class FileGlyph extends StatelessWidget {
  const FileGlyph({super.key, required this.entry, this.size = 46});

  final RemoteEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final family = familyOf(entry);
    final colors = _colors(palette, family);
    final icon = switch (family) {
      FileFamily.folder =>
        entry.isShare ? Icons.inventory_2_rounded : Icons.folder_rounded,
      FileFamily.image => Icons.image_rounded,
      FileFamily.video => Icons.movie_rounded,
      FileFamily.audio => Icons.graphic_eq_rounded,
      FileFamily.text => Icons.notes_rounded,
      FileFamily.pdf => Icons.picture_as_pdf_rounded,
      FileFamily.archive => Icons.archive_rounded,
      FileFamily.document => Icons.description_rounded,
      FileFamily.other => Icons.insert_drive_file_rounded,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: colors.$2, size: size * 0.48),
    );
  }

  (Color, Color) _colors(AppPalette palette, FileFamily family) {
    return switch (family) {
      FileFamily.folder => (palette.accentSoft, palette.accent),
      FileFamily.image => (const Color(0xFFF8D7E4), const Color(0xFFB4234E)),
      FileFamily.video => (const Color(0xFFE4D8F8), const Color(0xFF6938B0)),
      FileFamily.audio => (const Color(0xFFD7F3EA), const Color(0xFF0F766E)),
      FileFamily.text => (const Color(0xFFE7E4DE), palette.ink),
      FileFamily.pdf => (const Color(0xFFF8D6D2), const Color(0xFFB42318)),
      FileFamily.archive => (const Color(0xFFF6E4CC), const Color(0xFF9A6700)),
      FileFamily.document => (const Color(0xFFD9E6F8), const Color(0xFF1D4E89)),
      FileFamily.other => (palette.line, palette.muted),
    };
  }
}
