import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  int _selectedIndex = 0;

  SharedPreferences? _prefs;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  bool _notificationsEnabled = false;
  double _alertThreshold = 0.8;
  bool _alertedBelowThreshold = false;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _iapSubscription;
  bool _iapAvailable = false;
  bool _iapLoading = false;
  String? _iapError;
  List<ProductDetails> _products = [];
  bool _isPremium = false;

  static const String _prefsPremiumKey = 'premium_enabled';
  static const String _prefsNotificationsKey = 'notifications_enabled';
  static const String _prefsAlertThresholdKey = 'alert_threshold';

  @override
  void initState() {
    super.initState();
    _future = _load(_radius);
    _loadPreferences();
    _initNotifications();
    _initIap();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _iapSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final premium = prefs.getBool(_prefsPremiumKey) ?? false;
    final notificationsEnabled = prefs.getBool(_prefsNotificationsKey) ?? false;
    final alertThreshold = prefs.getDouble(_prefsAlertThresholdKey) ?? 0.8;

    if (!mounted) return;
    setState(() {
      _isPremium = premium || ApiConfig.testPremiumEnabled;
      _notificationsEnabled = notificationsEnabled;
      _alertThreshold = alertThreshold;
    });
  }

  Future<void> _persistBool(String key, bool value) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs ??= prefs;
    await prefs.setBool(key, value);
  }

  Future<void> _persistDouble(String key, double value) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs ??= prefs;
    await prefs.setDouble(key, value);
  }

  Future<void> _initNotifications() async {
    if (kIsWeb) {
      return;
    }

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(initSettings);

      const channel = AndroidNotificationChannel(
        'whi_alerts',
        'Waffle House Alerts',
        description:
            'Alerts when the Waffle House Index drops below your threshold.',
        importance: Importance.high,
      );
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      _notificationsReady = true;
    } catch (e) {
      print('Notifications unavailable: $e');
    }
  }

  Future<bool> _requestNotificationPermissionIfNeeded() async {
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    }

    return true;
  }

  Future<void> _toggleNotifications(bool value) async {
    if (!_isPremium) return;

    if (value) {
      final granted = await _requestNotificationPermissionIfNeeded();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification permission was not granted.'),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _notificationsEnabled = value;
    });
    await _persistBool(_prefsNotificationsKey, value);
  }

  Future<void> _updateAlertThreshold(double value) async {
    if (!_isPremium) return;

    setState(() {
      _alertThreshold = value;
    });
    _alertedBelowThreshold = false;
    await _persistDouble(_prefsAlertThresholdKey, value);
  }

  void _maybeSendAlert(WHIResult result) {
    if (!_notificationsReady || !_notificationsEnabled || !_isPremium) {
      _alertedBelowThreshold = false;
      return;
    }

    final isBelow = result.openPct < _alertThreshold;
    if (isBelow && !_alertedBelowThreshold) {
      _alertedBelowThreshold = true;
      _sendAlert(result);
    } else if (!isBelow) {
      _alertedBelowThreshold = false;
    }
  }

  Future<void> _sendAlert(WHIResult result) async {
    if (kIsWeb) return;

    final thresholdPct = (_alertThreshold * 100).toStringAsFixed(0);
    final openPct = (result.openPct * 100).toStringAsFixed(1);

    const androidDetails = AndroidNotificationDetails(
      'whi_alerts',
      'Waffle House Alerts',
      channelDescription:
          'Alerts when the Waffle House Index drops below your threshold.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        0,
        'Waffle House Index Alert',
        'Open locations dropped to $openPct% (threshold $thresholdPct%).',
        notificationDetails,
      );
    } catch (e) {
      print('Failed to send notification: $e');
    }
  }

  Future<void> _initIap() async {
    if (kIsWeb) {
      // Web-specific IAP initialization or mock setup
      setState(() {
        _iapAvailable = true;
        _products = [
          ProductDetails(
            id: ApiConfig.premiumMonthlyProductId,
            title: 'Waffle House Index Premium (Monthly)',
            description: 'Monthly subscription for advanced features',
            price: '\$4.99',
            rawPrice: 4.99,
            currencyCode: 'USD',
          ),
          ProductDetails(
            id: ApiConfig.premiumAnnualProductId,
            title: 'Waffle House Index Premium (Annual)',
            description: 'Annual subscription with best value',
            price: '\$49.99',
            rawPrice: 49.99,
            currencyCode: 'USD',
          ),
        ];
      });
      return;
    }

    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return;
    }

    _iapSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _iapError = error.toString();
        });
      },
    );

    setState(() {
      _iapLoading = true;
    });

    final available = await _iap.isAvailable();
    if (!mounted) return;

    if (!available) {
      setState(() {
        _iapAvailable = false;
        _iapLoading = false;
      });
      return;
    }

    final response =
        await _iap.queryProductDetails(ApiConfig.premiumProductIds);
    if (!mounted) return;

    setState(() {
      _iapAvailable = true;
      _iapLoading = false;
      _products = response.productDetails;
      _iapError = response.error?.message;
    });
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _setPremium(true);
      } else if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() {
            _iapError = purchase.error?.message;
          });
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _setPremium(bool value) async {
    if (!mounted) return;

    setState(() {
      _isPremium = value;
    });
    await _persistBool(_prefsPremiumKey, value);
  }

  Future<void> _buyProduct(ProductDetails product) async {
    if (kIsWeb) {
      // Simulate purchase for web
      await _setPremium(true);
      return;
    }

    if (!_iapAvailable) return;

    final purchaseParam = PurchaseParam(productDetails: product);
    setState(() {
      _iapError = null;
    });
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _restorePurchases() async {
    if (kIsWeb) {
      // For web, we might want to "restore" by just saying it's active
      // or just checking preferences (which _loadPreferences already does).
      // Here we can just simulate a successful check.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchases restored (simulated)')),
      );
      return;
    }
    if (!_iapAvailable) return;

    await _iap.restorePurchases();
  }

  Future<WHIResult> _load(double radius) async {
    // 1) Get permission and current position (use cached if available)
    Position pos;

    if (_cachedPosition != null) {
      pos = _cachedPosition!;
    } else {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) {
        throw Exception(
          'Location permission denied or unavailable (on Linux, ensure geoclue/location services are running)',
        );
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
    final apiResult =
        await _fetchIndexFromAPI(pos.latitude, pos.longitude, radius: radius);

    return _parseApiResult(apiResult, pos);
  }

  WHIResult _parseApiResult(Map<String, dynamic> apiResult, Position pos) {
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
        distanceMiles: (loc['distance_mi'] is num)
            ? (loc['distance_mi'] as num).toDouble()
            : null,
      ));
    }

    // 3) Compute index
    final total = apiResult['total'] as int? ?? 0;
    final open = apiResult['open_count'] as int? ?? 0;
    final closed = apiResult['closed_count'] as int? ?? 0;
    final openPct = (apiResult['open_percentage'] as num? ?? 0.0) / 100.0;
    final closedPct =
        (apiResult['closed_percentage'] as num? ?? 0.0) / 100.0;

    return WHIResult(
      position: pos,
      locations: details,
      openCount: open,
      closedCount: closed,
      openPct: openPct,
      closedPct: closedPct,
    );
  }

  Future<WHIResult> _loadByZip(String zip, double radius) async {
    final apiResult = await _fetchIndexFromZip(zip, radius: radius);
    final lat = (apiResult['latitude'] as num?)?.toDouble() ?? 0.0;
    final lon = (apiResult['longitude'] as num?)?.toDouble() ?? 0.0;
    final pos = _MockPosition(latitude: lat, longitude: lon);

    return _parseApiResult(apiResult, pos);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load(_radius);
    });
    await _future;
  }

  void _handleRadiusChanged(double value) {
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
  }

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return 'Waffle House Index (${_radius.toInt()} mi)';
      case 1:
        return 'Nearby Map';
      case 2:
        return 'Search by ZIP';
      case 3:
        return 'Menu';
      default:
        return 'Waffle House Index';
    }
  }

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
    return ApiConfig.getApiBaseUrl(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
      isDesktop: Platform.isLinux || Platform.isMacOS || Platform.isWindows,
    );
  }

  Future<Map<String, dynamic>> _fetchIndexFromAPI(
    double lat,
    double lon, {
    double radius = 50.0,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/api/index/coordinates/').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radius': radius.toString(),
      },
    );

    return _fetchFromUri(uri);
  }

  Future<Map<String, dynamic>> _fetchIndexFromZip(
    String zip, {
    double radius = 50.0,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/api/index/zip/').replace(
      queryParameters: {
        'zip': zip,
        'radius': radius.toString(),
      },
    );

    return _fetchFromUri(uri);
  }

  Future<Map<String, dynamic>> _fetchFromUri(Uri uri) async {
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

    throw lastError ??
        Exception('Failed to connect to API after $retries attempts');
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
        print(
          'Location services not available on this platform, using default location',
        );
        return true;
      }
      rethrow;
    }
  }

  void _goToUpgrade() {
    setState(() {
      _selectedIndex = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForIndex(_selectedIndex)),
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
          if (!snapshot.hasData) {
            return const Center(child: Text('No data available'));
          }

          final result = snapshot.data!;
          _maybeSendAlert(result);

          return IndexedStack(
            index: _selectedIndex,
            children: [
              HomeTab(
                result: result,
                radius: _radius,
                isLoading: _isLoading,
                onRadiusChanged: _handleRadiusChanged,
                onRefresh: _refresh,
              ),
              MapTab(
                result: result,
                radius: _radius,
                isLoading: _isLoading,
              ),
              SearchTab(
                isPremium: _isPremium,
                radius: _radius,
                onSearch: _loadByZip,
                onUpgradeRequested: _goToUpgrade,
              ),
              MenuTab(
                isPremium: _isPremium,
                iapAvailable: _iapAvailable,
                iapLoading: _iapLoading,
                iapError: _iapError,
                products: _products,
                onPurchase: _buyProduct,
                onRestorePurchases: _restorePurchases,
                notificationsEnabled: _notificationsEnabled,
                onNotificationsToggle: _toggleNotifications,
                alertThreshold: _alertThreshold,
                onAlertThresholdChanged: _updateAlertThreshold,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (value) {
          setState(() {
            _selectedIndex = value;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'Menu',
          ),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  final WHIResult result;
  final double radius;
  final bool isLoading;
  final ValueChanged<double> onRadiusChanged;
  final Future<void> Function() onRefresh;

  const HomeTab({
    super.key,
    required this.result,
    required this.radius,
    required this.isLoading,
    required this.onRadiusChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final status = statusInfoFor(result.openPct);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          StatusSummaryCard(status: status, openPct: result.openPct),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Search Radius',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${radius.toInt()} miles',
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
                    value: radius,
                    min: 10,
                    max: 500,
                    divisions: 49,
                    label: '${radius.toInt()} mi',
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: isLoading ? null : onRadiusChanged,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        '10 mi',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        '500 mi',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nearby stores: ${result.locations.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open: ${result.openCount} (${(result.openPct * 100).toStringAsFixed(0)}%)',
                  ),
                  Text(
                    'Closed: ${result.closedCount} (${(result.closedPct * 100).toStringAsFixed(0)}%)',
                  ),
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
          ...buildLocationCards(result.locations),
          const SizedBox(height: 24),
          const Text(
            'Note: The Waffle House Index indicates disaster severity. Below 80% suggests significant regional impact.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class MapTab extends StatelessWidget {
  final WHIResult result;
  final double radius;
  final bool isLoading;

  const MapTab({
    super.key,
    required this.result,
    required this.radius,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final status = statusInfoFor(result.openPct);
    final markers = result.locations
        .where((loc) => loc.lat != 0.0 && loc.lon != 0.0)
        .map(
          (loc) {
            final isOpen = loc.status == 'Open';
            return Marker(
              width: 36,
              height: 36,
              point: LatLng(loc.lat, loc.lon),
              child: Icon(
                Icons.location_on,
                color: isOpen ? Colors.green : Colors.red,
                size: 32,
              ),
            );
          },
        )
        .toList();

    final bottomOffset =
        MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 12;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(
              result.position.latitude,
              result.position.longitude,
            ),
            initialZoom: zoomForRadius(radius),
            maxZoom: 18,
            minZoom: 3,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.whi_flutter',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        if (markers.isEmpty)
          const Center(
            child: Text('No locations found in this radius'),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: bottomOffset,
          child: MapSummaryBar(
            status: status,
            result: result,
            radius: radius,
            isLoading: isLoading,
          ),
        ),
      ],
    );
  }
}

class SearchTab extends StatefulWidget {
  final bool isPremium;
  final double radius;
  final Future<WHIResult> Function(String zip, double radius) onSearch;
  final VoidCallback onUpgradeRequested;

  const SearchTab({
    super.key,
    required this.isPremium,
    required this.radius,
    required this.onSearch,
    required this.onUpgradeRequested,
  });

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _zipController = TextEditingController();
  WHIResult? _result;
  String? _error;
  bool _isSearching = false;

  @override
  void dispose() {
    _zipController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final zip = _zipController.text.trim();
    if (zip.length != 5 || int.tryParse(zip) == null) {
      setState(() {
        _error = 'Enter a valid 5-digit ZIP code.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final result = await widget.onSearch(zip, widget.radius);
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPremium) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Premium Search',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Search the Waffle House Index by ZIP code and explore other areas.',
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: widget.onUpgradeRequested,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Upgrade to Premium'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final status = _result == null ? null : statusInfoFor(_result!.openPct);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search by ZIP',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _zipController,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  decoration: const InputDecoration(
                    labelText: 'ZIP code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _isSearching ? null : _submit,
                      child: const Text('Search'),
                    ),
                    const SizedBox(width: 12),
                    Text('Radius: ${widget.radius.toInt()} mi'),
                  ],
                ),
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_result != null && status != null) ...[
          StatusSummaryCard(status: status, openPct: _result!.openPct),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nearby stores: ${_result!.locations.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open: ${_result!.openCount} (${(_result!.openPct * 100).toStringAsFixed(0)}%)',
                  ),
                  Text(
                    'Closed: ${_result!.closedCount} (${(_result!.closedPct * 100).toStringAsFixed(0)}%)',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...buildLocationCards(_result!.locations),
        ],
      ],
    );
  }
}

class MenuTab extends StatelessWidget {
  final bool isPremium;
  final bool iapAvailable;
  final bool iapLoading;
  final String? iapError;
  final List<ProductDetails> products;
  final ValueChanged<ProductDetails> onPurchase;
  final VoidCallback onRestorePurchases;
  final bool notificationsEnabled;
  final ValueChanged<bool> onNotificationsToggle;
  final double alertThreshold;
  final ValueChanged<double> onAlertThresholdChanged;

  const MenuTab({
    super.key,
    required this.isPremium,
    required this.iapAvailable,
    required this.iapLoading,
    required this.iapError,
    required this.products,
    required this.onPurchase,
    required this.onRestorePurchases,
    required this.notificationsEnabled,
    required this.onNotificationsToggle,
    required this.alertThreshold,
    required this.onAlertThresholdChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Premium',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (isPremium)
                  Row(
                    children: const [
                      Icon(Icons.verified, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Premium active'),
                    ],
                  )
                else if (iapLoading)
                  const LinearProgressIndicator()
                else if (!iapAvailable)
                  const Text(
                    'Purchases are available on Android, iOS, and Web.',
                  )
                else ...[
                  if (iapError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Store error: $iapError',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (products.isEmpty)
                    const Text(
                      'No products found. Update the product IDs in config.dart.',
                    )
                  else
                    ...products.map(
                      (product) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(product.title),
                          subtitle: Text(product.description),
                          trailing: ElevatedButton(
                            onPressed: () => onPurchase(product),
                            child: Text(product.price),
                          ),
                        ),
                      ),
                    ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onRestorePurchases,
                    child: const Text('Restore purchases'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (!isPremium)
                  const Text('Premium is required to enable alerts.'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Alert when open percentage drops below threshold',
                  ),
                  value: notificationsEnabled,
                  onChanged: isPremium ? onNotificationsToggle : null,
                ),
                const SizedBox(height: 4),
                Text(
                  'Threshold: ${(alertThreshold * 100).toStringAsFixed(0)}%',
                ),
                Slider(
                  value: alertThreshold,
                  min: 0.4,
                  max: 0.95,
                  divisions: 11,
                  label: '${(alertThreshold * 100).toStringAsFixed(0)}%',
                  onChanged: (isPremium && notificationsEnabled)
                      ? onAlertThresholdChanged
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class StatusSummaryCard extends StatelessWidget {
  final StatusInfo status;
  final double openPct;

  const StatusSummaryCard({
    super.key,
    required this.status,
    required this.openPct,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: Color.alphaBlend(status.color.withOpacity(0.08), Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: status.color.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  status.color.withOpacity(0.15),
                  Colors.white,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: status.color.withOpacity(0.3)),
              ),
              child: Icon(status.icon, color: status.color, size: 40),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: status.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: status.color.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.store,
                        size: 16,
                        color: status.color.withOpacity(0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(openPct * 100).toStringAsFixed(1)}% open',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: status.color.withOpacity(0.85),
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
    );
  }
}

class MapSummaryBar extends StatelessWidget {
  final StatusInfo status;
  final WHIResult result;
  final double radius;
  final bool isLoading;

  const MapSummaryBar({
    super.key,
    required this.status,
    required this.result,
    required this.radius,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Color.alphaBlend(status.color.withOpacity(0.08), Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(status.icon, color: status.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${(result.openPct * 100).toStringAsFixed(1)}% open within ${radius.toInt()} mi',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: status.color,
                    ),
                  ),
                ),
                Text(
                  '${result.openCount} open',
                  style: TextStyle(color: status.color.withOpacity(0.9)),
                ),
                const SizedBox(width: 8),
                Text(
                  '${result.closedCount} closed',
                  style: TextStyle(color: status.color.withOpacity(0.9)),
                ),
              ],
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class StatusInfo {
  final Color color;
  final IconData icon;
  final String title;
  final String description;

  const StatusInfo({
    required this.color,
    required this.icon,
    required this.title,
    required this.description,
  });
}

StatusInfo statusInfoFor(double openPct) {
  if (openPct >= 0.95) {
    return const StatusInfo(
      color: Colors.green,
      icon: Icons.check_circle,
      title: 'All Clear',
      description: 'Normal operations - minimal impact',
    );
  }
  if (openPct >= 0.80) {
    return const StatusInfo(
      color: Colors.lightGreen,
      icon: Icons.check_circle_outline,
      title: 'Minor Impact',
      description: 'Some locations affected',
    );
  }
  if (openPct >= 0.60) {
    return const StatusInfo(
      color: Colors.orange,
      icon: Icons.warning_amber,
      title: 'Moderate Alert',
      description: 'Significant regional impact',
    );
  }
  if (openPct >= 0.40) {
    return const StatusInfo(
      color: Colors.deepOrange,
      icon: Icons.warning,
      title: 'Severe Alert',
      description: 'Major disaster conditions',
    );
  }
  return const StatusInfo(
    color: Colors.red,
    icon: Icons.dangerous,
    title: 'Critical Alert',
    description: 'Catastrophic conditions',
  );
}

List<Widget> buildLocationCards(List<LocationDetail> locations) {
  return locations
      .map(
        (loc) => Card(
          child: ListTile(
            leading: Icon(
              loc.status == 'Open' ? Icons.check_circle : Icons.cancel,
              color: loc.status == 'Open' ? Colors.green : Colors.red,
            ),
            title: Text(loc.name ?? 'Waffle House #${loc.id}'),
            subtitle: Text(
              '${loc.city ?? ''} ${loc.state ?? ''} - ${loc.distanceMiles?.toStringAsFixed(1) ?? '?'} mi',
            ),
            trailing: Text(loc.status),
          ),
        ),
      )
      .toList();
}

double zoomForRadius(double radius) {
  if (radius <= 10) return 12.0;
  if (radius <= 25) return 10.5;
  if (radius <= 50) return 9.5;
  if (radius <= 100) return 8.5;
  if (radius <= 250) return 7.0;
  return 5.5;
}

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
