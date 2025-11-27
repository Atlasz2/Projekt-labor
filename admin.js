// Dummy adatok, cseréld le backend API hívásokra!
const adminUser = { username: "admin", password: "admin123" };
let stations = [
    { id: 1, name: "Kinizsi vár", status: "aktív", lat: 47.02513, lng: 17.64998, funFact: "A várat Kinizsi Pál építtette a 15. században." },
    { id: 2, name: "Szent Ilona romok", status: "inaktív", lat: 47.02780, lng: 17.65420, funFact: "A romok egy középkori templom maradványai." },
    { id: 3, name: "Forrás", status: "aktív", lat: 47.03010, lng: 17.65250, funFact: "A forrás vize egész évben iható." }
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
        setTimeout(window.initMap, 100);
    } else {
        document.getElementById('login-error').innerText = "Hibás felhasználónév vagy jelszó!";
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
    popup.style.padding = '0.7em 1.2em';
    popup.style.fontSize = '0.98em';
    popup.style.textAlign = 'center';
    popup.innerHTML = `
        <div style="font-size:1.3em;color:#27ae60;margin-bottom:0.3em;">✚</div>
        <div><strong>Koordináta:</strong></div>
        <div style="margin:0.5em 0 0.7em 0;">
            <span style="color:#2a4d69;">Lat:</span> <b>${lat}</b><br>
            <span style="color:#2a4d69;">Lng:</span> <b>${lng}</b>
        </div>
        <button class="modal-coord-hide-btn" id="coords-popup-close" style="margin-top:0.5em;">Elrejtés</button>
    `;
    document.body.appendChild(popup);
    document.getElementById('coords-popup-close').onclick = function() {
        document.body.removeChild(popup);
        if (onClose) onClose();
    };
}

window.initMap = function() {
    if (map) { map.remove(); markers = []; }
    map = L.map('map').setView([47.026, 17.652], 14);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap'
    }).addTo(map);

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
    stations.forEach(station => {
        container.innerHTML += `
            <div class="station station-anim">
                <div class="station-info">
                    <div class="station-title">
                        <span class="station-icon" title="Állomás">&#128205;</span>
                        ${station.name}
                        <button class="station-coords-btn" title="Koordináta megjelenítése" onclick="showCoords(${station.id})">&#128269;</button>
                    </div>
                    <span class="station-status ${station.status === 'aktív' ? 'aktiv' : 'inaktiv'}">
                        ${station.status.charAt(0).toUpperCase() + station.status.slice(1)}
                    </span>
                    <span class="station-funfact">
                        <strong>Érdekesség:</strong> ${station.funFact ? station.funFact : '<i>Nincs megadva</i>'}
                    </span>
                </div>
                <div class="station-actions">
                    <button class="station-edit" onclick="editStation(${station.id})" title="Szerkesztés">&#9998; Szerkesztés</button>
                    <button class="station-delete" onclick="deleteStation(${station.id})" title="Törlés">&#128465; Törlés</button>
                </div>
            </div>
        `;
    });
    window.updateMapMarkers();
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
    map.setView([station.lat, station.lng], 17, { animate: true });
    // Optionally, open the marker's popup if exists
    const marker = markers.find(m => {
        const pos = m.getLatLng && m.getLatLng();
        return pos && pos.lat === station.lat && pos.lng === station.lng;
    });
    if (marker && marker.openPopup) {
        marker.openPopup();
    }
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
    var pwInput = document.getElementById('password');
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
