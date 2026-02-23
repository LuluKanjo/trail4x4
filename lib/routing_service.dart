import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteData {
  final List<LatLng> points;
  final List<dynamic> instructions;
  RouteData(this.points, this.instructions);
}

class RoutingService {
  final String apiKey;
  
  RoutingService(this.apiKey);

  Future<RouteData?> getOffRoadRoute(LatLng start, LatLng dest) async {
    final url = 'https://graphhopper.com/api/1/route?key=$apiKey';
    
    // Le secret est ici : on force la recherche de terre et on fuit l'asphalte
    final body = json.encode({
      "points": [
        [start.longitude, start.latitude],
        [dest.longitude, dest.latitude]
      ],
      "profile": "car",
      "locale": "fr",
      "instructions": true,
      "elevation": false,
      "points_encoded": false,
      "ch.disable": true, // Obligatoire pour utiliser le modèle sur mesure
      "custom_model": {
        "distance_influence": 70,
        "priority": [
          { "if": "road_class == MOTORWAY || road_class == TRUNK", "multiply_by": 0.0 },
          { "if": "surface == ASPHALT || surface == PAVED || surface == CONCRETE", "multiply_by": 0.1 }
        ]
      }
    });

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: body,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['paths'] != null && data['paths'].isNotEmpty) {
          final paths = data['paths'][0];
          final coords = paths['points']['coordinates'] as List;
          final points = coords.map((p) => LatLng(p[1], p[0])).toList();
          final instructions = paths['instructions'] as List<dynamic>;
          return RouteData(points, instructions);
        }
      } else {
        print('Erreur API GraphHopper: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Erreur Routing: $e');
    }
    return null;
  }
}
