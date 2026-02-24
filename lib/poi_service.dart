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
    // On utilise des mots-clés plus larges pour l'eau et le bivouac
    String query = '';
    if (type == 'fuel') query = 'petrol station';
    else if (type == 'water') query = 'water tap, drinking water, fountain';
    else if (type == 'camp') query = 'campground, wild camping';

    final url = 'https://api.tomtom.com/search/2/search/$query.json?lat=$lat&lon=$lon&radius=30000&key=$tomtomKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((r) => POI(
          name: r['poi']['name'] ?? (type == 'water' ? 'Point Eau' : 'Lieu'),
          type: type,
          position: LatLng(r['position']['lat'], r['position']['lon']),
        )).toList();
      }
    } catch (e) { print('Erreur POI: $e'); }
    return [];
  }
}
