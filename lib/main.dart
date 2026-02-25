// ... (garder tous les imports identiques) ...

// Dans ta classe _MapScreenState, ajoute ces 2 variables de lissage :
double _smoothLat = 0, _smoothLon = 0;
final double _alpha = 0.20; // Plus c'est bas (ex: 0.1), plus c'est fluide mais lent. 0.2 est idéal pour le 4x4.

void _startTracking() async {
  await Geolocator.requestPermission();
  
  // NOUVELLES RÉGLAGES DE HAUTE PRÉCISION
  final locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0, // On veut TOUTES les données sans filtre
    intervalDuration: const Duration(milliseconds: 500), // Rafraîchissement 2 fois par seconde
    forceLocationManager: true, // Utilise le vrai GPS plutôt que le Wi-Fi (vital en forêt)
  );

  Geolocator.getPositionStream(locationSettings: locationSettings)
  .listen((pos) {
    if (!mounted) return;

    // ALGORITHME DE LISSAGE (LOW-PASS FILTER)
    // Au lieu de sauter, on fait une moyenne pondérée entre l'ancienne et la nouvelle position.
    if (_smoothLat == 0) {
      _smoothLat = pos.latitude;
      _smoothLon = pos.longitude;
    } else {
      _smoothLat = (_alpha * pos.latitude) + ((1 - _alpha) * _smoothLat);
      _smoothLon = (_alpha * pos.longitude) + ((1 - _alpha) * _smoothLon);
    }

    setState(() {
      _currentPos = LatLng(_smoothLat, _smoothLon);
      _speed = pos.speed * 3.6;
      _alt = pos.altitude;
      _head = pos.heading;
      
      if (_lastPos != null) {
        _tripDistance += const Distance().as(LengthUnit.Meter, _lastPos!, _currentPos);
      }
      _lastPos = _currentPos;
      if (_isRec) _trace.add(_currentPos);
      if (_route.isNotEmpty) _remDist = const Distance().as(LengthUnit.Meter, _currentPos, _route.last);
    });
    
    // Suivi caméra fluide
    if (_follow) {
      _mapController.move(_currentPos, _isNavigating ? 17.5 : _mapController.camera.zoom);
      if (_isNavigating && _speed > 1.0) _mapController.rotate(360 - _head);
    }
  });
}

// ... (copie le reste du fichier main.dart tel quel) ...
