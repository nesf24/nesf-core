import 'package:flutter_test/flutter_test.dart';
import 'package:nesf_core/config.dart';
import 'package:nesf_core/widgets/common.dart';

void main() {
  group('private media URLs', () {
    test('turns a storage key into an /api/media URL', () {
      final url = AppConfig.mediaUrl('attendance/2026-08/abc.jpg');
      expect(url, '${AppConfig.apiUrl}/media/attendance/2026-08/abc.jpg');
    });

    test('tolerates a leading slash', () {
      expect(AppConfig.mediaUrl('/signatures/a.png'),
          '${AppConfig.apiUrl}/media/signatures/a.png');
    });

    test('passes an absolute URL through untouched', () {
      // Records written before uploads became private may hold a full URL.
      const external = 'https://example.com/legacy/sig.png';
      expect(AppConfig.mediaUrl(external), external);
    });

    test('returns null for nothing, so callers can fall back', () {
      expect(AppConfig.mediaUrl(null), isNull);
      expect(AppConfig.mediaUrl(''), isNull);
      expect(AppConfig.mediaUrl('   '), isNull);
    });
  });

  group('money formatting', () {
    test('renders paise as rupees with Indian digit grouping', () {
      // 9,00,000 paise = Rs 9,000 — the figure a TA/DA bill would show.
      expect(fmtMoney(900000), '₹9,000');
      expect(fmtMoney(25000000), '₹2,50,000');
      expect(fmtMoney(0), '₹0');
    });

    test('includes paise when decimals are requested', () {
      expect(fmtMoney(850050, decimals: true), '₹8,500.50');
    });

    test('treats null as zero rather than throwing', () {
      expect(fmtMoney(null), '₹0');
    });
  });

  group('duration formatting', () {
    test('splits minutes into hours and minutes', () {
      expect(fmtDuration(155), '2 h 35 m');
      expect(fmtDuration(120), '2 h');
      expect(fmtDuration(45), '45 m');
    });

    test('shows a dash when no time is recorded', () {
      // A staff member who has checked in but not out has no worked minutes yet.
      expect(fmtDuration(0), '—');
      expect(fmtDuration(null), '—');
    });
  });

  group('api date formatting', () {
    test('pads month and day to the format the API expects', () {
      expect(apiDate(DateTime(2026, 8, 5)), '2026-08-05');
      expect(apiDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  // In-app dates use the compact 'd MMM yyyy' form; the issued PDFs use the
  // formal 'd MMMM yyyy' spelled-out month instead.
  group('date range formatting', () {
    test('collapses a single-day range', () {
      expect(fmtRange('2026-08-17', '2026-08-17'), '17 Aug 2026');
    });

    test('shows both ends of a multi-day range', () {
      expect(fmtRange('2026-08-17', '2026-08-19'), '17 Aug – 19 Aug 2026');
    });

    test('falls back to a dash without a start date', () {
      expect(fmtRange(null, '2026-08-19'), '—');
    });
  });
}
