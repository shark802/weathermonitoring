"""
Targeted SMS Alert System for Barangay-Specific Flood Warnings
This module handles sending SMS alerts only to users in affected barangays.
"""

import requests
from django.conf import settings
from django.db import connection
from weatherapp.ai.predictor import get_users_by_affected_barangays


def send_targeted_sms_alerts(flood_warnings, predicted_rain_rate, predicted_duration, intensity_label):
    """
    Send targeted SMS alerts to users in barangays with flood warnings.
    
    Args:
        flood_warnings (list): List of flood warning dictionaries
        predicted_rain_rate (float): Predicted rainfall rate
        predicted_duration (float): Predicted duration
        intensity_label (str): Rain intensity label
        
    Returns:
        dict: Summary of SMS sending results
    """
    if not flood_warnings:
        return {"success": True, "message": "No flood warnings to send", "total_sent": 0}
    
    try:
        affected_users = get_users_by_affected_barangays(flood_warnings)
        
        if not affected_users:
            return {"success": True, "message": "No users found in affected barangays", "total_sent": 0}
        
        # Setup SMS parameters
        headers = {
            "apikey": settings.SMS_API_KEY,
            "Content-Type": "application/x-www-form-urlencoded"
        }
        
        session = requests.Session()
        session.verify = False  # Disable SSL verification if needed
        
        total_sent = 0
        total_failed = 0
        results = {}
        
        print(f"\n--- SENDING TARGETED SMS ALERTS ---")
        
        for barangay, users in affected_users.items():
            # Get the warning for this barangay
            barangay_warning = next((w for w in flood_warnings if w['barangay'] == barangay), None)
            
            if not barangay_warning or not users:
                continue
                
            print(f"📱 Sending alerts to {len(users)} users in {barangay} ({barangay_warning['risk_level']} risk)")
            
            # Create targeted message for this barangay
            sms_message = create_barangay_sms_message(
                barangay, barangay_warning, predicted_rain_rate, predicted_duration, intensity_label
            )
            
            barangay_sent = 0
            barangay_failed = 0
            
            # Send SMS to each user in this barangay
            for user in users:
                try:
                    # Format phone number
                    formatted_phone = format_phone_number(user['phone_num'])
                    
                    # Send SMS
                    success = send_single_sms(formatted_phone, sms_message, headers, session)
                    
                    if success:
                        barangay_sent += 1
                        total_sent += 1
                        print(f"   ✅ Sent to {user['name']} ({formatted_phone})")
                    else:
                        barangay_failed += 1
                        total_failed += 1
                        print(f"   ❌ Failed to send to {user['name']} ({formatted_phone})")
                        
                except Exception as e:
                    barangay_failed += 1
                    total_failed += 1
                    print(f"   ❌ Error sending to {user['name']}: {e}")
            
            results[barangay] = {
                "users_count": len(users),
                "sent": barangay_sent,
                "failed": barangay_failed
            }
        
        print(f"✅ SMS Alert Summary: {total_sent} sent, {total_failed} failed")
        
        return {
            "success": True,
            "total_sent": total_sent,
            "total_failed": total_failed,
            "results": results,
            "message": f"Sent {total_sent} SMS alerts to affected barangays"
        }
        
    except Exception as e:
        print(f"❌ Error in targeted SMS alerts: {e}")
        return {
            "success": False,
            "error": str(e),
            "total_sent": 0,
            "total_failed": 0
        }


def create_barangay_sms_message(barangay, warning, rain_rate, duration, intensity):
    """
    Create a targeted SMS message for a specific barangay.
    
    Args:
        barangay (str): Barangay name
        warning (dict): Warning information
        rain_rate (float): Predicted rainfall rate
        duration (float): Predicted duration
        intensity (str): Rain intensity
        
    Returns:
        str: Formatted SMS message
    """
    message = f"🚨 FLOOD ALERT - {barangay.upper()} 🚨\n"
    message += f"Risk Level: {warning['risk_level']}\n"
    message += f"Predicted Rain: {rain_rate:.1f}mm over {duration:.0f}min\n"
    message += f"Intensity: {intensity}\n"
    message += f"Land Type: {warning['land_type'].replace('_', ' ').title()}\n"
    message += f"Message: {warning['message']}\n"
    message += f"Stay safe and monitor conditions!"
    
    return message


def format_phone_number(phone_num):
    """
    Format phone number for SMS API.
    
    Args:
        phone_num (str): Raw phone number
        
    Returns:
        str: Formatted phone number
    """
    if not phone_num:
        return None
        
    # Remove any spaces or special characters
    phone_num = phone_num.strip().replace(" ", "").replace("-", "")
    
    # Format for Philippines
    if phone_num.startswith("09"):
        return "+63" + phone_num[1:]
    elif phone_num.startswith("9") and len(phone_num) == 10:
        return "+63" + phone_num
    elif not phone_num.startswith("+63"):
        return "+63" + phone_num
    else:
        return phone_num


def send_single_sms(phone_number, message, headers, session):
    """
    Send a single SMS message.
    
    Args:
        phone_number (str): Formatted phone number
        message (str): SMS message
        headers (dict): HTTP headers
        session (requests.Session): HTTP session
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        parameters = {
            'message': message,
            'mobile_number': phone_number,
            'device': settings.SMS_DEVICE_ID,
            'device_sim': '1'
        }
        
        response = session.post(
            settings.SMS_API_URL,
            data=parameters,
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            return True
        else:
            print(f"   SMS API Error: {response.status_code} - {response.text}")
            return False
            
    except Exception as e:
        print(f"   SMS sending error: {e}")
        return False


def get_sms_alert_summary(flood_warnings):
    """
    Get a summary of SMS alert requirements without sending.
    
    Args:
        flood_warnings (list): List of flood warning dictionaries
        
    Returns:
        dict: Summary of alert requirements
    """
    if not flood_warnings:
        return {"total_barangays": 0, "total_users": 0, "barangays": []}
    
    try:
        affected_users = get_users_by_affected_barangays(flood_warnings)
        
        summary = {
            "total_barangays": len(affected_users),
            "total_users": sum(len(users) for users in affected_users.values()),
            "barangays": []
        }
        
        for barangay, users in affected_users.items():
            warning = next((w for w in flood_warnings if w['barangay'] == barangay), None)
            summary["barangays"].append({
                "name": barangay,
                "risk_level": warning['risk_level'] if warning else "Unknown",
                "user_count": len(users),
                "users": [{"name": user['name'], "phone": user['phone_num']} for user in users]
            })
        
        return summary
        
    except Exception as e:
        return {"error": str(e), "total_barangays": 0, "total_users": 0}
