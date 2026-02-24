import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class POI {
  final String name, type;
  final LatLng position;
  POI({required this.name, required this.type, required this.position});
}

class POIService {
  final String tomtomKey;
  POIService({required this.tomtomKey});

  Future<List<POI>> fetchPOIs(double lat, double lon, String type) async {
    if (type == 'fuel') {
      final url = 'https://api.tomtom.com/search/2/search/petrol station.json?lat=$lat&lon=$lon&radius=30000&key=$tomtomKey';
      try {
        final res = await http.get(Uri.parse(url));
        final data = json.decode(res.body);
        final List results = data['results'] ?? [];
        return results.map((r) => POI(name: r['poi']['name'] ?? 'Station', type: type, position: LatLng(r['position']['lat'], r['position']['lon']))).toList();
      } catch (e) { return []; }
    } else {
      // UTILISATION D'OVERPASS POUR L'EAU ET LE BIVOUAC (Précision Pampa)
      String query = type == 'water' 
        ? '[out:json];node(around:20000,$lat,$lon)["amenity"~"drinking_water|water_point"];out;'
        : '[out:json];node(around:20000,$lat,$lon)["tourism"~"camp_site|picnic_site"];out;';
      
      try {
        final res = await http.get(Uri.parse('https://overpass-api.de/api/interpreter?data=$query'));
        final data = json.decode(res.body);
        final List elements = data['elements'] ?? [];
        return elements.map((e) => POI(
          name: e['tags']['name'] ?? (type == 'water' ? 'Point d\'eau' : 'Bivouac/Pique-nique'),
          type: type,
          position: LatLng(e['lat'], e['lon']),
        )).toList();
      } catch (e) { return []; }
    }
  }
}
