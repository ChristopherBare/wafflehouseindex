import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

void main() {
  runApp(const WHIApp());
}

class WHIApp extends StatelessWidget {
  const WHIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waffle House Index',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      home: const WHIHomePage(),
    );
  }
}

class WHIHomePage extends StatefulWidget {
  const WHIHomePage({super.key});

  @override
  State<WHIHomePage> createState() => _WHIHomePageState();
}

class _WHIHomePageState extends State<WHIHomePage> {
  late Future<WHIResult> _future;
  double _radius = 50.0; // Default radius in miles
  Position? _cachedPosition; // Cache position to avoid re-requesting
  bool _isLoading = false; // Track loading state for slider changes
  Timer? _debounceTimer; // Debounce timer for slider updates

  @override
  void initState() {
    super.initState();
    _future = _load(_radius);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<WHIResult> _load(double radius) async {
    // 1) Get permission and current position (use cached if available)
    Position pos;

    if (_cachedPosition != null) {
      pos = _cachedPosition!;
    } else {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) {
        throw Exception('Location permission denied or unavailable (on Linux, ensure geoclue/location services are running)');
      }

      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        // Fallback for desktop/testing: Use Atlanta, GA coordinates
        if (e.toString().contains('getCurrentPosition') ||
            e.toString().contains('isLocationServiceEnabled') ||
            e.toString().contains('timeLimit')) {
          print('Using default location (Atlanta, GA) for testing');
          pos = _MockPosition(latitude: 33.7490, longitude: -84.3880);
        } else {
          rethrow;
        }
      }
      _cachedPosition = pos; // Cache the position
    }

    // 2) Call API to get Waffle House Index for location with specified radius
    final apiResult = await _fetchIndexFromAPI(pos.latitude, pos.longitude, radius: radius);

    // 3) Extract location details from API result
    final details = <LocationDetail>[];
    final locations = apiResult['locations'] as List<dynamic>? ?? [];

    for (final loc in locations) {
      if (loc is! Map<String, dynamic>) continue;

      details.add(LocationDetail(
        id: loc['id']?.toString() ?? '',
        name: loc['name']?.toString(),
        city: loc['city']?.toString(),
        state: loc['state']?.toString(),
        status: loc['status']?.toString() ?? 'Closed',
        lat: (loc['lat'] is num) ? (loc['lat'] as num).toDouble() : 0.0,
        lon: (loc['lon'] is num) ? (loc['lon'] as num).toDouble() : 0.0,
        distanceMiles: (loc['distance_mi'] is num) ? (loc['distance_mi'] as num).toDouble() : null,
      ));
    }

    // 4) Compute index
    final total = apiResult['total'] as int? ?? 0;
    final open = apiResult['open_count'] as int? ?? 0;
    final closed = apiResult['closed_count'] as int? ?? 0;
    final openPct = (apiResult['open_percentage'] as num? ?? 0.0) / 100.0;
    final closedPct = (apiResult['closed_percentage'] as num? ?? 0.0) / 100.0;

