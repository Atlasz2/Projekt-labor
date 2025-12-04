// Dummy adatok, cseréld le backend API hívásokra!
const adminUser = { username: "a", password: "as" };
// A tényleges turistaútvonal (járható szakaszok) - pontosan a stations.json és path.json alapján
let stations = [
    { id: 1, name: "Kinizsi vár", status: "aktív", lat: 46.98293554906191, lng: 17.69481718540192, funFact: "A várat Kinizsi Pál építtette a 15. században." },
    { id: 2, name: "Szent Ilona romok", status: "inaktív", lat: 46.98564788430669, lng: 17.689200639724735, funFact: "A romok egy középkori templom maradványai." },
    { id: 3, name: "Forrás", status: "inaktív", lat: 46.97926841129954, lng: 17.660238146781925, funFact: "A forrás vize egész évben iható." }
];

// A tényleges turistaútvonal (járható szakaszok) - pontosan a path.json alapján, a Forrás pont a végére került!
let tourPath = [
    [46.98293554906191, 17.69481718540192], // Kinizsi vár (helyes kezdőpont)
    [46.98495989257567, 17.695659399032596],
    [46.985180, 17.695510],
    [46.985370, 17.695080],
    [46.985600, 17.694600],
    [46.985800, 17.694000],
    [46.985900, 17.693400],
    [46.986000, 17.692800],
    [46.986100, 17.692200],
    [46.986200, 17.691600],
    [46.986100, 17.691000],
    [46.985900, 17.690400],
    [46.985800, 17.689800],
    [46.98564788430669, 17.689200639724735], // Szent Ilona romok
    [46.985400, 17.688700],
    [46.984900, 17.687900],
    [46.984200, 17.686900],
    [46.983500, 17.685900],
    [46.982800, 17.684900],
    [46.982100, 17.683900],
    [46.981400, 17.682900],
    [46.980700, 17.681900],
    [46.980000, 17.680900],
    [46.979500, 17.679000],
    [46.97926841129954, 17.660238146781925]  // Forrás (helyes végpont)
];

let stats = {
    users: 42,
    stations: stations.length,
    activeStations: stations.filter(s => s.status === "aktív").length
};

let map, markers = [];

// Dummy üzenetek (helyettesítsd backend API-val)
let messages = [
    { text: "Új visszajelzés érkezett az alkalmazásból.", date: "2024-06-10 14:22" },
    { text: "Felhasználó jelentett egy hibát a térképen.", date: "2024-06-09 18:05" }
];

async function loadTripData() {
    try {
        console.log('loadTripData indul...');

        // ⛳️ 1) Állomások – IDE ÍRD A VALÓDI API-DET
const stationsRes = await fetch('./stations.json');

        console.log('stationsRes status:', stationsRes.status);

        if (!stationsRes.ok) {
            throw new Error('Állomás lekérés sikertelen. HTTP ' + stationsRes.status);
        }

        // Ha nem vagy biztos a formátumban, először textként nézzük:
        const stationsText = await stationsRes.text();
        console.log('stations raw body:', stationsText);

        let stationsData;
        try {
            stationsData = JSON.parse(stationsText);
        } catch (e) {
            throw new Error('Állomás JSON parse hiba: ' + e.message);
        }

        // ⛳️ 2) Útvonal – IDE IS A VALÓDI API-T
const pathRes = await fetch('./path.json');
        console.log('pathRes status:', pathRes.status);

        if (!pathRes.ok) {
            throw new Error('Útvonal lekérés sikertelen. HTTP ' + pathRes.status);
        }

        const pathText = await pathRes.text();
        console.log('path raw body:', pathText);

        let pathData;
        try {
            pathData = JSON.parse(pathText);
        } catch (e) {
            throw new Error('Útvonal JSON parse hiba: ' + e.message);
        }

        // ⛳️ 3) JSON → belső változók
        // feltételezés: stationsData = [ {id, name, status, lat, lng, funFact}, ... ]
        stations = stationsData;

        // feltételezés: pathData.points = [ {lat, lng}, ... ]
        if (!Array.isArray(pathData.points)) {
            throw new Error('Útvonal formátum hiba: hiányzik a points tömb.');
        }

        tourPath = pathData.points.map(p => [p.lat, p.lng]);

        console.log('Betöltött állomások:', stations);
        console.log('Betöltött tourPath pontok száma:', tourPath.length);

        // statok
        stats.stations = stations.length;
        stats.activeStations = stations.filter(s => s.status === 'aktív').length;

        // UI friss
        window.renderStats();
        window.renderStations();
        window.renderMessages();
        setTimeout(window.initMap, 50);

    } catch (err) {
        console.error('loadTripData hiba:', err);
        alert('Nem sikerült betölteni az útvonalat és/vagy állomásokat:\n' + err.message);
    }
}

