import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/station.dart';
import '../models/point_content.dart';

final List<Station> mockStations = [
  Station(
    id: 'kinizsi_var',
    tripId: 1,
    name: 'Kinizsi-vár',
    location: const LatLng(46.9890, 17.6990),
    description: 'A nagyvázsonyi vár a település egyik legjelentősebb műemléke, amelyet a 15. században építtetett a Vezsenyi család. Legismertebb birtokosa Kinizsi Pál volt, aki 1472-ben kapta meg Mátyás királytól. A vár ma múzeumként működik, bemutatja a középkori várélet emlékeit és Kinizsi Pál történetét.',
    qrCode: 'kinizsi_var_qr',
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/Nagyv%C3%A1zsony_-_V%C3%A1r.jpg/800px-Nagyv%C3%A1zsony_-_V%C3%A1r.jpg',
    contents: [
      PointContent(
        id: 1,
        pointOfInterestId: 1,
        contentType: 'text',
        textContent: 'Fun fact: Kinizsi Pál, a legendás hadvezér állítólag egy malomkővel mutatta meg erejét Mátyás királynak, ami után a király szolgálatába fogadta.',
      ),
    ],
  ),
  Station(
    id: 'palos_kolostor',
    tripId: 1,
    name: 'Szent Mihály Pálos Kolostor',
    location: const LatLng(46.9857, 17.6893),
    description: 'A kolostort 1478-ban alapította Kinizsi Pál és Magyar Balázs. A pálos rend egyik jelentős központja volt, ahol értékes kódexek is készültek.',
    qrCode: 'palos_kolostor_qr',
    imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/6/65/Nagyvazsony_palosok.jpg/800px-Nagyvazsony_palosok.jpg',
    contents: [
      PointContent(
        id: 2,
        pointOfInterestId: 2,
        contentType: 'text',
        textContent: 'Fun fact: A kolostorban készült a Festetich-kódex és a Czech-kódex, amelyek Kinizsi Pál feleségének, Magyar Benignának az imádságos könyvei voltak. Ezek a magyar nyelv értékes nyelvemlékei.',
      ),
    ],
  ),
  Station(
    id: 'talodi_kolostor',
    tripId: 1,
    name: 'Tálodi Kolostor Rom',
    location: const LatLng(46.9715, 17.6827),
    description: 'A Tálodi kolostor romjai a Bakony erdejében találhatók. A pálos rendi kolostort a 14. században alapították, és a török időkig működött.',
    qrCode: 'talodi_kolostor_qr',
    imageUrl: 'https://www.bacterial.hu/kepek/csunya_helyek/talod.jpg',
    contents: [
      PointContent(
        id: 3,
        pointOfInterestId: 3,
        contentType: 'text',
        textContent: 'Fun fact: A kolostor romjai között megtalálható még az egykori templom szentélyének falmaradványa, amely jól mutatja a középkori építészet jellegzetességeit.',
      ),
    ],
  ),
  Station(
    id: 'szent_istvan_templom',
    tripId: 1,
    name: 'Szent István Király Templom',
    location: const LatLng(46.9882, 17.6995),
    description: 'A barokk stílusú római katolikus templom 1771-1776 között épült. A templom elődjét még Szent István király alapította, de az évszázadok során többször átépítették.',
    qrCode: 'szent_istvan_templom_qr',
    imageUrl: 'https://miserend.hu/uploaded/gallery/1/1668/800x600/nagyvazsonyi-romai-katolikus-templom.jpg',
    contents: [
      PointContent(
        id: 4,
        pointOfInterestId: 4,
        contentType: 'text',
        textContent: 'Fun fact: A templom főoltárképe Szent István király alakját ábrázolja, amint a koronát felajánlja Szűz Máriának. A templomban található egy 18. századi keresztelőkút is.',
      ),
    ],
  ),
];