    return WHIResult(
      position: pos,
      locations: details,
      openCount: open,
      closedCount: closed,
      openPct: openPct,
      closedPct: closedPct,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Waffle House Index (${_radius.toInt()} mi)'),
      ),
      body: FutureBuilder<WHIResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snapshot.error}'),
              ),
            );
          }
          final result = snapshot.data!;

          // Calculate index status with multiple severity levels
          Color statusColor;
          IconData statusIcon;
          String statusText;
          String statusDescription;

          if (result.openPct >= 0.95) {
            statusColor = Colors.green;
            statusIcon = Icons.check_circle;
            statusText = 'All Clear';
            statusDescription = 'Normal operations - minimal impact';
          } else if (result.openPct >= 0.80) {
            statusColor = Colors.lightGreen;
            statusIcon = Icons.check_circle_outline;
            statusText = 'Minor Impact';
            statusDescription = 'Some locations affected';
          } else if (result.openPct >= 0.60) {
            statusColor = Colors.orange;
            statusIcon = Icons.warning_amber;
            statusText = 'Moderate Alert';
            statusDescription = 'Significant regional impact';
          } else if (result.openPct >= 0.40) {
            statusColor = Colors.deepOrange;
            statusIcon = Icons.warning;
            statusText = 'Severe Alert';
            statusDescription = 'Major disaster conditions';
          } else {
            statusColor = Colors.red;
            statusIcon = Icons.dangerous;
            statusText = 'Critical Alert';
            statusDescription = 'Catastrophic conditions';
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _future = _load(_radius);
              });
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Status Indicator Card (FIXED)
                Card(
                  elevation: 4,
                  color: Color.alphaBlend(statusColor.withOpacity(0.08), Colors.white),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: statusColor.withOpacity(0.4), width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(statusColor.withOpacity(0.15), Colors.white),
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
                          ),
                          child: Icon(statusIcon, color: statusColor, size: 40),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                statusDescription,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: statusColor.withOpacity(0.85),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.store, size: 16, color: statusColor.withOpacity(0.8)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${(result.openPct * 100).toStringAsFixed(1)}% open',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: statusColor.withOpacity(0.85),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Radius Slider Card (FIXED with debouncing and 500 mile range)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Search Radius', style: Theme.of(context).textTheme.titleMedium),
                            Text(
                              '${_radius.toInt()} miles',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Slider(
                          value: _radius,
                          min: 10,
                          max: 500,
                          divisions: 49,  // (500-10)/10 = 49 divisions for 10-mile increments
                          label: '${_radius.toInt()} mi',
                          activeColor: Theme.of(context).primaryColor,
                          onChanged: _isLoading ? null : (value) {
                            setState(() {
                              _radius = value;
                            });

                            // Cancel any existing timer
                            _debounceTimer?.cancel();

                            // Start a new timer that will trigger after 500ms of inactivity
                            _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                              setState(() {
                                _isLoading = true;
                                _future = _load(_radius).whenComplete(() {
                                  if (mounted) {
                                    setState(() {
                                      _isLoading = false;
                                    });
                                  }
                                });
                              });
                            });
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('10 mi', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('500 mi', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Stats Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nearby stores: ${result.locations.length}', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Open: ${result.openCount} (${(result.openPct * 100).toStringAsFixed(0)}%)'),
                        Text('Closed: ${result.closedCount} (${(result.closedPct * 100).toStringAsFixed(0)}%)'),
                        if (result.position is _MockPosition)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Using Atlanta, GA as default location',
                              style: TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...result.locations.map((loc) => Card(
                      child: ListTile(
                        leading: Icon(
                          loc.status == 'Open' ? Icons.check_circle : Icons.cancel,
                          color: loc.status == 'Open' ? Colors.green : Colors.red,
                        ),
                        title: Text(loc.name ?? 'Waffle House #${loc.id}'),
                        subtitle: Text('${loc.city ?? ''} ${loc.state ?? ''} • ${loc.distanceMiles?.toStringAsFixed(1) ?? '?'} mi'),
                        trailing: Text(loc.status),
                      ),
                    )),
                const SizedBox(height: 24),
                const Text(
                  'Note: The Waffle House Index indicates disaster severity. Below 80% suggests significant regional impact.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return false;
      }
      return true;
    } catch (e) {
      // On Linux desktop, location services might not be available
      // Return true to allow using a default location
      if (e.toString().contains('isLocationServiceEnabled')) {
        print('Location services not available on this platform, using default location');
        return true;
      }
      rethrow;
    }
  }

  double _distanceMiles(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final km = R * c;
    return km * 0.621371; // miles
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  // API configuration - automatically detects platform and environment
  String get _apiBaseUrl {
    if (kIsWeb) {
      // Web app
      return ApiConfig.getApiBaseUrl(
        isAndroid: false,
        isIOS: false,
        isDesktop: true,
      );
    }

    // Platform checks (only works on non-web platforms)
    try {
      return ApiConfig.getApiBaseUrl(
        isAndroid: Platform.isAndroid,
        isIOS: Platform.isIOS,
        isDesktop: Platform.isLinux || Platform.isMacOS || Platform.isWindows,
      );
    } catch (e) {
      // Fallback if platform detection fails
      print('Platform detection failed: $e');
      return ApiConfig.getApiBaseUrl(
        isAndroid: false,
        isIOS: false,
        isDesktop: true,
      );
    }
  }

  Future<Map<String, dynamic>> _fetchIndexFromAPI(double lat, double lon, {double radius = 50.0}) async {
    final uri = Uri.parse('$_apiBaseUrl/api/index/coordinates/').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radius': radius.toString(),
      },
    );

    // Retry logic for initial connection
    int retries = 3;
    Exception? lastError;

    for (int i = 0; i < retries; i++) {
      try {
        final res = await http.get(
          uri,
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) {
          throw Exception('Failed to fetch data from API (${res.statusCode})');
        }

        try {
          return jsonDecode(res.body) as Map<String, dynamic>;
        } catch (e) {
          throw Exception('Failed to parse API response: $e');
        }
      } catch (e) {
        lastError = e as Exception;
        if (i < retries - 1) {
          // Wait before retrying (exponential backoff)
          await Future.delayed(Duration(seconds: (i + 1) * 2));
          print('Retrying API connection (attempt ${i + 2}/$retries)...');
        }
      }
    }

    throw lastError ?? Exception('Failed to connect to API after $retries attempts');
  }

  // Old detail API method - no longer needed since we get everything from main page
  // Keeping for reference but not used
  /*
  Future<List<LocationDetail>> _fetchLocationDetails(List<String> ids, {int batchSize = 10}) async {
    // This method is no longer needed - we get all data from the main page now
    // Just like the Python script does
    return [];
  }
  */
}

// BasicLocation class no longer needed - we use LocationDetail directly now

class LocationDetail {
  final String id;
  final String? name;
  final String? city;
  final String? state;
  final String status; // Open/Closed
  final double lat;
  final double lon;
  double? distanceMiles;
  LocationDetail({
    required this.id,
    this.name,
    this.city,
    this.state,
    required this.status,
    required this.lat,
    required this.lon,
    this.distanceMiles,
  });
}

class WHIResult {
  final Position position;
  final List<LocationDetail> locations;
  final int openCount;
  final int closedCount;
  final double openPct;
  final double closedPct;
  WHIResult({
    required this.position,
    required this.locations,
    required this.openCount,
    required this.closedCount,
    required this.openPct,
    required this.closedPct,
  });
}

// Mock Position class for Linux desktop testing
class _MockPosition implements Position {
  @override
  final double latitude;

  @override
  final double longitude;

  _MockPosition({required this.latitude, required this.longitude});

  @override
  double get accuracy => 10.0;

  @override
  double get altitude => 0.0;

  @override
  double get altitudeAccuracy => 0.0;

  @override
  double get heading => 0.0;

  @override
  double get headingAccuracy => 0.0;

  @override
  double get speed => 0.0;

  @override
  double get speedAccuracy => 0.0;

  @override
  DateTime get timestamp => DateTime.now();

  @override
  int? get floor => null;

  @override
  bool get isMocked => true;

  @override
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'altitudeAccuracy': altitudeAccuracy,
    'heading': heading,
    'headingAccuracy': headingAccuracy,
    'speed': speed,
    'speedAccuracy': speedAccuracy,
    'timestamp': timestamp.toIso8601String(),
    'floor': floor,
    'isMocked': isMocked,
  };
}
