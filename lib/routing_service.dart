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

    // ON PASSE SUR LE SERVEUR PUBLIC OSRM (100% Gratuit, sans clé API, ultra-fiable)
    final coordsString = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url = Uri.parse('http://router.project-osrm.org/route/v1/driving/$coordsString?overview=full&geometries=geojson');
    
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List coords = data['routes'][0]['geometry']['coordinates'];
          final double dist = (data['routes'][0]['distance'] as num).toDouble();
          
          return RouteData(
            coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList(),
            dist
          );
        }
      }
      debugPrint("Erreur OSRM: ${response.statusCode} - ${response.body}");
      return null;
    } catch (e) {
      debugPrint("Panne totale de routage: $e");
      return null;
    }
  }
}
