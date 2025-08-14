document.addEventListener('DOMContentLoaded', function() {
    const map = L.map('map').setView([10.508884, 122.957527], 12);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    const alertSound = document.getElementById('alertSound');
    const fadeDuration = 10000; // 10 seconds for fade effect
    const alertDuration = 300000; // 5 minutes total alert duration

    // Audio enable button
    const enableAudioBtn = document.getElementById('enableAudio');
    if (enableAudioBtn) {
        enableAudioBtn.addEventListener('click', function() {
            alertSound.volume = 0.7;
            alertSound.play().then(() => {
                alertSound.pause();
                alertSound.currentTime = 0;
                this.style.display = 'none';
                localStorage.setItem('audioEnabled', 'true');
            }).catch(e => {
                console.error("Audio initialization failed:", e);
                this.textContent = "🔇 Click to enable sound (browser blocked)";
            });
        });
    }

    // Check if audio was previously enabled
    const audioEnabled = localStorage.getItem('audioEnabled') === 'true';
    if (audioEnabled && enableAudioBtn) {
        enableAudioBtn.style.display = 'none';
    }

    // Process each location
    locations.forEach(loc => {
        const locationAlert = serverAlerts.find(alert => 
            String(alert.sensor_id) === String(loc.sensor_id)
        );
        
        const alertState = manageAlertState(loc.sensor_id, locationAlert?.datetime);
        let marker;

        if (alertState.isActive) {
            // Create alert marker with appropriate styling
            const alertType = locationAlert?.type || 'general';
            const iconColor = alertType === 'rain' ? '#2563eb' : 
                            alertType === 'wind' ? '#f59e0b' : '#dc2626';
            const popupClass = alertType === 'rain' ? 'rain-alert' :
                             alertType === 'wind' ? 'wind-alert' : 'general-alert';

            const customHTMLIcon = L.divIcon({
                className: 'alert-pin',
                html: `<div class="custom-pin" style="color: ${iconColor};">
                        <span class="alert-icon">${alertType === 'rain' ? '🌧️' : alertType === 'wind' ? '💨' : '⚠️'}</span>
                        <span class="pin-label">${loc.name}</span>
                      </div>`,
                iconSize: [32, 40],
                iconAnchor: [16, 40],
            });

            marker = L.marker([loc.lat, loc.lon], { icon: customHTMLIcon }).addTo(map);
            
            const alertText = locationAlert?.text || `⚠️ Alert at ${loc.name}`;
            const popup = marker.bindPopup(`<div class="alert-popup ${popupClass}">${alertText}</div>`, {
                autoClose: false,
                closeOnClick: false,
                maxWidth: 300
            }).openPopup();

            // Play sound if enabled
            if (audioEnabled && alertSound && !sessionStorage.getItem(`alert_played_${loc.sensor_id}`)) {
                alertSound.currentTime = 0;
                alertSound.play()
                    .then(() => {
                        sessionStorage.setItem(`alert_played_${loc.sensor_id}`, 'true');
                        setTimeout(() => {
                            sessionStorage.removeItem(`alert_played_${loc.sensor_id}`);
                        }, alertState.timeRemaining);
                    })
                    .catch(e => console.error("Audio playback failed:", e));
            }

            // Fade effect
            const fadeStartTime = Math.max(0, alertState.timeRemaining - fadeDuration);
            
            setTimeout(() => {
                const startTime = Date.now();
                const fadeInterval = setInterval(() => {
                    const elapsed = Date.now() - startTime;
                    const progress = Math.min(elapsed / fadeDuration, 1);
                    
                    // Calculate fading color
                    const baseColor = hexToRgb(iconColor);
                    const targetColor = {r: 59, g: 130, b: 246}; // blue-500
                    
                    const r = Math.floor(baseColor.r + (targetColor.r - baseColor.r) * progress);
                    const g = Math.floor(baseColor.g + (targetColor.g - baseColor.g) * progress);
                    const b = Math.floor(baseColor.b + (targetColor.b - baseColor.b) * progress);

                    marker.setIcon(L.divIcon({
                        html: `<div class="custom-pin" style="color: rgb(${r},${g},${b});">
                                <span class="alert-icon">${alertType === 'rain' ? '🌧️' : alertType === 'wind' ? '💨' : '⚠️'}</span>
                                <span class="pin-label">${loc.name}</span>
                              </div>`,
                        iconSize: [32, 40],
                        iconAnchor: [16, 40],
                    }));

                    if (progress >= 1) {
                        clearInterval(fadeInterval);
                        // Switch to normal marker
                        marker.setIcon(L.icon({
                            iconUrl: 'https://unpkg.com/leaflet/dist/images/marker-icon.png',
                            iconSize: [25, 41],
                            iconAnchor: [12, 41],
                        }));
                        marker.setPopupContent(`<div>${loc.name}</div>`);
                        popup.closePopup();
                    }
                }, 50);
            }, fadeStartTime);

            // Auto-close popup after 8 seconds
            setTimeout(() => popup.closePopup(), 8000);

        } else {
            // Normal marker
            marker = L.marker([loc.lat, loc.lon]).addTo(map);
            marker.bindPopup(`<div>${loc.name}</div>`);
        }
    });

    // Helper function to convert hex to RGB
    function hexToRgb(hex) {
        const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
        return result ? {
            r: parseInt(result[1], 16),
            g: parseInt(result[2], 16),
            b: parseInt(result[3], 16)
        } : {r: 0, g: 0, b: 0};
    }

    // Fix map size
    setTimeout(() => map.invalidateSize(), 100);
});

// Improved alert state management
function manageAlertState(sensorId, alertDatetime) {
    const storageKey = `alert_${sensorId}`;
    const now = new Date().getTime();
    
    if (!alertDatetime) {
        const storedEndTime = localStorage.getItem(storageKey);
        if (storedEndTime && now < parseInt(storedEndTime)) {
            return {
                isActive: true,
                timeRemaining: parseInt(storedEndTime) - now
            };
        }
        localStorage.removeItem(storageKey);
        return { isActive: false };
    }
    
    const alertDate = new Date(alertDatetime).getTime();
    const alertAge = now - alertDate;
    const remainingTime = Math.max(0, alertDuration - alertAge);
    
    if (remainingTime > 0) {
        const endTime = now + remainingTime;
        localStorage.setItem(storageKey, endTime.toString());
        return {
            isActive: true,
            timeRemaining: remainingTime
        };
    }
    
    localStorage.removeItem(storageKey);
    return { isActive: false };
}