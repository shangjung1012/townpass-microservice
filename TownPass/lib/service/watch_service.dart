import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'notification_service.dart';

class WatchedPlace {
  final String id;
  final String name;
  final double lon;
  final double lat;
  DateTime? lastChecked;
  int? lastConstructionCount;

  WatchedPlace({
    required this.id,
    required this.name,
    required this.lon,
    required this.lat,
    this.lastChecked,
    this.lastConstructionCount,
  });
}

class WatchService extends GetxService {
  final Map<String, WatchedPlace> _watchedPlaces = {};
  Timer? _periodicTimer;
  List<dynamic>? _constructionData;

  Future<WatchService> init() async {
    // 載入施工資料
    await _loadConstructionData();
    
    // 啟動 5 分鐘定時檢查
    _startPeriodicCheck();
    
    return this;
  }

  Future<void> _loadConstructionData() async {
    try {
      // 從前端 web server 載入施工資料（假設在同一 origin）
      final response = await http.get(Uri.parse('/mapData/construction.geojson'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['features'] is List) {
          _constructionData = data['features'];
        }
      }
    } catch (e) {
      print('Failed to load construction data: $e');
      _constructionData = [];
    }
  }

  void _startPeriodicCheck() {
    // 每 5 分鐘檢查一次
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkAllWatchedPlaces();
    });
  }

  Future<void> _checkAllWatchedPlaces() async {
    if (_watchedPlaces.isEmpty) return;

    try {
      // 取得目前位置（用來判斷使用者是否靠近監控地點）
      Position? currentPosition;
      try {
        currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        print('Failed to get current position: $e');
      }

      for (final place in _watchedPlaces.values) {
        await _checkPlace(place, currentPosition);
      }
    } catch (e) {
      print('Error checking watched places: $e');
    }
  }

  Future<void> _checkPlace(WatchedPlace place, Position? userPosition) async {
    // 如果有使用者位置，檢查是否距離監控地點超過 10 公里（避免無關通知）
    if (userPosition != null) {
      final distanceToPlace = _calculateDistance(
        userPosition.latitude,
        userPosition.longitude,
        place.lat,
        place.lon,
      );
      // 如果使用者距離監控地點超過 10 公里，跳過檢查
      if (distanceToPlace > 10000) {
        return;
      }
    }

    // 計算監控地點 1 公里內的施工地點數量
    final constructionCount = _countNearbyConstruction(place.lon, place.lat);

    // 更新檢查時間
    place.lastChecked = DateTime.now();

    // 如果數量有變化或是第一次檢查且有施工，發送通知
    final shouldNotify = (place.lastConstructionCount == null && constructionCount > 0) ||
        (place.lastConstructionCount != null && place.lastConstructionCount != constructionCount);

    if (shouldNotify && constructionCount > 0) {
      await NotificationService.showNotification(
        title: '${place.name} 附近施工資訊',
        content: '一公里內有 $constructionCount 個地點在施工',
      );
    }

    place.lastConstructionCount = constructionCount;
  }

  int _countNearbyConstruction(double centerLon, double centerLat) {
    if (_constructionData == null) return 0;

    int count = 0;
    const maxDistance = 1000.0; // 1 公里

    for (final feature in _constructionData!) {
      try {
        final geometry = feature['geometry'];
        if (geometry == null || geometry['type'] != 'Point') continue;

        final coordinates = geometry['coordinates'] as List;
        if (coordinates.length < 2) continue;

        final lon = (coordinates[0] as num).toDouble();
        final lat = (coordinates[1] as num).toDouble();

        final distance = _calculateDistance(centerLat, centerLon, lat, lon);
        if (distance <= maxDistance) {
          count++;
        }
      } catch (e) {
        continue;
      }
    }

    return count;
  }

  /// 計算兩點距離（Haversine 公式，單位：公尺）
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // 地球半徑（公尺）
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  /// 新增監控地點
  void addWatch({
    required String id,
    required String name,
    required double lon,
    required double lat,
  }) {
    _watchedPlaces[id] = WatchedPlace(
      id: id,
      name: name,
      lon: lon,
      lat: lat,
    );
    
    // 立即檢查一次（非同步，不阻塞）
    Future.microtask(() async {
      try {
        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 3),
          );
        } catch (_) {
          pos = null;
        }
        await _checkPlace(_watchedPlaces[id]!, pos);
      } catch (_) {}
    });
  }

  /// 移除監控地點
  void removeWatch(String id) {
    _watchedPlaces.remove(id);
  }

  /// 取得所有監控地點
  List<WatchedPlace> get watchedPlaces => _watchedPlaces.values.toList();

  @override
  void onClose() {
    _periodicTimer?.cancel();
    super.onClose();
  }
}