// Kijelentkezés gomb hozzáadása az admin felület tetejére
function renderLogoutButton() {
    let panel = document.getElementById('admin-panel');
    if (!panel) return;
    let logoutBtn = document.getElementById('logout-btn');
    if (!logoutBtn) {
        logoutBtn = document.createElement('button');
        logoutBtn.id = 'logout-btn';
        logoutBtn.className = 'logout-btn'; // csak class, ne inline style
        logoutBtn.innerHTML = 'Kijelentkezés <span style="font-size:1.2em;">&#128274;</span>';
        logoutBtn.onclick = window.logout;
        panel.appendChild(logoutBtn);
    }
}

// Kijelentkezés logika
window.logout = function() {
    document.getElementById('main-bg').style.display = 'none';
    document.getElementById('admin-container').style.display = 'none';
    document.getElementById('admin-panel').classList.add('hidden');
    document.getElementById('login').style.display = '';
    document.getElementById('login-bg').style.display = '';
    // Töröld az esetleges hibákat, mezőket
    document.getElementById('login-error').innerText = '';
    document.getElementById('username').value = '';
    document.getElementById('password').value = '';
};

window.login = function() {
    const u = document.getElementById('username').value;
    const p = document.getElementById('password').value;

    if (u === adminUser.username && p === adminUser.password) {
        document.getElementById('login').style.display = 'none';
        document.getElementById('login-bg').style.display = 'none';
        document.getElementById('main-bg').style.display = 'block';
        document.getElementById('admin-container').style.display = '';
        document.getElementById('admin-panel').classList.remove('hidden');
        window.renderStats();
        window.renderMessages();
        window.renderStations();
        setTimeout(window.initMap, 50);
        renderLogoutButton(); // <-- kijelentkezés gomb megjelenítése
    } else {
        document.getElementById('login-error').innerText =
            "Hibás felhasználónév vagy jelszó!";
    }
};



function createCrossIcon() {
    return L.divIcon({
        className: 'custom-cross-marker',
        html: `<div style="font-size:1.2em;color:#27ae60;line-height:1;">✚</div>`,
        iconSize: [20, 20],
        iconAnchor: [10, 10]
    });
}

function showCoordsPopup(lat, lng, onClose) {
    const popup = document.createElement('div');
    popup.className = 'coords-popup';
    popup.innerHTML = `
        <div class="coords-popup-icon">✚</div>
        <div><strong>Koordináta:</strong></div>
        <div class="coords-popup-values">
            <span>Lat:</span> <b>${lat}</b><br>
            <span>Lng:</span> <b>${lng}</b>
        </div>
        <button class="modal-coord-hide-btn coords-popup-close" id="coords-popup-close">Elrejtés</button>
    `;
    document.body.appendChild(popup);
    document.getElementById('coords-popup-close').onclick = function() {
        document.body.removeChild(popup);
        if (onClose) onClose();
    };
}

