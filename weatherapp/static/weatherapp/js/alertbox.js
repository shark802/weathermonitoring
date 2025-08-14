document.addEventListener('DOMContentLoaded', function() {
    const ALERT_LIFETIME = 10 * 60 * 1000; // 10 minutes in milliseconds
    
    function updateAlerts() {
        const now = new Date();
        const alertItems = document.querySelectorAll('.alert-item');
        let activeAlerts = 0;
        
        alertItems.forEach(item => {
            const timestamp = item.dataset.timestamp;
            const alertTime = new Date(timestamp);
            const age = now - alertTime;
            
            if (age >= ALERT_LIFETIME) {
                // Fade out and remove expired alert
                item.style.transition = 'opacity 0.5s ease';
                item.style.opacity = '0';
                setTimeout(() => item.remove(), 500);
            } else {
                activeAlerts++;
                // Update opacity based on remaining time (optional visual effect)
                const remainingTime = ALERT_LIFETIME - age;
                const fadeStartTime = ALERT_LIFETIME - (2 * 60 * 1000); // Start fading 2 minutes before expiration
                
                if (remainingTime < fadeStartTime) {
                    const fadeProgress = 1 - ((remainingTime - fadeStartTime) / (2 * 60 * 1000));
                    item.style.opacity = 1 - (fadeProgress * 0.7); // Fade to 30% opacity
                }
            }
        });
        
        // Show "no alerts" message if all expired
        const alertsList = document.getElementById('alerts-list');
        if (activeAlerts === 0 && alertItems.length > 0) {
            const noAlertsMsg = document.createElement('p');
            noAlertsMsg.className = 'text-green-600';
            noAlertsMsg.textContent = '✅ No active alerts at this time.';
            alertsList.innerHTML = '';
            alertsList.appendChild(noAlertsMsg);
        }
    }
    
    // Check alerts every 30 seconds
    updateAlerts();
    setInterval(updateAlerts, 30000);
    
    // Add fade-in animation for new alerts
    const alertItems = document.querySelectorAll('.alert-item');
    alertItems.forEach(item => {
        item.style.opacity = '0';
        setTimeout(() => {
            item.style.transition = 'opacity 0.3s ease';
            item.style.opacity = '1';
        }, 100);
    });
});