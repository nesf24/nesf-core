import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/api.dart';
import '../theme.dart';

/// Status pill matching the chip printed on the issued PDF.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.compact = false});
  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = statusStyle(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          color: s.fg,
          fontSize: compact ? 10.5 : 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Section heading used down the length of the forms and detail screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.padTop = true});
  final String text;
  final Widget? action;
  final bool padTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: padTop ? 22 : 0, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: NesfColors.muted,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Label/value row, mirroring the layout of the PDF detail blocks.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});
  final String label;
  final String? value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: NesfColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value!.isEmpty) ? '—' : value!,
              style: TextStyle(
                fontSize: 13.5,
                color: valueColor ?? NesfColors.ink,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card wrapper with consistent padding for list rows and form blocks.
class NesfCard extends StatelessWidget {
  const NesfCard({super.key, required this.child, this.onTap, this.padding});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );
  }
}

/// Shown when a list has nothing in it — states the reason, not just "empty".
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: NesfColors.greenLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: NesfColors.green),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: NesfColors.ink),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: NesfColors.muted, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Error state with a retry, used by every list that loads from the API.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: NesfColors.muted),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: NesfColors.body, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Displays a file held privately by the API — an attendance selfie, a scanned
/// signature, a profile photo.
///
/// Uploads are not publicly readable, so the image request has to carry the
/// session token. This wraps that plumbing and the loading/error fallbacks so
/// screens only need to pass the storage key.
class PrivateImage extends StatelessWidget {
  const PrivateImage({
    super.key,
    required this.storageKey,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  /// The key as returned by the API (e.g. `attendance/2026-08/….jpg`).
  final String? storageKey;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final url = AppConfig.mediaUrl(storageKey);
    final fallback = errorWidget ??
        placeholder ??
        SizedBox(width: width, height: height);
    if (url == null) return fallback;

    return Image.network(
      url,
      headers: context.read<Api>().mediaHeaders,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return placeholder ??
            Container(
              width: width,
              height: height,
              color: NesfColors.greenLight,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.8, color: NesfColors.green),
              ),
            );
      },
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.photoKey, this.size = 40});
  final String initials;

  /// Storage key of the profile photo, not a public URL.
  final String? photoKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = AppConfig.mediaUrl(photoKey);
    if (url != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: NesfColors.greenLight,
        foregroundImage: NetworkImage(url, headers: context.read<Api>().mediaHeaders),
        // Initials remain as the fallback if the image fails to load.
        child: Text(initials, style: TextStyle(fontSize: size * 0.36, color: NesfColors.green)),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: NesfColors.greenLight,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: NesfColors.green,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers shared by every screen
// ---------------------------------------------------------------------------

final _dayMonth = DateFormat('d MMM yyyy');
final _dayMonthShort = DateFormat('d MMM');
final _timeFmt = DateFormat('h:mm a');

String fmtDate(dynamic value) {
  final d = _parse(value);
  return d == null ? '—' : _dayMonth.format(d);
}

String fmtDateShort(dynamic value) {
  final d = _parse(value);
  return d == null ? '—' : _dayMonthShort.format(d);
}

String fmtTime(dynamic value) {
  final d = _parse(value);
  return d == null ? '—' : _timeFmt.format(d.toLocal());
}

/// Renders a date range the way the documents do, collapsing a single day.
String fmtRange(dynamic from, dynamic to) {
  final f = _parse(from);
  final t = _parse(to);
  if (f == null) return '—';
  if (t == null || f == t) return _dayMonth.format(f);
  return '${_dayMonthShort.format(f)} – ${_dayMonth.format(t)}';
}

DateTime? _parse(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse('$value');
}

/// Paise -> "₹1,23,456" with Indian digit grouping, matching the PDFs.
String fmtMoney(dynamic paise, {bool decimals = false}) {
  final rupees = (num.tryParse('${paise ?? 0}') ?? 0) / 100;
  final fmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: decimals ? 2 : 0,
  );
  return fmt.format(rupees);
}

/// "2 h 35 m" from a minute count, for time worked.
String fmtDuration(dynamic minutes) {
  final m = int.tryParse('${minutes ?? 0}') ?? 0;
  if (m <= 0) return '—';
  final h = m ~/ 60;
  final rem = m % 60;
  if (h == 0) return '$rem m';
  return rem == 0 ? '$h h' : '$h h $rem m';
}

/// The date format the API's DATE columns expect.
String apiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void showSnack(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? NesfColors.rejected : NesfColors.greenDark,
      duration: Duration(seconds: error ? 5 : 3),
    ));
}