// OSRM alapú gyalogos útvonal két állomás között
async function drawRouteBetweenStations(fromStation, toStation) {
    if (!map) return;

    const from = `${fromStation.lng},${fromStation.lat}`;
    const to   = `${toStation.lng},${toStation.lat}`;

    // foot = gyalogos útvonal
    const url = `https://router.project-osrm.org/route/v1/foot/${from};${to}?overview=full&geometries=geojson`;

    try {
        const res = await fetch(url);
        const data = await res.json();

        if (!data.routes || !data.routes.length) return;

        // GeoJSON -> [lat,lng] tömb Leafletnek
        const coords = data.routes[0].geometry.coordinates.map(([lng, lat]) => [lat, lng]);

        L.polyline(coords, {
            color: '#e1ad01',
            weight: 5,
            opacity: 0.85,
            lineJoin: 'round'
        }).addTo(map);

    } catch (err) {
        console.error('OSRM hiba:', err);
        // Ha bármi gond van, fallback: sima légvonal, hogy legalább valami legyen
        L.polyline(
            [
                [fromStation.lat, fromStation.lng],
                [toStation.lat,   toStation.lng]
            ],
            {
                color: '#e1ad01',
                weight: 5,
                opacity: 0.5,
                dashArray: '5,8'
            }
        ).addTo(map);
    }
}


// Dinamikus túraútvonal generálás: csak aktív állomások, sorrendben
function getActiveTourPath() {
    return stations
        .filter(s => s.status === "aktív")
        .map(s => [s.lat, s.lng]);
}

window.updateMapMarkers = function() {
    if (!map) return;
    markers.forEach(m => map.removeLayer(m));
    markers = [];
    stations.forEach(station => {
        const markerIcon = L.icon({
            iconUrl: station.status === 'aktív'
                ? 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png'
                : 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
            shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            shadowSize: [41, 41]
        });
        const marker = L.marker([station.lat, station.lng], { icon: markerIcon, draggable: false })
            .addTo(map)
            .bindPopup(`<strong>${station.name}</strong><br>${station.status.charAt(0).toUpperCase() + station.status.slice(1)}`);
        markers.push(marker);
    });
};

window.renderStats = function() {
    document.getElementById('stats').innerHTML = `
        <div class="stat-card">
            <strong>Felhasználók száma</strong>
            <p>${stats.users}</p>
        </div>
        <div class="stat-card">
            <strong>Állomások száma</strong>
            <p>${stats.stations}</p>
        </div>
        <div class="stat-card">
            <strong>Aktív állomások</strong>
            <p>${stats.activeStations}</p>
        </div>
    `;
};

window.renderMessages = function() {
    const list = document.getElementById('messages-list');
    if (!list) return;
    if (messages.length === 0) {
        list.innerHTML = '<div style="color:#888;text-align:center;">Nincs beérkező üzenet.</div>';
        return;
    }
    list.innerHTML = messages.map((msg, idx) => `
        <div class="message-item" onclick="showMessageDetail(${idx})">
            <div>${msg.text}</div>
            <div class="message-date">${msg.date}</div>
        </div>
    `).join('');
};

window.showMessageDetail = function(idx) {
    const msg = messages[idx];
    const modalBg = document.createElement('div');
    modalBg.className = 'modal-bg-message';
    const modal = document.createElement('div');
    modal.className = 'modal-box-message';
    modal.innerHTML = `
        <h3>Üzenet részletei</h3>
        <div>${msg.text}</div>
        <div class="message-date">${msg.date}</div>
        <button class="modal-close-btn" id="close-message-modal">Bezárás</button>
    `;
    modalBg.appendChild(modal);
    document.body.appendChild(modalBg);
    document.getElementById('close-message-modal').onclick = function() {
        document.body.removeChild(modalBg);
    };
};

