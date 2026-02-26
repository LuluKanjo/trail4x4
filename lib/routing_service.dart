import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class RouteData {
  final List<LatLng> points;
  final double distance;
  RouteData(this.points, this.distance);
}

class RoutingService {
  final String apiKey;
  RoutingService(this.apiKey);

  Future<RouteData?> getOffRoadRoute(List<LatLng> waypoints, List<LatLng> forbiddenZones, {bool isOffRoad = true}) async {
    if (waypoints.length < 2) return null;

    final profile = isOffRoad ? 'cycling-mountain' : 'driving-car';
    final coordinates = waypoints.map((p) => [p.longitude, p.latitude]).toList();
    final url = Uri.parse('https://api.openrouteservice.org/v2/directions/$profile/geojson');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': apiKey.isNotEmpty ? apiKey : '5b3ce3597851110001cf624838380e92751f498991443653134e6e66', 
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: json.encode({
          "coordinates": coordinates,
          "instructions": false,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coords = data['features'][0]['geometry']['coordinates'];
        
        // Sécurité de conversion absolue pour éviter les crashs de tracé
        final double dist = (data['features'][0]['properties']['summary']['distance'] as num).toDouble();
        
        return RouteData(
          coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList(),
          dist
        );
      } else {
        debugPrint("Erreur ORS: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("Erreur Routing: $e");
      return null;
    }
  }
}
