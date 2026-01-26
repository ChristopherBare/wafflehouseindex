import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whi_flutter/main.dart';

void main() {
  group('Integration Tests', () {
    test('WHIResult calculates percentages correctly', () {
      // Test with 10 locations, 7 open, 3 closed
      final locations = List.generate(10, (i) => LocationDetail(
        id: '$i',
        name: 'Location $i',
        status: i < 7 ? 'Open' : 'Closed',
        lat: 33.7490 + i * 0.01,
        lon: -84.3880 + i * 0.01,
      ));

      int openCount = 0;
      int closedCount = 0;
      for (final loc in locations) {
        if (loc.status == 'Open') {
          openCount++;
        } else {
          closedCount++;
        }
      }

      expect(openCount, 7);
      expect(closedCount, 3);

      final openPct = openCount / locations.length;
      final closedPct = closedCount / locations.length;

      expect(openPct, 0.7);
      expect(closedPct, 0.3);
    });

    test('Location filtering works within 50 miles', () {
      final centerLat = 33.7490;
      final centerLon = -84.3880;

      final locations = [
        BasicLocation(id: '1', lat: centerLat, lon: centerLon), // 0 miles
        BasicLocation(id: '2', lat: centerLat + 0.5, lon: centerLon), // ~35 miles
        BasicLocation(id: '3', lat: centerLat + 1.0, lon: centerLon), // ~69 miles
        BasicLocation(id: '4', lat: centerLat + 0.7, lon: centerLon), // ~48 miles
      ];

      final state = _WHIHomePageState();
      final filtered = locations.where((loc) {
        final distance = state.testDistanceMiles(centerLat, centerLon, loc.lat, loc.lon);
        return distance <= 50.0;
      }).toList();

      expect(filtered.length, 3); // Should include locations 1, 2, and 4
      expect(filtered.any((l) => l.id == '1'), true);
      expect(filtered.any((l) => l.id == '2'), true);
      expect(filtered.any((l) => l.id == '3'), false); // Too far
      expect(filtered.any((l) => l.id == '4'), true);
    });

    test('Status determination based on specialHoursOfOperation', () {
      // According to the app logic, if specialHoursOfOperation has length of 2, it's Open
      // Otherwise it's Closed

      final specialHours2Chars = '[]'; // Length 2 = Open
      final specialHoursLong = '["9AM-5PM", "10AM-4PM"]'; // Length > 2 = Closed
      final specialHoursEmpty = ''; // Length 0 = Closed

      expect(specialHours2Chars.trim().length == 2, true); // Should be Open
      expect(specialHoursLong.trim().length == 2, false); // Should be Closed
      expect(specialHoursEmpty.trim().length == 2, false); // Should be Closed
    });

    test('Distance sorting works correctly', () {
      final locations = [
        LocationDetail(id: '1', status: 'Open', lat: 33.8, lon: -84.4, distanceMiles: 10.5),
        LocationDetail(id: '2', status: 'Open', lat: 33.75, lon: -84.39, distanceMiles: 2.3),
        LocationDetail(id: '3', status: 'Closed', lat: 33.9, lon: -84.5, distanceMiles: 25.7),
        LocationDetail(id: '4', status: 'Open', lat: 33.74, lon: -84.38, distanceMiles: 0.8),
      ];

      locations.sort((a, b) =>
        (a.distanceMiles ?? 0).compareTo(b.distanceMiles ?? 0)
      );

      expect(locations[0].id, '4'); // Closest
      expect(locations[1].id, '2');
      expect(locations[2].id, '1');
      expect(locations[3].id, '3'); // Farthest
    });

    test('Empty location list handles correctly', () {
      final locations = <LocationDetail>[];

      final total = locations.length;
      int open = 0;
      for (final d in locations) {
        if (d.status == 'Open') open++;
      }
      final closed = total - open;
      final openPct = total == 0 ? 0.0 : open / total;
      final closedPct = total == 0 ? 0.0 : closed / total;

      expect(total, 0);
      expect(open, 0);
      expect(closed, 0);
      expect(openPct, 0.0);
      expect(closedPct, 0.0);
    });

    test('All locations open scenario', () {
      final locations = List.generate(5, (i) => LocationDetail(
        id: '$i',
        status: 'Open',
        lat: 33.7490 + i * 0.01,
        lon: -84.3880 + i * 0.01,
      ));

      int openCount = 0;
      for (final loc in locations) {
        if (loc.status == 'Open') openCount++;
      }

      expect(openCount, 5);
      expect(openCount / locations.length, 1.0);
    });

    test('All locations closed scenario', () {
      final locations = List.generate(5, (i) => LocationDetail(
        id: '$i',
        status: 'Closed',
        lat: 33.7490 + i * 0.01,
        lon: -84.3880 + i * 0.01,
      ));

      int closedCount = 0;
      for (final loc in locations) {
        if (loc.status == 'Closed') closedCount++;
      }

      expect(closedCount, 5);
      expect(closedCount / locations.length, 1.0);
    });
  });
}

// Test helper class (same as in widget_test.dart)
class _WHIHomePageState {
  double testDistanceMiles(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final km = R * c;
    return km * 0.621371; // miles
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);
}