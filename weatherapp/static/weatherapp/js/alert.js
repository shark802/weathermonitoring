document.addEventListener('DOMContentLoaded', function() {
    // Initialize map with center from Django context or default
    const mapCenter = window.mapCenter || { lat: 10.508884, lng: 122.957527 };
    const map = L.map('map').setView([mapCenter.lat, mapCenter.lng], 12);
    
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    // Audio setup
    const alertSound = document.getElementById('alertSound');
    const fadeDuration = 10000; // 10 seconds fade effect
    const alertDuration = 300000; // 5 minutes total alert duration
    const enableAudioBtn = document.getElementById('enableAudio');

    // Default marker icon
    const defaultIcon = L.icon({
        iconUrl: 'https://unpkg.com/leaflet/dist/images/marker-icon.png',
        iconSize: [25, 41],
        iconAnchor: [12, 41]
    });

    // Audio control setup
    if (enableAudioBtn) {
        enableAudioBtn.addEventListener('click', initAudio);
        if (localStorage.getItem('audioEnabled') === 'true') {
            enableAudioBtn.style.display = 'none';
        }
    }

    function initAudio() {
        alertSound.volume = 0.7;
        alertSound.play()
            .then(() => {
                alertSound.pause();
                alertSound.currentTime = 0;
                enableAudioBtn.style.display = 'none';
                localStorage.setItem('audioEnabled', 'true');
            })
            .catch(e => {
                console.error("Audio initialization failed:", e);
                enableAudioBtn.textContent = "🔇 Click to enable sound (browser blocked)";
            });
    }

    // Process locations from Django template
    const locations = JSON.parse(document.getElementById('locations-data').textContent);
    const serverAlerts = JSON.parse(document.getElementById('alerts-data').textContent);

    locations.forEach(loc => {
        if (!loc.latitude || !loc.longitude) return;

        const marker = L.marker([loc.latitude, loc.longitude], {
            icon: loc.has_alert ? createAlertIcon(loc) : defaultIcon
        }).addTo(map);

        if (loc.has_alert) {
            setupAlertMarker(marker, loc);
        } else {
            marker.bindPopup(`<div>${loc.name}</div>`);
        }
    });

    // Create appropriate alert icon based on alert type
    function createAlertIcon(location) {
        const alertType = location.alert_text.includes('Rainfall') ? 'rain' : 
                         location.alert_text.includes('Wind') ? 'wind' : 'general';
        
        const iconColor = {
            rain: '#2563eb',
            wind: '#f59e0b',
            general: '#dc2626'
        }[alertType];

        const iconSymbol = {
            rain: '🌧️',
            wind: '💨',
            general: '⚠️'
        }[alertType];

        return L.divIcon({
            className: 'alert-pin',
            html: `<div class="custom-pin" style="color: ${iconColor};">
                    <span class="alert-icon">${iconSymbol}</span>
                    <span class="pin-label">${location.name}</span>
                  </div>`,
            iconSize: [32, 40],
            iconAnchor: [16, 40]
        });
    }

    // Configure alert marker behavior
    function setupAlertMarker(marker, location) {
        const alertType = location.alert_text.includes('Rainfall') ? 'rain' : 
                         location.alert_text.includes('Wind') ? 'wind' : 'general';
        
        const popupClass = `${alertType}-alert`;
        const popup = marker.bindPopup(
            `<div class="alert-popup ${popupClass}">${location.alert_text}</div>`, 
            {
                autoClose: false,
                closeOnClick: false,
                maxWidth: 300
            }
        ).openPopup();

        // Play alert sound if enabled
        if (localStorage.getItem('audioEnabled') === 'true' && alertSound) {
            playAlertSound(location.sensor_id);
        }

        // Set up fade effect if alert is time-bound
        if (location.alert_datetime) {
            setupFadeEffect(marker, location, popup);
        }

        // Auto-close popup after 8 seconds
        setTimeout(() => popup.closePopup(), 8000);
    }

    function playAlertSound(sensorId) {
        if (!sessionStorage.getItem(`alert_played_${sensorId}`)) {
            alertSound.currentTime = 0;
            alertSound.play()
                .then(() => {
                    sessionStorage.setItem(`alert_played_${sensorId}`, 'true');
                    setTimeout(() => {
                        sessionStorage.removeItem(`alert_played_${sensorId}`);
                    }, alertDuration);
                })
                .catch(e => console.error("Audio playback failed:", e));
        }
    }

    function setupFadeEffect(marker, location, popup) {
        const alertEndTime = new Date(location.alert_datetime).getTime() + alertDuration;
        const now = new Date().getTime();
        const remainingTime = alertEndTime - now;
        
        if (remainingTime <= 0) return;

        const fadeStartTime = Math.max(0, remainingTime - fadeDuration);
        
        setTimeout(() => {
            const startTime = Date.now();
            const fadeInterval = setInterval(() => {
                const elapsed = Date.now() - startTime;
                const progress = Math.min(elapsed / fadeDuration, 1);
                
                // Calculate fading color
                const currentColor = getFadedColor(location, progress);
                
                marker.setIcon(L.divIcon({
                    html: `<div class="custom-pin" style="color: rgb(${currentColor.r},${currentColor.g},${currentColor.b});">
                            <span class="alert-icon">${location.alert_text.includes('Rainfall') ? '🌧️' : '💨'}</span>
                            <span class="pin-label">${location.name}</span>
                          </div>`,
                    iconSize: [32, 40],
                    iconAnchor: [16, 40],
                }));

                if (progress >= 1) {
                    clearInterval(fadeInterval);
                    marker.setIcon(defaultIcon);
                    marker.setPopupContent(`<div>${location.name}</div>`);
                    popup.closePopup();
                }
            }, 50);
        }, fadeStartTime);
    }

    function getFadedColor(location, progress) {
        const alertType = location.alert_text.includes('Rainfall') ? 'rain' : 'wind';
        const baseColor = alertType === 'rain' ? 
            { r: 37, g: 99, b: 235 } : // blue
            { r: 245, g: 158, b: 11 };  // amber
        
        const targetColor = { r: 59, g: 130, b: 246 }; // blue-500
        
        return {
            r: Math.floor(baseColor.r + (targetColor.r - baseColor.r) * progress),
            g: Math.floor(baseColor.g + (targetColor.g - baseColor.g) * progress),
            b: Math.floor(baseColor.b + (targetColor.b - baseColor.b) * progress)
        };
    }

    // Fix map size after load
    setTimeout(() => map.invalidateSize(), 100);
});