window.renderStations = function() {
    const container = document.getElementById('stations');
    container.innerHTML = '';
    stations.forEach((station, idx) => {
        const isFirst = idx === 0;
        const isLast = idx === stations.length - 1;
        const isActive = station.status === 'aktív';
        container.innerHTML += `
            <div class="station station-anim" style="box-shadow: 0 2px 8px rgba(42,77,105,0.10); border-left: 6px solid ${isActive ? '#27ae60' : '#e74c3c'}; padding: 0.9em 1.1em;">
                <div class="station-info" style="gap:0.15em;">
                    <div class="station-title" style="display:flex;align-items:center;gap:0.35em;font-size:1.05em;">
                        <span class="station-icon" title="Állomás" style="background:${isActive ? '#27ae60' : '#e74c3c'};width:22px;height:22px;font-size:1em;">&#128205;</span>
                        <span style="font-size:1em;">${station.name}</span>
                        <button class="station-coords-btn" title="Koordináta megjelenítése" onclick="showCoords(${station.id})">&#128269;</button>
                        <div style="display:flex;flex-direction:column;gap:1px;margin-left:7px;">
                            <button class="station-move-btn" title="Fel" onclick="moveStation(${idx},-1)" style="padding:1px 5px;border-radius:4px;background:#e0eafc;color:#2a4d69;border:none;box-shadow:0 1px 3px #b0c4de;cursor:pointer;transition:background 0.2s;font-size:1em;${isFirst ? 'opacity:0.4;cursor:not-allowed;' : ''}" ${isFirst ? 'disabled' : ''}>&#8593;</button>
                            <button class="station-move-btn" title="Le" onclick="moveStation(${idx},1)" style="padding:1px 5px;border-radius:4px;background:#e0eafc;color:#2a4d69;border:none;box-shadow:0 1px 3px #b0c4de;cursor:pointer;transition:background 0.2s;font-size:1em;${isLast ? 'opacity:0.4;cursor:not-allowed;' : ''}" ${isLast ? 'disabled' : ''}>&#8595;</button>
                        </div>
                    </div>
                    <span class="station-status ${isActive ? 'aktiv' : 'inaktiv'}" style="margin-top:0.15em;font-size:0.95em;">
                        ${station.status.charAt(0).toUpperCase() + station.status.slice(1)}
                    </span>
                    <span class="station-funfact" style="margin-top:0.15em;font-size:0.95em;">
                        <strong>Érdekesség:</strong> ${station.funFact ? station.funFact : '<i>Nincs megadva</i>'}
                    </span>
                </div>
                <div class="station-actions" style="display:flex;flex-direction:column;gap:0.25em;">
                    <button class="station-edit" onclick="editStation(${station.id})" title="Szerkesztés" style="background:#e0eafc;color:#2a4d69;padding:0.35em 0.8em;font-size:0.97em;">&#9998; Szerkesztés</button>
                    <button class="station-delete" onclick="deleteStation(${station.id})" title="Törlés" style="background:#ffe3e3;color:#e74c3c;padding:0.35em 0.8em;font-size:0.97em;">&#128465; Törlés</button>
                </div>
            </div>
        `;
    });
    window.updateMapMarkers();
    // Útvonal is frissüljön, ha változott a sorrend/státusz
    if (typeof window.initMap === 'function' && map) {
        window.initMap();
    }
};

// Fel-le mozgatás logika (marad)
window.moveStation = function(idx, dir) {
    const newIdx = idx + dir;
    if (newIdx < 0 || newIdx >= stations.length) return;
    const temp = stations[idx];
    stations[idx] = stations[newIdx];
    stations[newIdx] = temp;
    window.renderStations();
    window.renderStats();
    window.updateMapMarkers();
    if (typeof window.initMap === 'function' && map) {
        window.initMap();
    }
};

