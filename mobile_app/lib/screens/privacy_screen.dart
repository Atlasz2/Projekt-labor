import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Adatkezelési tájékoztató (GDPR 13. cikk). A tartalom a rendszer tényleges
/// működését írja le; az adatkezelő azonosító adatai kiadásonként, build-
/// időben adhatók meg (lásd [AppConfig.privacyController] és docs/LAUNCH.md).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controllerKnown = AppConfig.privacyController.isNotEmpty;

    Widget section(String title, List<String> paragraphs) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(p, style: const TextStyle(height: 1.45)),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Adatkezelési tájékoztató')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          section('Az adatkezelő', [
            controllerKnown
                ? AppConfig.privacyController
                : 'Az adatkezelő adatai az alkalmazás hivatalos kiadásában '
                      'szerepelnek.',
            if (AppConfig.privacyEmail.isNotEmpty)
              'Kapcsolat: ${AppConfig.privacyEmail}',
          ]),
          section('Milyen adatot kezelünk, és miért?', [
            '• A megadott név: a fiók azonosítására és a ranglistán való '
                'megjelenítésre. A név a ranglistán mások számára is látható.',
            '• Az e-mail-cím (csak ha megadod): a fiók másik eszközön való '
                'visszaállítására. Nem jelenik meg mások számára.',
            '• A játékbeli haladás: a beolvasott állomások és rendezvények, '
                'a beolvasás időpontja, a pontszám, a teljesített túrák és a '
                'jutalmak – a pontgyűjtés működéséhez.',
            '• A hibabejelentések szövege és a hozzájuk csatolt név, e-mail, '
                'platform és alkalmazásverzió – a hiba kivizsgálásához és a '
                'válaszadáshoz.',
          ]),
          section('Helymeghatározás', [
            'A QR-kód beolvasásakor az alkalmazás lekéri a telefon '
                'pozícióját, és a kóddal együtt elküldi a szervernek, amely '
                'ebből ellenőrzi, hogy az állomás közelében vagy-e. A pozíciót '
                'a szerver nem tárolja. Ha a beolvasás internet nélkül történik, '
                'a pozíció a jóváírásig csak a telefonodon marad.',
            'A helymeghatározást megtagadhatod; ilyenkor a legtöbb állomás '
                'továbbra is beváltható, de amelyeknél a település ezt '
                'előírja, ott pont nem jár.',
          ]),
          section('Igénybe vett szolgáltatások', [
            'Az adatokat a Google Firebase szolgáltatásai tárolják és '
                'dolgozzák fel (hitelesítés, adatbázis, szerveroldali '
                'függvények az EU-ban, push-értesítés, hibanaplózás és '
                'teljesítménymérés). A hibanaplózás az alkalmazás összeomlásakor '
                'a hiba technikai adatait és az eszköz típusát küldi el.',
            'A térképet a Google Maps, a letölthető térképcsempéket a CARTO '
                'szolgáltatja. A gyalogos útvonal számításához az állomások '
                '(nem a te) koordinátái kerülnek a BRouter, Valhalla, illetve '
                'OSRM útvonaltervezőhöz.',
          ]),
          section('Meddig őrizzük?', [
            'Az adataidat a fiókod törléséig őrizzük. Törléskor minden '
                'hozzád kötött adat törlődik; a hibabejelentéseid szövege '
                'névtelenítve megmaradhat, mert a hiba javításához szükséges, '
                'de már nem köthető hozzád.',
          ]),
          section('A jogaid', [
            'A Profil → „Adataim és adatvédelem” részben bármikor letöltheted '
                'minden adatodat géppel olvasható (JSON) formában, és '
                'törölheted a fiókodat. A neved a profilban módosíthatod.',
            'Kérheted az adataid helyesbítését, kezelésük korlátozását, '
                'és panaszt tehetsz a Nemzeti Adatvédelmi és '
                'Információszabadság Hatóságnál (NAIH).',
          ]),
        ],
      ),
    );
  }
}
