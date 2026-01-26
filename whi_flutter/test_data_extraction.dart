// Test script to verify data extraction is working
// Run with: dart test_data_extraction.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

const _ua = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';

Future<void> main() async {
  print('Testing Waffle House data extraction (Next.js method)...\n');

  try {
    final uri = Uri.parse('https://locations.wafflehouse.com');
    final res = await http.get(uri, headers: {
      'User-Agent': _ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    });

    if (res.statusCode != 200) {
      throw Exception('Failed to load page (${res.statusCode})');
    }

    final html = res.body;

    // Extract __NEXT_DATA__
    final regex = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', dotAll: true);
    final match = regex.firstMatch(html);

    if (match == null) {
      throw Exception('Failed to find __NEXT_DATA__ in page');
    }

    final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final props = data['props'] as Map<String, dynamic>?;
    final pageProps = props?['pageProps'] as Map<String, dynamic>?;
    final locations = pageProps?['locations'] as List?;

    if (locations == null) {
      throw Exception('No locations found in Next.js data');
    }

    print('✅ Found ${locations.length} total locations\n');

    // Count open vs closed
    int openCount = 0;
    int closedCount = 0;

    for (final loc in locations) {
      if (loc is Map<String, dynamic>) {
        final statusField = loc['_status']?.toString() ?? '';
        if (statusField == 'A') {
          openCount++;
        } else {
          closedCount++;
        }
      }
    }

    print('Status breakdown:');
    print('  Open: $openCount');
    print('  Closed: $closedCount');
    print('  Total: ${locations.length}');
    print('');

    // Show sample location
    if (locations.isNotEmpty) {
      final sample = locations[0] as Map<String, dynamic>;
      print('Sample location:');
      print('  storeCode: ${sample['storeCode']}');
      print('  businessName: ${sample['businessName']}');
      print('  city: ${sample['city']}');
      print('  state: ${sample['state']}');
      print('  _status: ${sample['_status']}');
      print('  latitude: ${sample['latitude']}');
      print('  longitude: ${sample['longitude']}');
    }

    print('\n✅ Data extraction working correctly!');
    print('The Flutter app should now work properly.');

  } catch (e) {
    print('❌ Error: $e');
  }
}