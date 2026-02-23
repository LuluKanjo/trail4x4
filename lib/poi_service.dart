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
  Future<List<POI>> fetchPOIs(double lat, double lon, String type) async {
    String query = '';
    if (type == 'fuel') {
      query = '[out:json];node["amenity"="fuel"](around:10000,$lat,$lon);out;';
    } else if (type == 'water') {
      query = '[out:json];(node["amenity"="drinking_water"](around:10000,$lat,$lon);node["natural"="spring"](around:10000,$lat,$lon););out;';
    } else if (type == 'camp') {
      query = '[out:json];(node["tourism"="camp_site"](around:20000,$lat,$lon);node["tourism"="wilderness_hut"](around:20000,$lat,$lon););out;';
    }
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
      case 'fuel': return 'Station essence';
      case 'water': return 'Point eau';
      case 'camp': return 'Bivouac';
      default: return 'POI';
    }
  }
}
