import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart'; // Ajout pour debugPrint

class RouteData {
  final List<LatLng> points;
  final double distance;
  RouteData(this.points, this.distance);
}

class RoutingService {
  final String apiKey;
  RoutingService(this.apiKey);

  Future<RouteData?> getOffRoadRoute(List<LatLng> waypoints, List<LatLng> forbiddenZones, {bool isOffRoad = true}) async {
    final profile = isOffRoad ? 'cycling-mountain' : 'driving-car';
    final coordinates = waypoints.map((p) => [p.longitude, p.latitude]).toList();
    final url = Uri.parse('https://api.openrouteservice.org/v2/directions/$profile/geojson');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': '5b3ce3597851110001cf624838380e92751f498991443653134e6e66', 
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "coordinates": coordinates,
          "instructions": false,
          "preference": "fastest",
          "units": "m"
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coords = data['features'][0]['geometry']['coordinates'];
        final double dist = data['features'][0]['properties']['summary']['distance'];
        
        return RouteData(
          coords.map((c) => LatLng(c[1], c[0])).toList(),
          dist
        );
      }
    } catch (e) {
      debugPrint("Erreur Routing: $e"); // Changé print en debugPrint
    }
    return null;
  }
}
