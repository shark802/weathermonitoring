# Enhanced SMS Alert System with Barangay Targeting

## Overview
Successfully enhanced the SMS alert system to send targeted alerts only to users in barangays affected by flood warnings based on ML predictions. This ensures users receive relevant alerts for their specific location.

## Features Implemented

### 1. User Dashboard Updates
- **Enhanced Flood Warning Display**: Updated user dashboard to show barangay-specific flood warnings
- **Real-time Updates**: AJAX integration for dynamic warning updates
- **Visual Indicators**: Color-coded warnings (Red/Orange/Yellow) based on risk level
- **Scrollable Interface**: Max height with overflow for multiple warnings

### 2. Targeted SMS Alert System
- **Barangay-Specific Targeting**: SMS alerts sent only to users in affected barangays
- **Smart User Retrieval**: Users matched by address field containing barangay name
- **Formatted Messages**: Customized SMS messages with barangay-specific information
- **Phone Number Formatting**: Automatic formatting for Philippine phone numbers

### 3. Enhanced ML Integration
- **Automatic SMS Triggering**: SMS alerts automatically sent when ML predicts flood risk
- **Risk-Based Messaging**: Different message content based on risk level (High/Moderate/Low)
- **Comprehensive Coverage**: All 24 barangays monitored and targeted as needed

## Technical Implementation

### 1. User Dashboard Enhancements

#### Template Updates (`weatherapp/templates/user_dashboard.html`)
```html
<!-- Enhanced flood warning section -->
<div>
    <h3 class="font-bold text-lg mb-2 text-gray-700 border-b pb-1">🚨 Flood Warnings by Barangay</h3>
    <div id="floodWarningContent" class="space-y-3 text-medium max-h-64 overflow-y-auto">
        {% if flood_warnings %}
            {% for warning in flood_warnings %}
                <div class="border rounded-lg p-3 {% if warning.risk_level == 'High' %}border-red-300 bg-red-50{% elif warning.risk_level == 'Moderate' %}border-orange-300 bg-orange-50{% else %}border-yellow-300 bg-yellow-50{% endif %}">
                    <!-- Warning content -->
                </div>
            {% endfor %}
        {% endif %}
    </div>
</div>
```

#### JavaScript Updates
- Dynamic flood warning updates via AJAX
- Color-coded risk level indicators
- Real-time data refresh every 10 seconds

### 2. SMS Targeting System

#### Core Functions (`weatherapp/sms_targeted_alerts.py`)

**User Retrieval by Barangay:**
```python
def get_users_by_barangay(barangay_name):
    """Get all users from a specific barangay for targeted SMS alerts."""
    cursor.execute("""
        SELECT u.user_id, u.name, u.phone_num, u.address
        FROM user u
        WHERE u.address LIKE %s AND u.phone_num IS NOT NULL AND u.phone_num != ''
    """, [f"%{barangay_name}%"])
```

**Targeted SMS Sending:**
```python
def send_targeted_sms_alerts(flood_warnings, predicted_rain_rate, predicted_duration, intensity_label):
    """Send targeted SMS alerts to users in barangays with flood warnings."""
    affected_users = get_users_by_affected_barangays(flood_warnings)
    
    for barangay, users in affected_users.items():
        # Create barangay-specific message
        sms_message = create_barangay_sms_message(...)
        
        # Send to each user in the barangay
        for user in users:
            send_single_sms(user['phone_num'], sms_message, ...)
```

**Message Creation:**
```python
def create_barangay_sms_message(barangay, warning, rain_rate, duration, intensity):
    """Create a targeted SMS message for a specific barangay."""
    message = f"🚨 FLOOD ALERT - {barangay.upper()} 🚨\n"
    message += f"Risk Level: {warning['risk_level']}\n"
    message += f"Predicted Rain: {rain_rate:.1f}mm over {duration:.0f}min\n"
    message += f"Intensity: {intensity}\n"
    message += f"Land Type: {warning['land_type'].replace('_', ' ').title()}\n"
    message += f"Message: {warning['message']}\n"
    message += f"Stay safe and monitor conditions!"
    return message
```

### 3. ML Integration