// Aktív állomások sorrendjében, minden szomszédos aktív között legyen gyalogos útvonal (OSRM)
window.initMap = function() {
    if (map) { 
        map.remove(); 
        markers = []; 
    }

    // Térkép középre állítása az összes állomás alapján
    if (stations.length > 0) {
        const latlngs = stations.map(s => [s.lat, s.lng]);
        const bounds = L.latLngBounds(latlngs);
        map = L.map('map');
        map.fitBounds(bounds, { padding: [30, 30] });
    } else {
        map = L.map('map').setView([47.026, 17.652], 14);
    }

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap'
    }).addTo(map);

    // Csak az aktív állomások sorrendjében, minden szomszédos aktív között legyen szakasz
    const activeStations = stations.filter(s => s.status === 'aktív');
    (async () => {
        for (let i = 0; i < activeStations.length - 1; i++) {
            await drawRouteBetweenStations(activeStations[i], activeStations[i + 1]);
        }
    })();

    window.updateMapMarkers();

    window._selectCoordCallback = null;
    map.on('click', function(e) {
        if (typeof window._selectCoordCallback === 'function') {
            const tempMarker = L.marker([e.latlng.lat, e.latlng.lng], { icon: createCrossIcon() }).addTo(map);
            setTimeout(() => map.removeLayer(tempMarker), 1200);
            window._selectCoordCallback(e.latlng.lat, e.latlng.lng);
            window._selectCoordCallback = null;
        }
    });
};


// Jelszó mutatás/takarás
window.showPwTemp = function() {
    const pw = document.getElementById('password');
    if (pw) pw.type = 'text';
};
window.hidePw = function() {
    const pw = document.getElementById('password');
    if (pw) pw.type = 'password';
};

// Koordináta popup
window.showCoords = function(stationId) {
    const station = stations.find(s => s.id === stationId);
    if (!station || !map) return;

    // Zoom and pan to the station's coordinates on the map
    map.setView([station.lat, station.lng], 18, { animate: true });

    // Nyissa meg a marker popupját, ha van ilyen marker
    const marker = markers.find(m => {
        const pos = m.getLatLng && m.getLatLng();
        return pos && Math.abs(pos.lat - station.lat) < 0.0001 && Math.abs(pos.lng - station.lng) < 0.0001;
    });
    if (marker && marker.openPopup) {
        marker.openPopup();
    }

    // Mutassa a koordináta popupot is
    showCoordsPopup(station.lat, station.lng);
};

function createStatusSwitch(idPrefix, currentStatus) {
    return `
        <div class="modal-status-switch">
            <button type="button" class="modal-status-btn${currentStatus === 'aktív' ? ' active' : ''}" id="${idPrefix}-status-aktiv">Aktív</button>
            <button type="button" class="modal-status-btn${currentStatus === 'inaktív' ? ' inactive' : ''}" id="${idPrefix}-status-inaktiv">Inaktív</button>
        </div>
    `;
}

function createCoordFields(idPrefix, lat, lng, showFields = false) {
    return `
        <div id="${idPrefix}-coord-fields" style="display:flex;flex-direction:column;align-items:center;margin-bottom:1em;">
            <button class="modal-coord-btn" id="${idPrefix}-coord-show-btn" style="margin:0 auto;display:block;">Koordináták megjelenítése</button>
            <div id="${idPrefix}-coords-fields-inner" style="margin-top:1em;${showFields ? '' : 'display:none;'}">
                <label style="margin-bottom:0;">
                    <span style="color:#2a4d69;font-weight:500;">Lat:</span>
                    <input type="text" id="${idPrefix}-lat" value="${lat || ''}" readonly style="width:110px;">
                </label>
                <label style="margin-bottom:0;">
                    <span style="color:#2a4d69;font-weight:500;">Lng:</span>
                    <input type="text" id="${idPrefix}-lng" value="${lng || ''}" readonly style="width:110px;">
                </label>
            </div>
            <div id="${idPrefix}-coords-extra" style="display:none;margin-top:0.5em;">
                <span style="color:#2a4d69;">Lat:</span> <b id="${idPrefix}-coords-lat"></b>
                <span style="margin-left:1em;color:#2a4d69;">Lng:</span> <b id="${idPrefix}-coords-lng"></b>
                <button class="modal-coord-hide-btn" id="${idPrefix}-coords-hide-btn" style="margin-left:1em;">Elrejtés</button>
            </div>
        </div>
    `;
}

