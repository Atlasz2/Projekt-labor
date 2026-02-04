# Szakirodalmi Áttekintés

## 1. Turisztikai és Kulturális Mobilalkalmazások

### 1.1 Szakirodalmi források

#### Mobilalkalmazások a turizmusban
- **Brown, B., & Chalmers, M. (2003)**: Tourism and mobile technology
  - A helymeghatározás és kontextus-érzékeny tartalmak fontossága
  - Turisztikai élmények digitális bővítése

- **Gretzel, U., et al. (2015)**: Smart tourism
  - Okoseszközök integrációja a turisztikai élményekbe
  - Valós idejű információk jelentősége

#### Gamifikáció és interaktivitás
- **Xu, F., et al. (2017)**: Gamification in tourism
  - Játékosítási elemek motivációs hatása turistáknál
  - Gyűjtögetés és achievement rendszerek

### 1.2 Alkalmazás példák

#### Geocaching alkalmazások
- **Munzee, Geocaching.com**: GPS-alapú kincsvadászat
- Fizikai helyszínek felfedezése
- Közösségi elemek és pontrendszer

#### Kulturális örökség appok
- **Google Arts & Culture**: Múzeumok és műemlékek digitális felfedezése
- **izi.TRAVEL**: Audió túrák és múzeum útmutatók
- Multimédiás tartalom (hang, kép, videó)

## 2. QR-kód Alapú Ismeretterjesztés

### 2.1 QR technológia

#### Alapvető működés
- **ISO/IEC 18004:2015** szabvány
- 2D mátrix kód, nagy adattárolási kapacitás
- Hibatűrés (7-30% hibajavítás Reed-Solomon algoritmussal)

#### QR-kódok előnyei turisztikai környezetben
- **Gyors hozzáférés**: Azonnali információ mobileszközön
- **Offline működés**: URL-ek, szöveges tartalom tárolása
- **Költséghatékonyság**: Olcsó előállítás és telepítés
- **Univerzális olvashatóság**: Minden okostelefon támogatja

### 2.2 Szakirodalmi támogatás

- **Ceipidor, U. B., et al. (2009)**: Mobile museum applications with QR codes
  - QR-kódok múzeumi környezetben történő használata
  - Látogatói élmény fokozása interaktív tartalommal

- **Ozcelik, E., & Acarturk, C. (2011)**: Reducing cognitive load in multimedia learning
  - Mobil eszközökön történő tanulás optimalizálása
  - Chunk-olás és fokozatos információközlés

- **So, S. (2011)**: QR code application in tourism
  - Turisztikai információk nyújtása QR-kódon keresztül
  - Késleltetett információközlés elkerülése

### 2.3 Implementációs szempontok

#### QR-kód típusok
1. **URL QR-kódok**: Webes tartalom linkje
2. **Text QR-kódok**: Szöveges információ
3. **vCard QR-kódok**: Kapcsolati információk
4. **Egyedi azonosítók**: Állomás-specifikus ID-k

#### Best practice-ek
- **Méret**: Minimum 2×2 cm nyomtatásban
- **Kontraszt**: Magas kontraszt a háttérrel
- **Hibajavítás**: Legalább M szint (15%)
- **Védelem**: Időjárásálló kivitelezés kültéri használatra

## 3. Adatbiztonság és Adatvédelem

### GDPR megfelelőség
- Felhasználói beleegyezés kezelése
- Adattárolás korlátozása
- Hozzáférési és törlési jog biztosítása

### Firebase biztonság
- Firestore Security Rules
- Authentikáció (Firebase Auth)
- HTTPS kommunikáció

## 4. PWA (Progressive Web App) Követelmények

### Core követelmények
- **HTTPS**: Biztonságos kapcsolat
- **Service Worker**: Offline funkciók
- **Manifest fájl**: Telepíthetőség
- **Responsive design**: Minden eszközön működik

### Előnyök
- App store-tól független telepítés
- Automatikus frissítések
- Platformfüggetlen működés
- Kisebb tárhelyigény natív appokhoz képest

## 5. Geolokáció és Térképes Szolgáltatások

### Technológiák
- **HTML5 Geolocation API**: Pozíció meghatározás
- **OpenStreetMap / Leaflet**: Nyílt térképes megoldás
- **Google Maps API**: Részletes térképadatok

### Háttérben futó szolgáltatások
- **Geofencing**: Közelség detektálás
- **Background location tracking**: Folyamatos pozíciókövetés
- **Push notifications**: Értesítések közelség alapján

## Hivatkozások

1. Brown, B., & Chalmers, M. (2003). Tourism and mobile technology. ECSCW 2003.
2. Gretzel, U., et al. (2015). Smart tourism: foundations and developments. Electronic Markets, 25(3), 179-188.
3. Xu, F., et al. (2017). Gamification in tourism. Tourism Management, 60, 244-256.
4. Ceipidor, U. B., et al. (2009). Mobile museum applications with NFC and QR-code. IEEE International Conference.
5. Ozcelik, E., & Acarturk, C. (2011). Reducing cognitive load in multimedia learning. Computers in Human Behavior.
6. So, S. (2011). The adoption of QR code in tourism destinations. Pacific Asia Conference on Information Systems.

## Összefoglalás

A szakirodalom egyértelműen alátámasztja:
- **Interaktív, gamifikált megoldások** növelik a turisztikai élményt
- **QR-kódok praktikus eszközök** helyszíni információközlésre
- **Mobil technológia** lehetővé teszi a kontextus-érzékeny tartalomszolgáltatást
- **Adatbiztonság és PWA** követelmények biztosítják a modern felhasználói elvárásokat
