import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteData {
  final List<LatLng> points;
  final double distance;
  RouteData(this.points, this.distance);
}

class RoutingService {
  RoutingService(String _); 

  Future<RouteData?> getOffRoadRoute(LatLng start, LatLng dest, List<LatLng> forbiddenZones) async {
    // On prépare tes zones interdites posées à la main (points rouges)
    final String noGo = forbiddenZones.map((p) => '${p.longitude},${p.latitude},50').join('|');

    // ON UTILISE LE PROFIL OFFICIEL 'trekking' DU SERVEUR
    // Il est programmé pour fuir les routes et privilégier la nature et la terre.
    final queryParams = {
      'lonlats': '${start.longitude},${start.latitude}|${dest.longitude},${dest.latitude}',
      'profile': 'trekking', 
      'alternativeidx': '0',
      'format': 'geojson',
    };
    
    // On ajoute tes interdictions manuelles si tu en as posé
    if (noGo.isNotEmpty) queryParams['nogo'] = noGo;

    final url = Uri.parse('https://brouter.de/brouter').replace(queryParameters: queryParams);
    
    try {
      final response = await http.get(url);
      
      // Si le serveur répond bien (code 200)
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // On vérifie qu'un tracé a bien été trouvé
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final coords = feature['geometry']['coordinates'] as List;
          final double dist = double.tryParse(feature['properties']['track-length'].toString()) ?? 0.0;
          
          return RouteData(coords.map((p) => LatLng(p[1], p[0])).toList(), dist);
        }
      } else {
        print('Erreur serveur BRouter: ${response.statusCode}');
      }
    } catch (e) { 
      print('Erreur connexion: $e'); 
    }
    
    // Si on arrive ici, c'est qu'il n'y a vraiment aucun chemin (ou une rivière à traverser sans pont)
    return null; 
  }
}
