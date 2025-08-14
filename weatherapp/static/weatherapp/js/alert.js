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

    // Icon configurations
    const icons = {
        default: L.icon({
            iconUrl: 'https://unpkg.com/leaflet/dist/images/marker-icon.png',
            iconSize: [25, 41],
            iconAnchor: [12, 41]
        }),
        rain: {
            color: '#2563eb',
            symbol: '🌧️',
            className: 'rain-alert'
        },
        wind: {
            color: '#f59e0b',
            symbol: '💨',
            className: 'wind-alert'
        },
        general: {
            color: '#dc2626',
            symbol: '⚠️',
            className: 'general-alert'
        }
    };

    // Initialize audio controls
    function initAudioControls() {
        if (!enableAudioBtn) return;
        
        enableAudioBtn.addEventListener('click', function() {
            alertSound.volume = 0.7;
            alertSound.play()
                .then(() => {
                    alertSound.pause();
                    alertSound.currentTime = 0;
                    this.style.display = 'none';
                    localStorage.setItem('audioEnabled', 'true');
                })
                .catch(e => {
                    console.error("Audio initialization failed:", e);
                    this.textContent = "🔇 Click to enable sound (browser blocked)";
                });
        });

        if (localStorage.getItem('audioEnabled') === 'true') {
            enableAudioBtn.style.display = 'none';
        }
    }

    // Create custom alert icon
    function createAlertIcon(location) {
        const alertType = determineAlertType(location.alert_text);
        const iconConfig = icons[alertType];
        
        return L.divIcon({
            className: 'alert-pin',
            html: `<div class="custom-pin" style="color: ${iconConfig.color};">
                    <span class="alert-icon">${iconConfig.symbol}</span>
                    <span class="pin-label">${location.name}</span>
                  </div>`,
            iconSize: [32, 40],
            iconAnchor: [16, 40]
        });
    }

    // Determine alert type from alert text
    function determineAlertType(alertText) {
        if (alertText.includes('Rainfall')) return 'rain';
        if (alertText.includes('Wind')) return 'wind';
        return 'general';
    }

    // Configure alert marker behavior
    function setupAlertMarker(marker, location) {
        const alertType = determineAlertType(location.alert_text);
        const popupClass = icons[alertType].className;
        
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
            setupFadeEffect(marker, location, popup, alertType);
        }

        // Auto-close popup after 8 seconds
        setTimeout(() => popup.closePopup(), 8000);
    }

    // Play alert sound with session tracking
    function playAlertSound(sensorId) {
        if (sessionStorage.getItem(`alert_played_${sensorId}`)) return;
        
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

    // Set up color fade effect for alert markers
    function setupFadeEffect(marker, location, popup, alertType) {
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
                
                const currentColor = calculateFadedColor(alertType, progress);
                
                marker.setIcon(L.divIcon({
                    html: `<div class="custom-pin" style="color: rgb(${currentColor.r},${currentColor.g},${currentColor.b});">
                            <span class="alert-icon">${icons[alertType].symbol}</span>
                            <span class="pin-label">${location.name}</span>
                          </div>`,
                    iconSize: [32, 40],
                    iconAnchor: [16, 40],
                }));

                if (progress >= 1) {
                    clearInterval(fadeInterval);
                    marker.setIcon(icons.default);
                    marker.setPopupContent(`<div>${location.name}</div>`);
                    popup.closePopup();
                }
            }, 50);
        }, fadeStartTime);
    }

    // Calculate faded color based on progress
    function calculateFadedColor(alertType, progress) {
        const baseColor = hexToRgb(icons[alertType].color);
        const targetColor = { r: 59, g: 130, b: 246 }; // blue-500
        
        return {
            r: Math.floor(baseColor.r + (targetColor.r - baseColor.r) * progress),
            g: Math.floor(baseColor.g + (targetColor.g - baseColor.g) * progress),
            b: Math.floor(baseColor.b + (targetColor.b - baseColor.b) * progress)
        };
    }

    // Convert hex color to RGB
    function hexToRgb(hex) {
        const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
        return result ? {
            r: parseInt(result[1], 16),
            g: parseInt(result[2], 16),
            b: parseInt(result[3], 16)
        } : {r: 0, g: 0, b: 0};
    }

    // Initialize the map with locations
    function initializeMap() {
        const locations = JSON.parse(document.getElementById('locations-data').textContent);
        
        locations.forEach(loc => {
            if (!loc.latitude || !loc.longitude) return;

            const marker = L.marker([loc.latitude, loc.longitude], {
                icon: loc.has_alert ? createAlertIcon(loc) : icons.default
            }).addTo(map);

            if (loc.has_alert) {
                setupAlertMarker(marker, loc);
            } else {
                marker.bindPopup(`<div>${loc.name}</div>`);
            }
        });

        // Fix map size after load
        setTimeout(() => map.invalidateSize(), 100);
    }

    // Initialize everything
    initAudioControls();
    initializeMap();
});