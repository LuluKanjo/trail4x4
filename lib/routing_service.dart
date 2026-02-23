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
      "ch.disable": true, // Désactive le cache rapide pour utiliser notre recette
      "custom_model": {
        // Autorise de plus longs détours géographiques pour trouver de la piste (défaut: 70)
        "distance_influence": 40,
        "priority": [
          // On fuit les autoroutes et voies rapides
          { "if": "road_class == MOTORWAY || road_class == TRUNK", "multiply_by": 0.05 },
          // L'asphalte reste possible pour les liaisons, mais fortement pénalisé face à la terre
          { "if": "surface == ASPHALT || surface == PAVED || surface == CONCRETE", "multiply_by": 0.3 },
          // On traverse moins les lotissements et zones résidentielles
          { "if": "road_class == RESIDENTIAL", "multiply_by": 0.6 }
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
        return RouteData([start, dest], [{'text': 'ERREUR API: ${response.statusCode} - ${response.body}', 'interval': [0, 1]}]);
      }
    } catch (e) {
      return RouteData([start, dest], [{'text': 'CRASH INTERNE: $e', 'interval': [0, 1]}]);
    }
    return null;
  }
}