function setupCoordShowHide(idPrefix, getLat, getLng) {
    let coordsVisible = false;
    const showBtn = document.getElementById(`${idPrefix}-coord-show-btn`);
    const hideBtn = document.getElementById(`${idPrefix}-coords-hide-btn`);
    const coordsExtra = document.getElementById(`${idPrefix}-coords-extra`);
    const coordsLat = document.getElementById(`${idPrefix}-coords-lat`);
    const coordsLng = document.getElementById(`${idPrefix}-coords-lng`);
    const fieldsInner = document.getElementById(`${idPrefix}-coords-fields-inner`);

    showBtn.onclick = function() {
        // Ha már látszik, ne csináljon semmit (második nyomásra sem)
        if (coordsVisible || coordsExtra.style.display === 'inline-block') return;
        const lat = getLat();
        const lng = getLng();
        if (!lat || !lng) return;
        if (fieldsInner && fieldsInner.style.display === 'none') {
            fieldsInner.style.display = '';
            return;
        }
        coordsLat.textContent = lat;
        coordsLng.textContent = lng;
        coordsExtra.style.display = 'inline-block';
        coordsVisible = true;
        // Tiltsd le a gombot, hogy ne lehessen újra rányomni
        showBtn.disabled = true;
    };
    hideBtn.onclick = function() {
        coordsExtra.style.display = 'none';
        coordsVisible = false;
        // Engedélyezd újra a gombot
        showBtn.disabled = false;
        // Töröld a koordináta értékeket, hogy ne duplikáljon
        coordsLat.textContent = '';
        coordsLng.textContent = '';
    };
}

window.editStation = function(stationId) {
    const station = stations.find(s => s.id === stationId);
    if (!station) return;
    let tempLat = station.lat, tempLng = station.lng;
    let selecting = false;
    let tempMarker = null;

    const modalBg = document.createElement('div');
    modalBg.className = 'modal-bg';
    const modal = document.createElement('div');
    modal.className = 'modal-box';
    modal.innerHTML = `
        <h3>Állomás szerkesztése</h3>
        <label>Név:<input type="text" id="edit-name" value="${station.name}" /></label>
        <button class="modal-coord-map-btn" id="edit-map-btn">Hely kijelölése a térképen</button>
        ${createStatusSwitch('edit', station.status)}
        ${createCoordFields('edit', tempLat, tempLng)}
        <label>Érdekesség:<textarea id="edit-funfact">${station.funFact || ''}</textarea></label>
        <div class="modal-actions">
            <button class="modal-save" id="edit-save">Mentés</button>
            <button class="modal-cancel" id="edit-cancel">Mégse</button>
        </div>
    `;
    modalBg.appendChild(modal);
    document.body.appendChild(modalBg);

    // Státusz kapcsoló
    document.getElementById('edit-status-aktiv').onclick = function() {
        document.getElementById('edit-status-aktiv').classList.add('active');
        document.getElementById('edit-status-inaktiv').classList.remove('inactive');
        station.status = 'aktív';
    };
    document.getElementById('edit-status-inaktiv').onclick = function() {
        document.getElementById('edit-status-inaktiv').classList.add('inactive');
        document.getElementById('edit-status-aktiv').classList.remove('active');
        station.status = 'inaktív';
    };

    setupCoordShowHide('edit', () => tempLat, () => tempLng);

    document.getElementById('edit-map-btn').onclick = function() {
        selecting = true;
        map.getContainer().style.cursor = 'crosshair';
        modalBg.style.display = 'none';

        map.on('mousemove', onMapMove);
        map.once('click', onMapClick);
    };

    function onMapMove(e) {
        if (!selecting) return;
        if (tempMarker) map.removeLayer(tempMarker);
        tempMarker = L.marker([e.latlng.lat, e.latlng.lng], { icon: createCrossIcon() }).addTo(map);
    }

    function onMapClick(e) {
        selecting = false;
        map.getContainer().style.cursor = '';
        if (tempMarker) {
            map.removeLayer(tempMarker);
            tempMarker = null;
        }
        tempLat = e.latlng.lat;
        tempLng = e.latlng.lng;
        document.getElementById('edit-lat').value = tempLat;
        document.getElementById('edit-lng').value = tempLng;
        map.off('mousemove', onMapMove);
        modalBg.style.display = '';
        document.getElementById('edit-coords-extra').style.display = 'none';
    }

    document.getElementById('edit-cancel').onclick = function() {
        if (tempMarker) map.removeLayer(tempMarker);
        map.off('mousemove', onMapMove);
        document.body.removeChild(modalBg);
    };
    document.getElementById('edit-save').onclick = function() {
        station.name = document.getElementById('edit-name').value;
        station.funFact = document.getElementById('edit-funfact').value;
        station.lat = parseFloat(document.getElementById('edit-lat').value);
        station.lng = parseFloat(document.getElementById('edit-lng').value);
        // Frissítsd az aktív állomások számlálót!
        stats.activeStations = stations.filter(s => s.status === "aktív").length;
        window.renderStations();
        window.renderStats();
        window.updateMapMarkers();
        if (tempMarker) map.removeLayer(tempMarker);
        map.off('mousemove', onMapMove);
        document.body.removeChild(modalBg);
    };
};

