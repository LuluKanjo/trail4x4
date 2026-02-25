import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class POI {
  final LatLng position;
  final String type;
  final String name;

  POI(this.position, this.type, this.name);
}

class POIService {
  // On garde tomtomKey dans les paramètres pour ne pas faire planter main.dart
  // mais on ne s'en sert plus ! On passe au 100% Gratuit/OpenSource.
  POIService({String? tomtomKey});

  Future<List<POI>> fetchPOIs(double lat, double lon, String type) async {
    List<POI> results = [];
    
    // Traduction de nos boutons en langage OpenStreetMap
    String osmTag = '';
    if (type == 'gas') osmTag = '["amenity"="fuel"]';
    if (type == 'water') osmTag = '["amenity"="drinking_water"]';
    
    // On lance un scan radar sur un rayon de 15 km (15000 mètres)
    String query = '''
      [out:json][timeout:15];
      (
        node$osmTag(around:15000,$lat,$lon);
        way$osmTag(around:15000,$lat,$lon);
      );
      out center;
    ''';

    try {
      // Appel au serveur mondial public Overpass
      final url = Uri.parse('https://overpass-api.de/api/interpreter');
      final response = await http.post(url, body: query);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        for (var element in data['elements']) {
          // Gère les points (node) et les bâtiments (way)
          double pLat = element['type'] == 'node' ? element['lat'] : element['center']['lat'];
          double pLon = element['type'] == 'node' ? element['lon'] : element['center']['lon'];
          String name = element['tags']?['name'] ?? (type == 'gas' ? 'Station Essence' : 'Point d\'eau');
          
          results.add(POI(LatLng(pLat, pLon), type, name));
        }
      }
    } catch (e) {
      debugPrint("Erreur Radar POI: $e");
    }
    
    return results;
  }
}
