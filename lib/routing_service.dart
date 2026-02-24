import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteData {
  final List<LatLng> points;
  final double distance;
  RouteData(this.points, this.distance);
}

class RoutingService {
  final String apiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjBjZjIwMTNiNzhmODQwZDZhOGExMGE5MWFlMWFiYmM5IiwiaCI6Im11cm11cjY0In0=';

  RoutingService(String _); 

  List<List<double>> _createForbiddenBox(LatLng center) {
    double d = 0.0005; // Zone de contournement d'environ 50m
    return [
      [center.longitude - d, center.latitude - d],
      [center.longitude + d, center.latitude - d],
      [center.longitude + d, center.latitude + d],
      [center.longitude - d, center.latitude + d],
      [center.longitude - d, center.latitude - d]
    ];
  }

  Future<RouteData?> getOffRoadRoute(List<LatLng> waypoints, List<LatLng> forbiddenZones) async {
    if (waypoints.length < 2) return null;

    final url = Uri.parse('https://api.openrouteservice.org/v2/directions/cycling-mountain/geojson');

    List<List<double>> coords = waypoints.map((p) => [p.longitude, p.latitude]).toList();

    Map<String, dynamic> body = {
      "coordinates": coords,
      "elevation": false,
      "instructions": false
    };

    if (forbiddenZones.isNotEmpty) {
      body["options"] = {
        "avoid_polygons": {
          "type": "MultiPolygon",
          "coordinates": [
            for (var zone in forbiddenZones)
              [ _createForbiddenBox(zone) ]
          ]
        }
      };
    }

    try {
      final response = await http.post(
        url,
        headers: {
          'Accept': 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8',
          'Authorization': apiKey,
          'Content-Type': 'application/json; charset=utf-8'
        },
        body: json.encode(body)
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final geometry = feature['geometry']['coordinates'] as List;
          
          double dist = 0.0;
          final props = feature['properties']['segments'] as List?;
          if (props != null) {
            for (var seg in props) {
              dist += (seg['distance'] ?? 0.0);
            }
          }

          List<LatLng> routePoints = [];
          for (var p in geometry) {
            routePoints.add(LatLng(p[1], p[0]));
          }
          
          return RouteData(routePoints, dist);
        }
      } else {
        debugPrint("Erreur ORS: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("Erreur réseau ORS: $e");
    }
    return null; 
  }
}