window.deleteStation = function(stationId) {
    const station = stations.find(s => s.id === stationId);
    if (!station) return;
    // Modal háttér
    const modalBg = document.createElement('div');
    modalBg.className = 'modal-bg';
    // Modal doboz
    const modal = document.createElement('div');
    modal.className = 'modal-box';
    modal.innerHTML = `
        <h3>Állomás törlése</h3>
        <div>Biztosan törölni szeretnéd az állomást?<br><strong>${station.name}</strong></div>
        <div class="modal-actions">
            <button class="modal-save" id="delete-confirm">Törlés</button>
            <button class="modal-cancel" id="delete-cancel">Mégse</button>
        </div>
    `;
    modalBg.appendChild(modal);
    document.body.appendChild(modalBg);

    document.getElementById('delete-cancel').onclick = function() {
        document.body.removeChild(modalBg);
    };
    document.getElementById('delete-confirm').onclick = function() {
        stations = stations.filter(s => s.id !== stationId);
        stats.stations = stations.length;
        stats.activeStations = stations.filter(s => s.status === "aktív").length;
        window.renderStats();
        window.renderStations();
        window.updateMapMarkers();
        document.body.removeChild(modalBg);
    };
};

window.addStation = function() {
    let status = 'aktív';
    let tempLat = '', tempLng = '';
    let selecting = false;
    let tempMarker = null;
    let showFields = false;

    const modalBg = document.createElement('div');
    modalBg.className = 'modal-bg';
    const modal = document.createElement('div');
    modal.className = 'modal-box';
    modal.innerHTML = `
        <h3>Új állomás hozzáadása</h3>
        <label>Név:<input type="text" id="new-name" /></label>
        <button class="modal-coord-map-btn" id="new-map-btn">Hely kijelölése a térképen</button>
        ${createStatusSwitch('new', status)}
        <div id="new-coord-fields-container">
            ${createCoordFields('new', tempLat, tempLng, showFields)}
        </div>
        <label>Érdekesség:<textarea id="new-funfact"></textarea></label>
        <div class="modal-actions">
            <button class="modal-save" id="new-save">Hozzáadás</button>
            <button class="modal-cancel" id="new-cancel">Mégse</button>
        </div>
    `;
    modalBg.appendChild(modal);
    document.body.appendChild(modalBg);

    document.getElementById('new-status-aktiv').onclick = function() {
        status = 'aktív';
        document.getElementById('new-status-aktiv').classList.add('active');
        document.getElementById('new-status-inaktiv').classList.remove('inactive');
    };
    document.getElementById('new-status-inaktiv').onclick = function() {
        status = 'inaktív';
        document.getElementById('new-status-inaktiv').classList.add('inactive');
        document.getElementById('new-status-aktiv').classList.remove('active');
    };

    setupCoordShowHide('new', () => tempLat, () => tempLng);

    let mapClickHandler = null;
    let mapMoveHandler = null;

    document.getElementById('new-map-btn').onclick = function() {
        selecting = true;
        map.getContainer().style.cursor = 'crosshair';
        modalBg.style.display = 'none';

        // Tisztítsd le az előző eseményeket, ha voltak
        if (mapClickHandler) map.off('click', mapClickHandler);
        if (mapMoveHandler) map.off('mousemove', mapMoveHandler);

        mapMoveHandler = function(e) {
            if (!selecting) return;
            if (tempMarker) map.removeLayer(tempMarker);
            tempMarker = L.marker([e.latlng.lat, e.latlng.lng], { icon: createCrossIcon() }).addTo(map);
        };
        mapClickHandler = function(e) {
            selecting = false;
            map.getContainer().style.cursor = '';
            if (tempMarker) {
                map.removeLayer(tempMarker);
                tempMarker = null;
            }
            tempLat = e.latlng.lat;
            tempLng = e.latlng.lng;
            map.off('mousemove', mapMoveHandler);
            map.off('click', mapClickHandler);
            modalBg.style.display = '';
            showFields = false;
            document.getElementById('new-coord-fields-container').innerHTML = createCoordFields('new', tempLat, tempLng, showFields);
            setupCoordShowHide('new', () => tempLat, () => tempLng);
        };

        map.on('mousemove', mapMoveHandler);
        map.on('click', mapClickHandler);
    };

    document.getElementById('new-cancel').onclick = function() {
        if (tempMarker) map.removeLayer(tempMarker);
        if (mapMoveHandler) map.off('mousemove', mapMoveHandler);
        if (mapClickHandler) map.off('click', mapClickHandler);
        document.body.removeChild(modalBg);
    };
    document.getElementById('new-save').onclick = function() {
        const name = document.getElementById('new-name').value;
        const funFact = document.getElementById('new-funfact').value;
        const lat = tempLat;
        const lng = tempLng;
        if (!name || !lat || !lng) {
            alert('Név és hely kötelező!');
            return;
        }
        const newId = stations.length > 0 ? Math.max(...stations.map(s => s.id)) + 1 : 1;
        stations.push({ id: newId, name, status, lat, lng, funFact });
        stats.stations = stations.length;
        stats.activeStations = stations.filter(s => s.status === "aktív").length;
        window.renderStats();
        window.renderStations();
        window.updateMapMarkers();
        if (tempMarker) map.removeLayer(tempMarker);
        if (mapMoveHandler) map.off('mousemove', mapMoveHandler);
        if (mapClickHandler) map.off('click', mapClickHandler);
        document.body.removeChild(modalBg);
    };
};

// DOMContentLoaded: események bekötése
document.addEventListener('DOMContentLoaded', function() {
    // Új állomás gomb JS-ből
    var addBtn = document.getElementById('add-station-btn');
    if (addBtn) {
        addBtn.onclick = window.addStation;
    }
    // Enterrel is lehessen belépni
    var userInput = document.getElementById('username');
    var pwInput = document.getElementById('password');
    if (userInput) {
        userInput.onkeydown = function(e) {
            if (e.key === 'Enter') {
                if (pwInput) pwInput.focus();
            }
        };
    }
    if (pwInput) {
        pwInput.onkeydown = function(e) {
            if (e.key === 'Enter') {
                window.login();
            }
        };
    }
    // Ha automatikusan kell inicializálni valamit, itt tedd meg
    // Például: window.renderStats(); window.renderMessages(); window.renderStations();
});

// Minden függvény window-ra van rakva, minden inline gomb működik.
// Ellenőrizd a böngésző konzolt, hogy nincs-e JS hiba vagy betöltési gond!