#### Enhanced Predictor (`weatherapp/ai/predictor.py`)
```python
# Step 5: Send Targeted SMS Alerts to Affected Barangays
try:
    from weatherapp.sms_targeted_alerts import send_targeted_sms_alerts
    
    sms_result = send_targeted_sms_alerts(
        flood_warnings, 
        predicted_rain_rate, 
        predicted_duration, 
        intensity_label
    )
    
    if sms_result["success"]:
        print(f"✅ SMS Alerts: {sms_result['total_sent']} sent, {sms_result['total_failed']} failed")
except Exception as e:
    print(f"❌ Error sending targeted SMS alerts: {e}")
```

## SMS Message Examples

### High Risk Alert (Poblacion)
```
🚨 FLOOD ALERT - POBLACION 🚨
Risk Level: High
Predicted Rain: 15.0mm over 120min
Intensity: Heavy
Land Type: Low Lying
Message: High flood risk in Poblacion due to predicted Heavy rain (15.0mm) over 120 minutes. High flood risk - prone to water accumulation.
Stay safe and monitor conditions!
```

### Moderate Risk Alert (Lag-asan)
```
🚨 FLOOD ALERT - LAG-ASAN 🚨
Risk Level: Moderate
Predicted Rain: 5.0mm over 60min
Intensity: Moderate
Land Type: Low Lying
Message: Moderate flood risk in Lag-asan due to predicted Moderate rain. High flood risk - prone to water accumulation.
Stay safe and monitor conditions!
```

## Benefits

### 1. **Targeted Communication**
- Users only receive alerts for their specific barangay
- Reduces alert fatigue from irrelevant notifications
- Improves alert effectiveness and user engagement

### 2. **Improved User Experience**
- Clear, location-specific information
- Visual indicators for quick risk assessment
- Real-time updates on dashboard

### 3. **Efficient Resource Usage**
- SMS costs reduced by targeting only affected areas
- Network load minimized
- Better emergency response coordination

### 4. **Enhanced Safety**
- Users get timely, relevant warnings
- Location-specific risk information
- Clear action guidance based on land type

## System Flow

1. **ML Prediction**: Weather data analyzed for flood risk
2. **Barangay Assessment**: Each of 24 barangays evaluated based on land type
3. **Warning Generation**: Flood warnings created for affected barangays
4. **User Targeting**: Users in affected barangays identified
5. **SMS Sending**: Targeted messages sent to relevant users only
6. **Dashboard Update**: Both admin and user dashboards updated with warnings

## Database Integration

### User Matching Strategy
- Users matched by `address` field containing barangay name
- Phone number validation and formatting
- Automatic filtering of users without phone numbers

### Warning Storage
- All flood warnings stored in `flood_warnings` table
- Barangay-specific information preserved
- Timestamp tracking for alert management

## Error Handling

### Robust Error Management
- Database connection error handling
- SMS API failure recovery
- User data validation
- Phone number formatting validation

### Fallback Mechanisms
- Graceful degradation if SMS service unavailable
- Database error logging
- User notification of system status

## Files Modified

1. `weatherapp/templates/user_dashboard.html` - Enhanced UI for barangay warnings
2. `weatherapp/views.py` - Updated user dashboard context with flood_warnings
3. `weatherapp/ai/predictor.py` - Enhanced ML integration with SMS targeting
4. `weatherapp/sms_targeted_alerts.py` - New SMS targeting system
5. `SMS_TARGETING_ENHANCEMENT.md` - This documentation

## Future Enhancements

1. **User Preferences**: Allow users to customize alert types and frequency
2. **Multi-language Support**: SMS messages in local languages
3. **Alert History**: Track and display alert history per user
4. **Geolocation Integration**: More precise user location matching
5. **Alert Confirmation**: User acknowledgment of received alerts

## Conclusion

The enhanced SMS alert system now provides targeted, location-specific flood warnings to users in affected barangays only. This improvement significantly enhances the effectiveness of emergency communications while reducing unnecessary alerts and improving user experience. The system integrates seamlessly with the existing ML prediction system and provides comprehensive coverage for all 24 barangays of Bago City.
