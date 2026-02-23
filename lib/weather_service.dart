import 'package:http/http.dart' as http;
import 'dart:convert';

class WeatherService {
  final String apiKey;
  WeatherService(this.apiKey);

  Future<Map<String, dynamic>?> getWeather(double lat, double lon) async {
    try {
      final url =
          'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=fr';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
