import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.protocol,
    required this.title,
    required this.host,
    required this.port,
    required this.actionLabel,
    required this.onOpen,
    this.detail,
    this.online = false,
    this.onEdit,
    this.onDelete,
  });

  final RemoteProtocol protocol;
  final String title;
  final String host;
  final int port;
  final String? detail;
  final String actionLabel;
  final bool online;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tone = protocol == RemoteProtocol.smb ? palette.samba : palette.ftp;
    final soft = protocol == RemoteProtocol.smb
        ? palette.sambaSoft
        : palette.ftpSoft;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.line),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    protocol == RemoteProtocol.smb
                        ? Icons.dns_rounded
                        : Icons.photo_library_rounded,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (online) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: palette.ok,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$host:$port',
                        style: TextStyle(color: palette.muted, fontSize: 13),
                      ),
                      if (detail != null && detail!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        protocol.title,
                        style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onEdit != null)
                          IconButton(
                            tooltip: '修改登录',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: onEdit,
                            icon: const Icon(Icons.key_rounded, size: 20),
                          ),
                        if (onDelete != null)
                          IconButton(
                            tooltip: '忘记',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: onDelete,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                          ),
                        Text(
                          actionLabel,
                          style: TextStyle(
                            color: palette.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
