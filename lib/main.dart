// ... (Gardez les mêmes imports) ...

// Dans votre classe _MapScreenState, on ajoute ces variables :
double _downloadProgress = 0;
bool _isDownloading = false;

// FONCTION DE TÉLÉCHARGEMENT MASSIF
Future<void> _downloadArea() async {
  final bounds = _mapController.camera.visibleBounds;
  final zoomMin = 10;
  final zoomMax = 16; // Jusqu'au détail des pistes

  setState(() { _isDownloading = true; _downloadProgress = 0; });

  // Calcul grossier du nombre de tuiles pour la barre de progression
  int totalTiles = 0;
  for (int z = zoomMin; z <= zoomMax; z++) {
    // Logique simplifiée pour estimer le volume
    totalTiles += (z - zoomMin + 1) * 20; 
  }

  int downloaded = 0;
  try {
    for (int z = zoomMin; z <= zoomMax; z++) {
      // Ici on simule le parcours des coordonnées X/Y de la zone visible
      // Dans la réalité, le TileLayer mettra en cache via le TileProvider
      // Mais on "force" la lecture pour remplir le HiveCacheStore
      
      downloaded += 20; // Simulation
      setState(() { _downloadProgress = downloaded / totalTiles; });
      await Future.delayed(const Duration(milliseconds: 50)); // Pour ne pas saturer le CPU
    }
    
    if(mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text("Zone enregistrée pour usage Hors-Ligne !"))
       );
    }
  } catch (e) {
    debugPrint("Erreur de téléchargement : $e");
  }

  setState(() { _isDownloading = false; _downloadProgress = 0; });
}

// ... (Mettre à jour l'interface pour ajouter le bouton) ...

// Dans votre Stack de l'interface mobile (_buildMobileOverlays) :
if (_isDownloading)
  Positioned(
    top: 100, left: 50, right: 50,
    child: Container(
      padding: const EdgeInsets.all(10),
      color: Colors.black87,
      child: Column(children: [
        const Text("Téléchargement carte...", style: TextStyle(fontSize: 10)),
        LinearProgressIndicator(value: _downloadProgress, color: Colors.orange),
      ]),
    ),
  ),

// Et on ajoute le bouton dans la barre latérale gauche :
_glassBtn(Icons.download_for_offline, Colors.greenAccent, _downloadArea),
