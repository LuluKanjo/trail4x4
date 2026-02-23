import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';

class POI {
  final LatLng position;
  final String name;
  final String type;
  POI({required this.position, required this.name, required this.type});
}

class POIService {
  final String tomtomKey;
  POIService({this.tomtomKey = ''});

  Future<List<POI>> fetchPOIs(double lat, double lon, String type) async {
    if (type == 'fuel') {
      return _fetchFuelTomTom(lat, lon);
    } else if (type == 'water') {
      return _fetchOSM(lat, lon,
          '[out:json];(node["amenity"="drinking_water"](around:10000,$lat,$lon);node["natural"="spring"](around:10000,$lat,$lon););out;',
          'water');
    } else if (type == 'camp') {
      return _fetchOSM(lat, lon,
          '[out:json];(node["tourism"="camp_site"](around:20000,$lat,$lon);node["tourism"="wilderness_hut"](around:20000,$lat,$lon););out;',
          'camp');
    }
    return [];
  }

  Future<List<POI>> _fetchFuelTomTom(double lat, double lon) async {
    try {
      final url =
          'https://api.tomtom.com/search/2/poiSearch/station%20essence.json?lat=$lat&lon=$lon&radius=10000&limit=50&categorySet=7311&key=$tomtomKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<POI> pois = [];
        for (final result in data['results']) {
          final name = result['poi']?['name'] ?? 'Station essence';
          final position = result['position'];
          pois.add(POI(
            position: LatLng(position['lat'].toDouble(), position['lon'].toDouble()),
            name: name,
            type: 'fuel',
          ));
        }
        return pois;
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  Future<List<POI>> _fetchOSM(double lat, double lon, String query, String type) async {
    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<POI> pois = [];
        for (final element in data['elements']) {
          final name = element['tags']?['name'] ?? _defaultName(type);
          pois.add(POI(
            position: LatLng(element['lat'].toDouble(), element['lon'].toDouble()),
            name: name,
            type: type,
          ));
        }
        return pois;
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  String _defaultName(String type) {
    switch (type) {
      case 'water': return 'Point eau';
      case 'camp': return 'Bivouac';
      default: return 'POI';
    }
  }
}
