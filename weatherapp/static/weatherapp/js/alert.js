document.addEventListener('DOMContentLoaded', function() {
    // Initialize map with center from Django context or default
    const mapCenter = window.mapCenter || { lat: 10.508884, lng: 122.957527 };
    const map = L.map('map').setView([mapCenter.lat, mapCenter.lng], 12);
    
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    // Configuration
    const ALERT_DURATION = 600000;
    const FADE_DURATION = 10000;
    const POPUP_DURATION = 8000;

    // Audio setup
    const alertSound = document.getElementById('alertSound');
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

    function isAlertActive(alertDateTime) {
        if (!alertDateTime) return false;
        
        const alertTime = new Date(alertDateTime).getTime();
        const currentTime = new Date().getTime();
        return (currentTime - alertTime) < ALERT_DURATION;
    }

    // Create appropriate alert icon
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
        if (!alertText) return 'general';
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

        // Set up fade effect
        setupFadeEffect(marker, location, popup, alertType);

        // Auto-close popup after duration
        setTimeout(() => popup.closePopup(), POPUP_DURATION);
    }

    // Play alert sound with session tracking
    function playAlertSound(sensorId) {
        if (!sensorId || sessionStorage.getItem(`alert_played_${sensorId}`)) return;
        
        alertSound.currentTime = 0;
        alertSound.play()
            .then(() => {
                sessionStorage.setItem(`alert_played_${sensorId}`, 'true');
                setTimeout(() => {
                    sessionStorage.removeItem(`alert_played_${sensorId}`);
                }, ALERT_DURATION);
            })
            .catch(e => console.error("Audio playback failed:", e));
    }

    // Set up color fade effect for alert markers
    function setupFadeEffect(marker, location, popup, alertType) {
        const alertTime = new Date(location.date_time).getTime();
        const currentTime = new Date().getTime();
        const alertEndTime = alertTime + ALERT_DURATION;
        const remainingTime = alertEndTime - currentTime;
        
        if (remainingTime <= 0) return;

        const fadeStartTime = Math.max(0, remainingTime - FADE_DURATION);
        
        setTimeout(() => {
            const startTime = Date.now();
            const fadeInterval = setInterval(() => {
                const elapsed = Date.now() - startTime;
                const progress = Math.min(elapsed / FADE_DURATION, 1);
                
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
        const locationsData = document.getElementById('locations-data').textContent;
        const locations = locationsData ? JSON.parse(locationsData) : [];
        
        // Clear existing markers if any (for refresh scenarios)
        if (window.mapMarkers) {
            window.mapMarkers.forEach(marker => map.removeLayer(marker));
        }
        window.mapMarkers = [];

        locations.forEach(loc => {
            // Skip if missing coordinates
            if (!loc.latitude || !loc.longitude) return;

            // Check if alert is active (exists and within time window)
            const hasActiveAlert = loc.has_alert && isAlertActive(loc.date_time);
            
            // Create marker with appropriate icon
            const marker = L.marker([loc.latitude, loc.longitude], {
                icon: hasActiveAlert ? createAlertIcon(loc) : icons.default
            }).addTo(map);

            // Store reference to marker
            window.mapMarkers.push(marker);

            // Configure popup based on alert status
            if (hasActiveAlert) {
                setupAlertMarker(marker, loc);
            } else {
                marker.bindPopup(`<div class="location-popup">${loc.name}</div>`);
            }

            // Add click event to zoom to marker
            marker.on('click', function() {
                map.setView([loc.latitude, loc.longitude], 15);
            });
        });

        // Fix map size after load
        setTimeout(() => {
            map.invalidateSize();
            
            if (locations.length > 0 && locations.some(loc => loc.latitude && loc.longitude)) {
                const markerGroup = new L.FeatureGroup(window.mapMarkers);
                map.fitBounds(markerGroup.getBounds().pad(0.2));
            }
        }, 100);
    }

    // Initialize everything
    initAudioControls();
    initializeMap();

    // Optional: Auto-refresh every 5 minutes
    setTimeout(() => {
        window.location.reload();
    }, 300000);
});