from django.shortcuts import render, redirect
from django.db import connection
from django.contrib import messages
from django.contrib.auth.hashers import make_password
from django.contrib.auth.hashers import check_password
from django.http import HttpResponseForbidden
from django.http import HttpResponseNotAllowed
from django.views.decorators.cache import cache_control
from django.utils.timezone import now
import random
from django.core.mail import send_mail
from django.conf import settings
from .forecast import get_five_day_forecast
import json
from django.views.decorators.csrf import csrf_exempt
from django.http import HttpResponse
import re
import os
from django.core.files.storage import FileSystemStorage
from django.http import JsonResponse
from datetime import datetime, timedelta, date, timezone
from datetime import time as time_class
from calendar import month_name
import pytz
from decimal import Decimal
import requests
import certifi
import time
from django.conf import settings
import jwt
import base64
from nacl.signing import VerifyKey
from nacl.exceptions import BadSignatureError
import logging
import sys
import urllib.parse 

utc_plus_8 = timezone(timedelta(hours=8))

logger = logging.getLogger(__name__)

def register_user(request):
    if request.method != 'POST':
        return JsonResponse({
            'success': False,
            'errors': {'method': 'POST request required'}
        })

    errors = {}

    # Get and format name components
    first_name = request.POST.get('firstName', '').strip().upper()
    middle_name = request.POST.get('middleName', '').strip().upper()
    last_name = request.POST.get('lastName', '').strip().upper()
    name = ' '.join(filter(None, [first_name, middle_name, last_name]))

    # Get and format address components
    province = request.POST.get('province', '').strip().upper()
    province_name = (request.POST.get('province_name') or '').strip().title()
    city = request.POST.get('city', '').strip().upper()
    city_name = (request.POST.get('city_name') or '').strip().title()
    barangay = request.POST.get('barangay', '').strip().upper()
    barangay_name = (request.POST.get('barangay_name') or '').strip().title()
    address = ', '.join(filter(None, [barangay_name, city_name, province_name]))

    # Other fields
    email = request.POST.get('regEmail')
    phone = request.POST.get('regPhone')
    username = request.POST.get('regUsername')
    password = request.POST.get('regPassword')
    confirm_password = request.POST.get('confirm_Password')
    qr_data = request.POST.get('qr_data')

    # QR validation
    if not qr_data:
        errors['qr_data'] = "Please scan your PhilSys QR code"
    else:
        try:
            try:
                # Try JSON parse (EdDSA format)
                qr_json = json.loads(qr_data)
                alg = qr_json.get("alg", "").upper()

                if alg == "EDDSA":
                    signature_b64 = qr_json.pop("signature", None)
                    if not signature_b64:
                        errors['qr_data'] = "QR signature missing."
                    else:
                        psa_key = getattr(settings, 'PSA_ED25519_PUBLIC_KEY', None)
                        if psa_key:
                            try:
                                verify_key = VerifyKey(base64.b64decode(psa_key))
                                signed_content = json.dumps(qr_json, separators=(',', ':')).encode()
                                verify_key.verify(signed_content, base64.b64decode(signature_b64))
                            except BadSignatureError:
                                errors['qr_invalid'] = "Invalid PhilSys QR signature"
                        else:
                            logger.warning("PSA_ED25519_PUBLIC_KEY is not set — skipping QR signature verification.")

                    # Extract name fields
                    phil_first = qr_json.get("subject", {}).get("fName", "").upper()
                    phil_middle = qr_json.get("subject", {}).get("mName", "").upper()
                    phil_last = qr_json.get("subject", {}).get("lName", "").upper()
                    phil_barangay = ""
                    phil_city = ""
                    phil_province = ""

                else:
                    raise ValueError("Not EdDSA JSON QR")

            except json.JSONDecodeError:
                # Fallback: JWT RS256 format
                decoded = jwt.decode(qr_data, key=settings.PSA_PUBLIC_KEY, algorithms=["RS256"])
                phil_first = decoded.get('givenName', '').upper()
                phil_middle = decoded.get('middleName', '').upper()
                phil_last = decoded.get('familyName', '').upper()
                phil_barangay = decoded.get('address', {}).get('barangay', '').upper()
                phil_city = decoded.get('address', {}).get('city', '').upper()
                phil_province = decoded.get('address', {}).get('province', '').upper()

            # Name match
            if (first_name != phil_first or 
                last_name != phil_last or 
                (middle_name and middle_name != phil_middle)):
                errors['name_mismatch'] = "Name doesn't match PhilSys ID"

            # Address match
            if any([phil_province, phil_city, phil_barangay]):
                if ((province and province not in phil_province) or
                    (city and city not in phil_city) or
                    (barangay and barangay not in phil_barangay)):
                    errors['address_mismatch'] = "Address doesn't match PhilSys ID"

        except jwt.InvalidSignatureError:
            errors['qr_invalid'] = "Invalid PhilSys QR signature"
        except Exception as e:
            errors['qr_error'] = f"QR verification failed: {str(e)}"

    # Email validation
    if not re.match(r"[^@]+@[^@]+\.[^@]+", email):
        errors['regEmail'] = "Invalid email format."

    # Phone validation
    if not re.match(r"^\d{11}$", phone):
        errors['regPhone'] = "Phone number must be exactly 11 digits."

    # Password validation
    if len(password) < 8:
        errors['regPassword'] = "Password must be at least 8 characters long."
    elif not re.search(r'[A-Z]', password):
        errors['regPassword'] = "Password must contain at least one uppercase letter."
    elif not re.search(r'[a-z]', password):
        errors['regPassword'] = "Password must contain at least one lowercase letter."
    elif not re.search(r'\d', password):
        errors['regPassword'] = "Password must contain at least one number."
    elif not re.search(r'[!@#$%^&*(),.?\":{}|<>]', password):
        errors['regPassword'] = "Password must contain at least one special character."

    if password != confirm_password:
        errors['confirm_Password'] = "Passwords do not match."

    # Database checks
    with connection.cursor() as cursor:
        cursor.execute("SELECT user_id FROM user WHERE username = %s", [username])
        if cursor.fetchone():
            errors['regUsername'] = "Username already taken."

        cursor.execute("SELECT user_id FROM user WHERE name = %s", [name])
        if cursor.fetchone():
            errors['name'] = "Name already exists."
            
        cursor.execute("SELECT user_id FROM user WHERE phone_num = %s", [phone])
        if cursor.fetchone():
            errors['regPhone'] = "Phone number already taken."
            
        cursor.execute("SELECT user_id FROM user WHERE email = %s", [email])
        if cursor.fetchone():
            errors['regEmail'] = "Email already taken."

    if errors:
        return JsonResponse({'success': False, 'errors': errors})

    # Save user
    hashed_password = make_password(password)
    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO user (
                    name,
                    address,
                    email, 
                    phone_num, 
                    username, 
                    password, 
                    verified_with_philsys
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, [
                name,
                address,
                email,
                phone,
                username,
                hashed_password,
                bool(qr_data)
            ])

        return JsonResponse({
            'success': True,
            'message': "Registration successful!",
            'user_data': {
                'full_name': name,
                'address': address,
                'philsys_verified': bool(qr_data)
            }
        })

    except Exception as e:
        return JsonResponse({'success': False, 'errors': {'database': str(e)}})

def check_username(request):
     username = request.GET.get('username')
     if not username:
         return JsonResponse({'exists': False})
    
     with connection.cursor() as cursor:
         cursor.execute("SELECT user_id FROM user WHERE username = %s", [username])
         exists = cursor.fetchone() is not None
    
     return JsonResponse({'exists': exists})
 
def check_name(request):
    first_name = request.GET.get('firstName', '').strip().upper()
    middle_name = request.GET.get('middleName', '').strip().upper()
    last_name = request.GET.get('lastName', '').strip().upper()

    # Construct full name exactly how you store it in DB
    name = ' '.join(filter(None, [first_name, middle_name, last_name]))

    if not name:
        return JsonResponse({'exists': False})
    
    with connection.cursor() as cursor:
        cursor.execute("SELECT user_id FROM user WHERE name = %s", [name])
        exists = cursor.fetchone() is not None

    return JsonResponse({'exists': exists})
 
def check_phone(request):
     phone_num = request.GET.get('phone_num')
     if not phone_num:
         return JsonResponse({'exists': False})
    
     with connection.cursor() as cursor:
         cursor.execute("SELECT user_id FROM user WHERE phone_num = %s", [phone_num])
         exists = cursor.fetchone() is not None
    
     return JsonResponse({'exists': exists})
 
def check_email(request):
     email = request.GET.get('email')
     if not email:
         return JsonResponse({'exists': False})
    
     with connection.cursor() as cursor:
         cursor.execute("SELECT user_id FROM user WHERE email = %s", [email])
         exists = cursor.fetchone() is not None
    
     return JsonResponse({'exists': exists})


def home(request):
    
    logout_success = request.session.pop('form_logoutSuccess', None)
    
    return render(request, 'home.html', {
        'form_logoutSuccess': logout_success
    })


def set_session_expiry(request, remember_me):
    """Set session expiry based on 'Remember Me' checkbox."""
    request.session.set_expiry(30 * 24 * 60 * 60 if remember_me == 'on' else 0)

def login_view(request):
    if request.method == "POST":
        username = request.POST.get('username')
        password = request.POST.get('password')
        remember_me = request.POST.get('remember_me')

        # Try user login
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT user_id, username, password FROM user WHERE username = %s",
                [username]
            )
            user_data = cursor.fetchone()

        if user_data:
            user_id, db_username, db_hashed_password = user_data
            if check_password(password, db_hashed_password):
                request.session['user_id'] = user_id
                request.session['username'] = db_username
                set_session_expiry(request, remember_me)
                return redirect('user_dashboard')
            else:
                form_loginError = "Invalid username or password."
        
        else:
            # Try admin login
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT admin_id, username, password, status FROM admin WHERE username = %s",
                    [username]
                )
                admin_data = cursor.fetchone()

            if admin_data:
                admin_id, db_username, db_hashed_password, status = admin_data
                if status != 'Active':
                    form_loginError = "Account has been deactivated."
                elif check_password(password, db_hashed_password):
                    request.session['admin_id'] = admin_id
                    request.session['username'] = db_username
                    set_session_expiry(request, remember_me)
                    return redirect('admin_dashboard')
                else:
                    form_loginError = "Invalid username or password."
            else:
                form_loginError = "Invalid username or password."

        return render(request, 'home.html', {
            'show_login_modal': True,
            'login_username': username,
            'form_loginError': form_loginError
        })

    return render(request, 'home.html')


def forgot_password(request):
    if request.method == "POST":
        email = request.POST.get("email")
        cursor = connection.cursor()

        cursor.execute("SELECT * FROM admin WHERE email = %s", [email])
        admin_result = cursor.fetchone()

        cursor.execute("SELECT * FROM user WHERE email = %s", [email])
        user_result = cursor.fetchone()

        if not admin_result and not user_result:
            messages.error(request, "Email not found in our records.")
            return render(request, "forgot_password.html")

        otp = random.randint(100000, 999999)
        request.session['otp'] = otp
        request.session['reset_email'] = email
        request.session['source_table'] = 'admin' if admin_result else 'user'

        try:
            send_mail(
                subject='WeatherAlert Password Reset OTP',
                message=f'Your OTP for resetting your password is: {otp}',
                from_email=settings.EMAIL_HOST_USER,
                recipient_list=[email],
                fail_silently=False,
            )
            return redirect('verify_otp')
        except Exception as e:
            messages.error(request, "Failed to send email. Please try again.")
            return render(request, "forgot_password.html")

    return render(request, "forgot_password.html")

def verify_otp(request):
    if request.method == 'POST':
        entered_otp = request.POST.get('otp')
        session_otp = str(request.session.get('otp'))

        if entered_otp == session_otp:
            return redirect('reset_password')
        else:
            messages.error(request, "Invalid OTP. Please try again.")
            return render(request, 'verify_otp.html')

    return render(request, 'verify_otp.html')

def reset_password(request):
    if request.method == 'POST':
        new_password = request.POST.get('new_password')
        confirm_password = request.POST.get('confirm_password')
        email = request.session.get('reset_email')
        source_table = request.session.get('source_table')

        if new_password != confirm_password:
            messages.error(request, "Passwords do not match.")
            return render(request, 'reset_password.html')

        hashed_password = make_password(new_password)
        cursor = connection.cursor()

        if source_table == 'admin':
            cursor.execute("UPDATE admin SET password = %s WHERE email = %s", [hashed_password, email])
        elif source_table == 'user':
            cursor.execute("UPDATE user SET password = %s WHERE email = %s", [hashed_password, email])
        else:
            messages.error(request, "Invalid source. Cannot reset password.")
            return render(request, 'reset_password.html')

        messages.success(request, "Password successfully reset. You can now log in.")
        return redirect('home')

    return render(request, 'reset_password.html')

def get_rain_intensity(amount_mm_hr):
    """
    Determines the rain intensity based on amount in mm/hr, 
    using the standard PAGASA/Philippine Weather Service scale.
    """
    # Standard PAGASA 1-hour Intensity Thresholds (mm/hr)
    LIGHT_TO_MODERATE = 2.5    # 2.5 mm/hr
    MODERATE_TO_HEAVY = 7.5    # 7.5 mm/hr (or 7.6 depending on source)
    HEAVY_TO_INTENSE  = 15     # 15 mm/hr
    INTENSE_TO_TORRENTIAL = 30 # 30 mm/hr

    if amount_mm_hr is None or amount_mm_hr <= 0:
        return "None"
    elif amount_mm_hr < LIGHT_TO_MODERATE:
        return "Light"
    elif amount_mm_hr < MODERATE_TO_HEAVY:
        return "Moderate"
    elif amount_mm_hr < HEAVY_TO_INTENSE:
        return "Heavy"
    elif amount_mm_hr < INTENSE_TO_TORRENTIAL:
        return "Intense"
    else:
        return "Torrential"
    
def get_wind_signal(wind_speed_mps):
    """
    Determines the Tropical Cyclone Wind Signal (TCWS) based on 
    sustained wind speed in meters per second (m/s).
    """
    if wind_speed_mps is None or wind_speed_mps < 0:
        return "No Signal"

    # Convert PAGASA km/h thresholds to m/s by dividing by 3.6
    
    # Sig. 1: 30-60 km/h (8.33 to 16.67 m/s)
    SIG1_MIN = 30 / 3.6  # 8.33... m/s
    SIG2_MIN = 61 / 3.6  # 16.94... m/s
    SIG3_MIN = 101 / 3.6 # 28.05... m/s
    SIG4_MIN = 151 / 3.6 # 41.94... m/s
    SIG5_MIN = 201 / 3.6 # 55.83... m/s (200 km/h is the max for Sig 4)
    
    if wind_speed_mps < SIG1_MIN:
        # Below the minimum for Signal No. 1 (30 km/h)
        return "No Signal"
    elif wind_speed_mps < SIG2_MIN:
        # Winds 30 to 60 km/h
        return "Signal No. 1"
    elif wind_speed_mps < SIG3_MIN:
        # Winds 61 to 100 km/h
        return "Signal No. 2"
    elif wind_speed_mps < SIG4_MIN:
        # Winds 101 to 150 km/h
        return "Signal No. 3"
    elif wind_speed_mps < SIG5_MIN:
        # Winds 151 to 200 km/h
        return "Signal No. 4"
    else:
        # Winds exceeding 200 km/h
        return "Signal No. 5"

def latest_dashboard_data(request):
    """
    Returns all dashboard data (weather, charts, alerts, AI forecast)
    as a single JSON response for AJAX auto-refresh.
    """
    try:
        selected_sensor_id = request.GET.get('sensor_id')
        
        # Convert to int if provided
        if selected_sensor_id:
            try:
                selected_sensor_id = int(selected_sensor_id)
            except ValueError:
                selected_sensor_id = None

        with connection.cursor() as cursor:
            # 1. Fetch Latest Weather Data
            if selected_sensor_id:
                cursor.execute("""
                    SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                        wr.wind_speed, wr.barometric_pressure, wr.altitude, wr.date_time, s.name, s.latitude, s.longitude, s.sensor_id
                    FROM weather_reports wr
                    JOIN sensor s ON wr.sensor_id = s.sensor_id
                    WHERE wr.sensor_id = %s
                    ORDER BY wr.date_time DESC
                    LIMIT 1
                """, [selected_sensor_id])
            else:
                cursor.execute("""
                    SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                        wr.wind_speed, wr.barometric_pressure, wr.altitude, wr.date_time, s.name, s.latitude, s.longitude, s.sensor_id
                    FROM weather_reports wr
                    JOIN sensor s ON wr.sensor_id = s.sensor_id
                    ORDER BY wr.date_time DESC
                    LIMIT 1
                """)
        
        row = cursor.fetchone()
        weather = {}
        if row:
            weather = {
                'temperature': row[0],
                'humidity': row[1],
                'rain_rate': row[2],
                'dew_point': row[3],
                'wind_speed': row[4],
                'barometric_pressure': row[5],
                'altitude': row[6],
                'date_time': row[7].strftime('%Y-%m-%d %H:%M:%S'),
                'location': row[8],
                'latitude': row[9],
                'longitude': row[10],
                'error': None
            }
            if not selected_sensor_id:
                selected_sensor_id = row[11]
        else:
            weather = {
                'error': 'No weather data available',
                'temperature': 'N/A',
                'humidity': 'N/A',
                'rain_rate': 'N/A',
                'dew_point': 'N/A',
                'wind_speed': 'N/A',
                'barometric_pressure': 'N/A',
                'altitude': 'N/A',
                'date_time': 'N/A',
                'location': 'Unknown',
                'latitude': None,
                'longitude': None
            }

        # 2. Prepare Chart Data (only for the selected sensor)
        chart_labels = []
        chart_data = []
        if selected_sensor_id:
            cursor.execute("""
                SELECT DATE_FORMAT(date_time, '%%a %%b %%d') AS label, temperature
                FROM weather_reports
                WHERE sensor_id = %s
                ORDER BY date_time DESC
                LIMIT 10
            """, [selected_sensor_id])
            rows = cursor.fetchall()
            for row in reversed(rows):
                chart_labels.append(row[0])
                chart_data.append(float(row[1]))

        # 3. Fetch AI Prediction
        forecast = {}
        cursor.execute("""
            SELECT predicted_rain, duration, intensity
            FROM ai_predictions
            ORDER BY created_at DESC
            LIMIT 1
        """)
        row = cursor.fetchone()
        if row:
            forecast = {
                'prediction': float(row[0]),
                'duration': float(row[1]),
                'intensity': row[2],
                'error': None
            }
        else:
            forecast = {'error': 'No AI prediction data available.'}
            
        # Fetch all recent flood warnings (last 24 hours) for barangay-specific display
        flood_warnings = []
        cursor.execute("""
            SELECT area, risk_level, message, prediction_date
            FROM flood_warnings
            WHERE prediction_date >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
            ORDER BY 
                CASE risk_level 
                    WHEN 'High' THEN 1 
                    WHEN 'Moderate' THEN 2 
                    WHEN 'Low' THEN 3 
                    ELSE 4 
                END,
                prediction_date DESC
        """)
        rows = cursor.fetchall()
        
        if rows:
            for row in rows:
                flood_warnings.append({
                    'area': row[0],
                    'risk_level': row[1],
                    'message': row[2],
                    'prediction_date': row[3].strftime('%Y-%m-%d %H:%M:%S') if row[3] else None
                })
        
        # For backward compatibility, keep the first warning as the main flood_warning
        flood_warning = flood_warnings[0] if flood_warnings else {'error': 'No recent flood warning data available.'}

        # 4. Fetch Alerts (the logic is copied directly from your original admin_dashboard view)
        alerts = []
        cursor.execute("""
            SELECT s.sensor_id, s.name, wr.rain_rate, wr.wind_speed, wr.date_time
            FROM sensor s
            LEFT JOIN weather_reports wr ON s.sensor_id = wr.sensor_id
            WHERE wr.date_time = (
                SELECT MAX(date_time) 
                FROM weather_reports 
                WHERE sensor_id = s.sensor_id
            ) OR wr.date_time IS NULL
        """)
        
        for row in cursor.fetchall():
            sensor_id, name, rain_rate, wind_speed, date_time = row

            # --- RAIN ALERT FIXES ---
            if rain_rate is not None:
                intensity = get_rain_intensity(rain_rate)
                
                # FIX: Use the rain_rate directly for display, as it's already in mm/hr
                rain_rate_mm_hr = rain_rate  
                
                # Check for PAGASA's 'Heavy', 'Intense', or 'Torrential' rainfall
                if intensity in ["Heavy", "Intense", "Torrential"]:
                    alerts.append({
                        'text': f"⚠️ {intensity} Rainfall Alert in {name} ({rain_rate_mm_hr:.1f} mm/hr) {date_time.strftime('%Y-%m-%d %H:%M:%S')}",
                        'timestamp': datetime.now().isoformat(),
                        'type': 'rain',
                        'intensity': intensity.lower(),
                        'sensor_id': sensor_id
                    })

            if wind_speed is not None:
                wind_signal = get_wind_signal(wind_speed)
                
                if wind_signal != "No Signal":
                    # Convert m/s to km/h for more contextual alert text
                    wind_speed_kmh = wind_speed * 3.6
                    
                    alerts.append({
                        'text': f"🚨 {wind_signal} (PAGASA) Wind Alert for {name} ({wind_speed:.1f} m/s or {wind_speed_kmh:.0f} km/h) {date_time.strftime('%Y-%m-%d %H:%M:%S')}",
                        'timestamp': datetime.now().isoformat(),
                        'type': 'wind',
                        'intensity': wind_signal.replace(" ", "_").lower(), 
                        'sensor_id': sensor_id
                    })
    
        # Return all data as a single JSON response
        return JsonResponse({
            'weather': weather,
            'alerts': alerts,
            'forecast': [forecast] if forecast.get('error') is None else [],
            'flood_warning': flood_warning,
            'flood_warnings': flood_warnings,  # Include all barangay warnings
            'chart_labels': chart_labels,
            'chart_data': chart_data,
        })
    
    except Exception as e:
        # Log the error for debugging
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"Error in latest_dashboard_data: {str(e)}")
        
        # Return error response
        return JsonResponse({
            'error': f'Server error: {str(e)}',
            'weather': {'error': 'Failed to fetch weather data'},
            'alerts': [],
            'forecast': [],
            'flood_warning': {'error': 'Failed to fetch flood warnings'},
            'flood_warnings': [],
            'chart_labels': [],
            'chart_data': [],
        }, status=500)

@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def admin_dashboard(request):
    """
    Renders the admin dashboard with real-time weather data, alerts,
    and a map of sensor locations.
    """
    if 'admin_id' not in request.session:
        return redirect('home')
    
    admin_id = request.session['admin_id']
    selected_sensor_id = request.GET.get('sensor_id')

    # Initialize lists/dictionaries
    alerts = []
    locations = []
    current_sensor_id = None
    weather = {}
    forecast = {}
    flood_warning = {}
    labels = []
    temps = []

    # Use a single `with` block for ALL database operations
    with connection.cursor() as cursor:
        # 1. Fetch admin name
        cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [admin_id])
        row = cursor.fetchone()
        admin_name = row[0] if row else 'Admin'
        
        # 2. Fetch available sensors
        cursor.execute("SELECT sensor_id, name FROM sensor ORDER BY name")
        available_sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]

        # 3. Get latest weather data for the main card (current sensor)
        if selected_sensor_id:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.barometric_pressure, wr.date_time, s.name, s.latitude, s.longitude, s.sensor_id
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                WHERE wr.sensor_id = %s
                ORDER BY wr.date_time DESC
                LIMIT 1
            """, [selected_sensor_id])
        else:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.barometric_pressure, wr.date_time, s.name, s.latitude, s.longitude, s.sensor_id
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                ORDER BY wr.date_time DESC
                LIMIT 1
            """)
        
        row = cursor.fetchone()
        if row:
            weather = {
                'temperature': row[0], 'humidity': row[1], 'rain_rate': row[2], 
                'dew_point': row[3], 'wind_speed': row[4], 'barometric_pressure': row[5], 
                'date_time': row[6].strftime('%Y-%m-%d %H:%M:%S'), 'location': row[7], 
                'latitude': row[8], 'longitude': row[9], 'error': None
            }
            current_sensor_id = selected_sensor_id if selected_sensor_id else row[10] 
        else:
             weather = {
                'error': 'No weather data available', 'temperature': 'N/A', 
                'humidity': 'N/A', 'rain_rate': 'N/A', 'dew_point': 'N/A', 
                'wind_speed': 'N/A', 'barometric_pressure': 'N/A', 
                'date_time': 'N/A', 'location': 'Unknown', 
                'latitude': None, 'longitude': None
            }

        # 4. Forecast Data (Logic retained from original)
        # Get today's date in the UTC+8 timezone
        today_utc8 = datetime.now(utc_plus_8).date() 

        # Combine today's date (in UTC+8) with midnight (00:00:00) 
        # and explicitly set the timezone to UTC+8.
        today_start = datetime.combine(today_utc8, time_class(0, 0, 0)).astimezone(utc_plus_8)

        # Convert to string in '%Y-%m-%d %H:%M:%S' format. 
        # Note: The database query will now look for timestamps *after*
        # the start of the day in UTC+8.
        today_start_str = today_start.strftime('%Y-%m-%d %H:%M:%S')

        cursor.execute("""
            SELECT predicted_rain, duration, intensity, created_at
            FROM ai_predictions
            WHERE created_at >= %s
            ORDER BY created_at DESC
            LIMIT 1
        """, (today_start_str,))

        row = cursor.fetchone()
        if row:
            # Assuming 'created_at' (row[3]) is a datetime object 
            # that may or may not be timezone-aware.
            forecast = {
                'prediction': float(row[0]), 'duration': float(row[1]), 
                'intensity': row[2], 'created_at': row[3].strftime('%Y-%m-%d %H:%M:%S'), 
                'error': None
            }
        else:
            forecast = {'error': 'No AI prediction data available for today.'}
        
        # 5. Flood Warning (Logic retained from original)
        cursor.execute("""
             SELECT area, risk_level, message
             FROM flood_warnings
             ORDER BY prediction_date DESC
             LIMIT 1
         """)
        row = cursor.fetchone()
        if row:
             flood_warning = {
                 'area': row[0], 'risk_level': row[1], 'message': row[2], 'error': None
             }
        else:
             flood_warning = {'error': 'No recent flood warning data available.'}

        # 6. Chart data (Logic retained from original)
        cursor.execute("""
             SELECT DATE_FORMAT(date_time, '%a %b %d') AS label, temperature
             FROM weather_reports
             ORDER BY date_time DESC
             LIMIT 10
         """)
        rows = cursor.fetchall()
        labels = [row[0] for row in rows]
        temps = [float(row[1]) for row in rows]

        # 7. Fetch all sensor locations for the map, PROCESS ALERTS, and build locations data
        cursor.execute("""
             SELECT s.sensor_id, s.name, s.latitude, s.longitude, s.radius,
                    wr.rain_rate, wr.wind_speed, wr.date_time
             FROM sensor s
             LEFT JOIN weather_reports wr ON s.sensor_id = wr.sensor_id
             WHERE wr.date_time = (
                 SELECT MAX(date_time) 
                 FROM weather_reports 
                 WHERE sensor_id = s.sensor_id
             ) OR wr.date_time IS NULL
         """)
        
        for row in cursor.fetchall():
            # FIX 1: Corrected comment to reflect database unit
            # Note: rain_rate is in mm/hr, wind_speed is in m/s 
            sensor_id, name, lat, lng, radius, rain_rate, wind_speed, date_time = row
            
            has_alert = False
            alert_text = ""
            # Ensure date_time_str is generated safely
            date_time_str = date_time.strftime('%Y-%m-%d %H:%M:%S') if date_time else ""

            # --- 1. RAINFALL ALERT (PAGASA Scale) ---
            rain_intensity_label = "None"
            if rain_rate is not None and rain_rate > 0:
                
                # FIX 2: The fetched rain_rate (mm/hr) is passed directly to the classification function.
                # Ensure you are using the mm/hr version of get_rain_intensity (without division by 60 in its definition).
                rain_intensity_label = get_rain_intensity(rain_rate)

                # FIX 3: rain_rate_mm_hr is the fetched value itself (no multiplication needed).
                rain_rate_mm_hr = rain_rate 

                # Check for PAGASA's highest alert levels (Heavy, Intense, Torrential)
                if rain_intensity_label in ["Heavy", "Intense", "Torrential"]:
                    
                    alert_msg = f"⚠️ {rain_intensity_label} Rainfall Alert in {name} ({rain_rate_mm_hr:.1f} mm/hr)"
                    
                    # Add to the UI Alerts List
                    alerts.append({
                        'text': alert_msg, 
                        'timestamp': date_time_str,
                        'location_name': name,
                        'type': 'rain', # Added
                        'severity': rain_intensity_label.lower(), # Added
                        'sensor_id': sensor_id # Added
                    })
                    alert_text += alert_msg + "<br>"
                    has_alert = True
                    
            # --- 2. WIND SIGNAL ALERT (PAGASA TCWS) ---
            wind_signal = "No Signal"
            if wind_speed is not None and wind_speed > 0:
                
                # Use the m/s data to get the PAGASA Wind Signal
                wind_signal = get_wind_signal(wind_speed)
                
                # Check if a TCWS is issued (Signal No. 1 or higher)
                if wind_signal != "No Signal":
                    
                    # Convert m/s to km/h for contextual display (m/s * 3.6)
                    wind_speed_kmh = wind_speed * 3.6
                    
                    alert_msg = f"🚨 {wind_signal} (PAGASA) Wind Alert in {name} ({wind_speed_kmh:.0f} km/h)"
                    
                    # Add to the UI Alerts List
                    alerts.append({
                        'text': alert_msg, 
                        'timestamp': date_time_str,
                        'location_name': name,
                        'type': 'wind', # Added
                        'severity': wind_signal.replace(" ", "_").lower(), # Added
                        'sensor_id': sensor_id # Added
                    })
                    alert_text += alert_msg + "<br>"
                    has_alert = True

            # Prepare enriched data for the map (JavaScript 'locations' array)
            locations.append({
                'sensor_id': sensor_id,
                'name': name,
                'latitude': float(lat) if lat is not None else None,
                'longitude': float(lng) if lng is not None else None,
                'rain_rate': float(rain_rate) if rain_rate is not None else None,
                'wind_speed': float(wind_speed) if wind_speed is not None else None,
                'date_time': date_time_str,
                'has_alert': has_alert, # <--- 🔑 Crucial field for JS map logic
                'alert_text': alert_text.strip('<br>'), # <--- 🔑 Crucial field for JS map logic popup/icon
                'radius': radius # Geo-fence radius
            })
            
    # Prepare final context for the template
    context = {
        'admin': {'name': admin_name},
        'locations': json.dumps(locations),
        'weather': weather,
        'forecast': [forecast] if forecast.get('error') is None else [],
        'flood_warning': flood_warning,
        'labels': json.dumps(labels),
        'data': json.dumps(temps),
        'available_sensors': available_sensors,
        'current_sensor_id': current_sensor_id,
        'alerts': alerts, # Alerts list for the sidebar/UI
        'map_center': { # For map initialization
            'lat': weather['latitude'] if weather['latitude'] else 10.508884,
            'lng': weather['longitude'] if weather['longitude'] else 122.957527
        }
    }

    return render(request, 'admin_dashboard.html', context)


@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def user_dashboard(request):
    if 'user_id' not in request.session:
        return redirect('home')
    
    user_id = request.session['user_id']
    selected_sensor_id = request.GET.get('sensor_id')
    
    alerts = []
    locations = []
    current_sensor_id = None
    weather = {}
    forecast = {}
    flood_warning = {}
    labels = []
    temps = []

    # ✅ Get logged-in user name
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM user WHERE user_id = %s", [user_id])
        row = cursor.fetchone()
        user_name = row[0] if row else 'User'
    
        cursor.execute("SELECT sensor_id, name FROM sensor ORDER BY name")
        available_sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]

        # 3. Get latest weather data for the main card (current sensor)
        if selected_sensor_id:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.barometric_pressure, wr.date_time, s.name, s.latitude, s.longitude, s.sensor_id
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                WHERE wr.sensor_id = %s
                ORDER BY wr.date_time DESC
                LIMIT 1
            """, [selected_sensor_id])
        else:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.barometric_pressure, wr.date_time, s.name, s.latitude, s.longitude, s.sensor_id
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                ORDER BY wr.date_time DESC
                LIMIT 1
            """)
        
        row = cursor.fetchone()
        if row:
            weather = {
                'temperature': row[0], 'humidity': row[1], 'rain_rate': row[2], 
                'dew_point': row[3], 'wind_speed': row[4], 'barometric_pressure': row[5], 
                'date_time': row[6].strftime('%Y-%m-%d %H:%M:%S'), 'location': row[7], 
                'latitude': row[8], 'longitude': row[9], 'error': None
            }
            current_sensor_id = selected_sensor_id if selected_sensor_id else row[10] 
        else:
             weather = {
                'error': 'No weather data available', 'temperature': 'N/A', 
                'humidity': 'N/A', 'rain_rate': 'N/A', 'dew_point': 'N/A', 
                'wind_speed': 'N/A', 'barometric_pressure': 'N/A', 
                'date_time': 'N/A', 'location': 'Unknown', 
                'latitude': None, 'longitude': None
            }

        # 4. Forecast Data (Logic retained from original)
        today_start = datetime.combine(date.today(), time_class(0, 0, 0))
        today_start_str = today_start.strftime('%Y-%m-%d %H:%M:%S')

        cursor.execute("""
             SELECT predicted_rain, duration, intensity, created_at
             FROM ai_predictions
             WHERE created_at >= %s
             ORDER BY created_at DESC
             LIMIT 1
         """, (today_start_str,)) 

        row = cursor.fetchone()
        if row:
             forecast = {
                 'prediction': float(row[0]), 'duration': float(row[1]), 
                 'intensity': row[2], 'created_at': row[3].strftime('%Y-%m-%d %H:%M:%S'), 
                 'error': None
             }
        else:
             forecast = {'error': 'No AI prediction data available for today.'}
        
        # 5. Flood Warning (Logic retained from original)
        cursor.execute("""
             SELECT area, risk_level, message
             FROM flood_warnings
             ORDER BY prediction_date DESC
             LIMIT 1
         """)
        row = cursor.fetchone()
        if row:
             flood_warning = {
                 'area': row[0], 'risk_level': row[1], 'message': row[2], 'error': None
             }
        else:
             flood_warning = {'error': 'No recent flood warning data available.'}

        # 6. Chart data (Logic retained from original)
        cursor.execute("""
             SELECT DATE_FORMAT(date_time, '%a %b %d') AS label, temperature
             FROM weather_reports
             ORDER BY date_time DESC
             LIMIT 10
         """)
        rows = cursor.fetchall()
        labels = [row[0] for row in rows]
        temps = [float(row[1]) for row in rows]

    # ✅ Alerts (initial load — AJAX will refresh later)
    alerts = []
    with connection.cursor() as cursor:
        # SQL FIX: Select sensor_id to correctly join and for potential use in the alert data
        # The SQL query is fine as it fetches the necessary fields.
        cursor.execute("""
            SELECT s.sensor_id, s.name, wr.rain_rate, wr.wind_speed, wr.date_time
            FROM sensor s
            JOIN weather_reports wr ON s.sensor_id = wr.sensor_id
            WHERE wr.date_time = (
                SELECT MAX(date_time) 
                FROM weather_reports 
                WHERE sensor_id = s.sensor_id
            )
        """)

        for row in cursor.fetchall():
            # Sensor ID is now included in the row data
            sensor_id, name, rain_rate, wind_speed, date_time = row
            # Ensure date_time is handled gracefully, though usually safe here.
            date_time_str = date_time.strftime('%Y-%m-%d %H:%M:%S') if date_time else "N/A" 

            # --- RAIN ALERT LOGIC (PAGASA, Display mm/hr) ---
            if rain_rate is not None and rain_rate > 0:
                
                # FIX 1: rain_rate is now treated as mm/hr, so it's passed directly.
                # (Requires get_rain_intensity to use mm/hr thresholds, e.g., 7.6, 15, 30)
                intensity = get_rain_intensity(rain_rate)

                # FIX 2: rain_rate is already mm/hr, so no multiplication is needed for display.
                rain_rate_mm_hr = rain_rate 

                # Trigger alert for PAGASA's highest levels
                if intensity in ["Heavy", "Intense", "Torrential"]:
                    alerts.append({
                        'text': f"⚠️ {intensity} Rainfall Alert in {name} ({rain_rate_mm_hr:.1f} mm/hr)",
                        'timestamp': date_time_str,
                        'sensor_id': sensor_id,
                        'type': 'rain',
                        'intensity': intensity.lower()
                    })

            # --- WIND ALERT LOGIC (PAGASA TCWS, Display km/h) ---
            if wind_speed is not None and wind_speed > 0:
                
                # Use the m/s sensor data to classify the Wind Signal
                wind_signal = get_wind_signal(wind_speed)
                
                # Convert to km/h for user-friendly display (m/s * 3.6)
                wind_speed_kmh = wind_speed * 3.6

                # Trigger alert if a Signal is issued (Signal No. 1 or higher)
                if wind_signal != "No Signal":
                    alerts.append({
                        'text': f"🚨 {wind_signal} (PAGASA) Wind Alert in {name} ({wind_speed_kmh:.0f} km/h)",
                        'timestamp': date_time_str,
                        'sensor_id': sensor_id,
                        'type': 'wind',
                        'intensity': wind_signal.replace(" ", "_").lower()
                    })

        # ✅ Send context to template
    context = {
        'user': {'name': user_name},
        'weather': weather,
        'forecast': [forecast] if forecast.get('error') is None else [],
        'flood_warning': flood_warning,
        'labels': json.dumps(labels),
        'data': json.dumps(temps),
        'available_sensors': available_sensors,
        'current_sensor_id': current_sensor_id,
        'alerts': alerts
    }
    
    return render(request, 'user_dashboard.html', context)


# 🔔 AJAX endpoint for auto-refresh alerts
def get_alerts(request):
    try:
        alerts = []
        
        # 1. Get sensor-based alerts
        with connection.cursor() as cursor:
            # SQL FIX: Select sensor_id (or other unique ID) for a proper alert key
            cursor.execute("""
                SELECT s.sensor_id, s.name, wr.rain_rate, wr.wind_speed, wr.date_time
                FROM sensor s
                JOIN weather_reports wr ON s.sensor_id = wr.sensor_id
                WHERE wr.date_time = (
                    SELECT MAX(date_time) 
                    FROM weather_reports 
                    WHERE sensor_id = s.sensor_id
                )
            """)
            
            for row in cursor.fetchall():
                # FIX: Added sensor_id to the row unpack
                sensor_id, name, rain_rate, wind_speed, date_time = row
                date_time_str = date_time.strftime('%Y-%m-%d %H:%M:%S')

                # --- RAIN ALERT LOGIC (PAGASA, mm/hr Display) ---
                if rain_rate is not None and rain_rate > 0:
                    
                    # 1. Classify intensity using mm/min data
                    intensity = get_rain_intensity(rain_rate)

                    # 2. Convert to mm/hr for display (mm/min * 60)
                    rain_rate_mm_hr = rain_rate * 60 

                    # 3. Trigger alert for PAGASA's highest levels
                    if intensity in ["Heavy", "Intense", "Torrential"]:
                        
                        alert_msg = f"⚠️ {intensity} Rainfall Alert in {name} ({rain_rate_mm_hr:.1f} mm/hr)"
                        alerts.append({
                            'text': alert_msg, 
                            'timestamp': date_time_str,
                            'type': 'rain',
                            'severity': intensity.lower(), # Use the classified intensity
                            'sensor_id': sensor_id         # Add sensor ID for tracking
                        })

                # --- WIND ALERT LOGIC (PAGASA TCWS, km/h Display) ---
                if wind_speed is not None and wind_speed > 0:
                    
                    # 1. Classify wind signal using m/s data
                    wind_signal = get_wind_signal(wind_speed)
                    
                    # 2. Convert to km/h for display (m/s * 3.6)
                    wind_speed_kmh = wind_speed * 3.6

                    # 3. Trigger alert if a TCWS is issued (Signal No. 1 or higher)
                    if wind_signal != "No Signal":
                        
                        # Use official Signal name
                        alert_msg = f"🚨 {wind_signal} (PAGASA) Wind Alert in {name} ({wind_speed_kmh:.0f} km/h)"
                        alerts.append({
                            'text': alert_msg, 
                            'timestamp': date_time_str,
                            'type': 'wind',
                            'severity': wind_signal.replace(" ", "_").lower(), # Use Signal No. as severity
                            'sensor_id': sensor_id
                        })

        # 2. Get flood warnings from ML predictions (last 24 hours)
        # This section remains UNCHANGED as it was not part of the required fix.
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT area, risk_level, message, prediction_date
                FROM flood_warnings
                WHERE prediction_date >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
                ORDER BY prediction_date DESC
            """)
            flood_warnings = cursor.fetchall()
            
            for row in flood_warnings:
                area, risk_level, message, prediction_date = row
                # Add flood warning as alert
                alerts.append({
                    'text': f"🌊 {risk_level} Flood Risk: {area}",
                    'timestamp': prediction_date.strftime('%Y-%m-%d %H:%M:%S') if prediction_date else '',
                    'type': 'flood',
                    'severity': risk_level.lower(),
                    'message': message,
                    'area': area
                })

        # Check if user has marked alerts as read
        read_alerts_data = request.session.get('read_alerts', {})
        read_alerts = read_alerts_data.get('alerts', [])
        marked_at = read_alerts_data.get('marked_at', None)
        
        return JsonResponse({
            'alerts': alerts,
            'read_alerts': read_alerts,
            'marked_at': marked_at,
            'total_count': len(alerts),
            'read_count': len(read_alerts)
        })
        
    except Exception as e:
        print(f"Error in get_alerts: {str(e)}")
        return JsonResponse({
            'alerts': [],
            'error': str(e)
        }, status=500)

@csrf_exempt
def mark_alerts_read(request):
    if request.method == "POST":
        try:
            # Get current alerts using the same logic as get_alerts function
            alerts = []
            
            # 1. Get sensor-based alerts
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT s.name, wr.rain_rate, wr.wind_speed, wr.date_time
                    FROM weather_reports wr
                    JOIN sensor s ON wr.sensor_id = s.sensor_id
                    WHERE wr.date_time = (
                        SELECT MAX(date_time) 
                        FROM weather_reports 
                        WHERE sensor_id = s.sensor_id
                    )
                """)
                for row in cursor.fetchall():
                    name, rain_rate, wind_speed, date_time = row
                    # Use consistent alert thresholds
                    if rain_rate and rain_rate >= 7.6:
                        alerts.append({
                            'text': f"⚠️ Heavy Rainfall Alert in {name} ({rain_rate} mm)",
                            'timestamp': date_time.strftime('%Y-%m-%d %H:%M:%S'),
                            'type': 'rain',
                            'severity': 'heavy'
                        })
                    if wind_speed and wind_speed > 30:
                        alerts.append({
                            'text': f"⚠️ Strong Wind Alert in {name} ({wind_speed} km/h)",
                            'timestamp': date_time.strftime('%Y-%m-%d %H:%M:%S'),
                            'type': 'wind',
                            'severity': 'strong'
                        })

            # 2. Get flood warnings from ML predictions (last 24 hours)
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT area, risk_level, message, prediction_date
                    FROM flood_warnings
                    WHERE prediction_date >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
                    ORDER BY prediction_date DESC
                """)
                flood_warnings = cursor.fetchall()
                
                for row in flood_warnings:
                    area, risk_level, message, prediction_date = row
                    # Add flood warning as alert
                    alerts.append({
                        'text': f"🌊 {risk_level} Flood Risk: {area}",
                        'timestamp': prediction_date.strftime('%Y-%m-%d %H:%M:%S') if prediction_date else '',
                        'type': 'flood',
                        'severity': risk_level.lower(),
                        'message': message,
                        'area': area
                    })

            # Save read alerts in session with timestamp
            current_time = datetime.now().isoformat()
            request.session["read_alerts"] = {
                'alerts': alerts,
                'marked_at': current_time,
                'count': len(alerts)
            }
            request.session.modified = True

            return JsonResponse({
                "status": "success",
                "message": f"Marked {len(alerts)} alerts as read",
                "marked_count": len(alerts),
                "marked_at": current_time
            })
            
        except Exception as e:
            print(f"Error in mark_alerts_read: {str(e)}")
            return JsonResponse({
                "status": "error",
                "message": f"Failed to mark alerts as read: {str(e)}"
            }, status=500)
    
    return JsonResponse({
        "status": "error",
        "message": "Invalid request method. POST required."
    }, status=405)

@csrf_exempt
def clear_read_alerts(request):
    """Clear all read alerts from session"""
    if request.method == "POST":
        try:
            # Clear read alerts from session
            if 'read_alerts' in request.session:
                del request.session['read_alerts']
                request.session.modified = True
            
            return JsonResponse({
                "status": "success",
                "message": "Read alerts cleared successfully"
            })
            
        except Exception as e:
            print(f"Error in clear_read_alerts: {str(e)}")
            return JsonResponse({
                "status": "error",
                "message": f"Failed to clear read alerts: {str(e)}"
            }, status=500)
    
    return JsonResponse({
        "status": "error",
        "message": "Invalid request method. POST required."
    }, status=405)

@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def logout_view(request):
    if 'admin_id' not in request.session and 'user_id' not in request.session:
        return redirect('home')

    if request.method == "POST":
        
        request.session['form_logoutSuccess'] = "You have been logged out successfully."
        request.session.pop('admin_id', None)
        request.session.pop('user_id', None)
        return redirect('home')
    else:
        return HttpResponseNotAllowed(['POST'])
    
def user_profile(request):
    if 'user_id' not in request.session:
        return redirect('home')

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT name, email, phone_num, username 
            FROM user 
            WHERE user_id = %s
        """, [request.session['user_id']])
        row = cursor.fetchone()

    user_profile = {}
    if row:
        name, email, phone, username = row
        user_profile = {
            'name': name,
            'email': email,
            'phone_num': phone,
            'username': username,
            'email_verified': False,
            'phone_verified': False,
        }

        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT contact_type, contact_value 
                FROM verified_contacts 
                WHERE user_id = %s
            """, [request.session['user_id']])
            verified = cursor.fetchall()

        for ctype, cvalue in verified:
            if ctype == 'email' and cvalue == email:
                user_profile['email_verified'] = True
            if ctype == 'phone' and cvalue == phone:
                user_profile['phone_verified'] = True

    form_userSuccess = request.session.pop('form_userSuccess', None)
    form_userError = request.session.pop('form_userError', None)

    context = {
        'user_profile': user_profile,
        'form_userSuccess': form_userSuccess,
        'form_userError': form_userError,
    }
    
    return render(request, 'user_profile.html', context)

def send_otp(request, contact_type):
    if 'user_id' not in request.session:
        return redirect('home')

    with connection.cursor() as cursor:
        cursor.execute("SELECT email, phone_num FROM user WHERE user_id = %s", [request.session['user_id']])
        row = cursor.fetchone()
        if not row:
            messages.error(request, "User not found.")
            return redirect("user_profile")

    email, phone = row
    otp = random.randint(100000, 999999)

    # Store OTP in session
    request.session['otp'] = str(otp)
    request.session['otp_type'] = contact_type
    request.session['otp_value'] = email if contact_type == "email" else phone

    try:
        if contact_type == "email":
            # Send OTP via Email
            send_mail(
                subject="WeatherAlert Verification OTP",
                message=f"Your OTP for verifying your email in WeatherAlert is: {otp}",
                from_email=settings.EMAIL_HOST_USER,
                recipient_list=[email],
                fail_silently=False,
            )
            messages.success(request, "OTP has been sent to your email.")

        elif contact_type == "phone":
            # Send OTP via SMS API
            url = settings.SMS_API_URL
            
            # Format phone number properly
            formatted_phone = phone
            if phone.startswith("0"):
                formatted_phone = "+63" + phone[1:]
            elif not phone.startswith("+"):
                formatted_phone = "+63" + phone
            
            parameters = {
                'message': f'Your OTP for verifying your phone in WeatherAlert is: {otp}',
                'mobile_number': formatted_phone,
                'device': settings.SMS_DEVICE_ID,
                'device_sim': '1'
            }
            headers = {
                'apikey': settings.SMS_API_KEY,
                'Content-Type': 'application/x-www-form-urlencoded'
            }
            
            # Try with SSL verification first
            try:
                session = requests.Session()
                session.verify = certifi.where()
                response = session.post(url, headers=headers, data=parameters, timeout=10)
                
                if response.status_code == 200:
                    try:
                        result = response.json()
                        if result.get("success", True):
                            messages.success(request, "OTP has been sent to your phone.")
                        else:
                            messages.error(request, f"SMS API Error: {result.get('message', 'Unknown error')}")
                            return redirect("user_profile")
                    except:
                        # If response is not JSON, assume success for 200 status
                        messages.success(request, "OTP has been sent to your phone.")
                else:
                    messages.error(request, f"Failed to send SMS: HTTP {response.status_code} - {response.text}")
                    return redirect("user_profile")
                    
            except requests.exceptions.SSLError as e:
                print(f"SSL Error in send_otp: {str(e)}")
                # Fallback without SSL verification
                try:
                    response = requests.post(url, headers=headers, data=parameters, timeout=10, verify=False)
                    if response.status_code == 200:
                        messages.success(request, "OTP has been sent to your phone.")
                    else:
                        messages.error(request, f"Failed to send SMS (fallback): HTTP {response.status_code} - {response.text}")
                        return redirect("user_profile")
                except Exception as fallback_error:
                    print(f"Fallback SMS Error in send_otp: {str(fallback_error)}")
                    messages.error(request, f"Failed to send SMS: {str(fallback_error)}")
                    return redirect("user_profile")
            except Exception as e:
                print(f"SMS Error in send_otp: {str(e)}")
                messages.error(request, f"Failed to send SMS: {str(e)}")
                return redirect("user_profile")

        else:
            messages.error(request, "Invalid contact type.")
            return redirect("user_profile")

    except Exception as e:
        messages.error(request, f"Failed to send OTP: {str(e)}")
        return redirect("user_profile")

    return redirect("userverify_otp")

def userverify_otp(request):
    if request.method == "POST":
        entered_otp = request.POST.get("otp")
        if entered_otp == request.session.get("otp"):
            contact_type = request.session.get("otp_type")
            contact_value = request.session.get("otp_value")
            user_id = request.session['user_id']

            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO verified_contacts (user_id, contact_type, contact_value)
                    VALUES (%s, %s, %s)
                """, [user_id, contact_type, contact_value])

            request.session['form_userSuccess'] = f"{contact_type.capitalize()} verified successfully!"
            request.session.pop("otp", None)
            return redirect("user_profile")
        else:
            request.session['form_userError'] = "Invalid OTP"
            return redirect("userverify_otp")

    return render(request, "userverify_otp.html")

    
def admin_profile(request):
    if 'admin_id' not in request.session:
        return redirect('home')

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT name, email, phone_num, username 
            FROM admin 
            WHERE admin_id = %s
        """, [request.session['admin_id']])
        row = cursor.fetchone()

    if row:
        admin_profile = {
            'name': row[0],
            'email': row[1],
            'phone_num': row[2],
            'username': row[3]
        }
    else:
        admin_profile = {}

    form_adminSuccess = request.session.pop('form_adminSuccess', None)
    form_adminError = request.session.pop('form_adminError', None)

    context = {
        'admin_profile': admin_profile,
        'form_adminSuccess': form_adminSuccess,
        'form_adminError': form_adminError,
    }
    
    return render(request, 'admin_profile.html', context)

@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def admin_view(request):
    # Check admin authentication and status
    if 'admin_id' not in request.session:
        messages.error(request, 'Please login to access this page')
        return redirect('home')
    
    admin_id = request.session['admin_id']
    
    try:
        with connection.cursor() as cursor:
            # Get logged-in admin info with status check
            cursor.execute("""
                SELECT name, status 
                FROM admin 
                WHERE admin_id = %s AND status = 'Active'
            """, [admin_id])
            row = cursor.fetchone()
            
            if not row:
                messages.error(request, 'Your account is not active or does not exist')
                return redirect('home')
                
            admin_name = row[0]

        # Get all admins with error handling
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT admin_id, name, phone_num, email, username, status 
                FROM admin
                ORDER BY status DESC, name ASC
            """)
            rows = cursor.fetchall()

        admins = [{
            'id': row[0],
            'name': row[1],
            'phone_num': row[2],
            'email': row[3],
            'username': row[4],
            'status': row[5]
        } for row in rows]

        context = {
            'admins': admins,
            'admin': {'name': admin_name, 'id': admin_id},
            'form_adminSuccess': request.session.pop('form_adminSuccess', None),
            'form_adminError': request.session.pop('form_adminError', None),
            'show_addadmin_modal': request.session.pop('show_addadmin_modal', False),
            'form_errors': request.session.pop('form_errors', {}),
            'form_data': request.session.pop('form_data', {})
        }

        return render(request, 'admin.html', context)

    except Exception as e:
        messages.error(request, f'Database error: {str(e)}')
        return redirect('admin_dashboard')

def add_admin(request):
    if request.method == 'POST':
        errors = {}

        name = request.POST.get('name', '').strip()
        email = request.POST.get('email', '').strip()
        phone = request.POST.get('phone_num', '').strip()
        username = request.POST.get('username', '').strip()
        password = request.POST.get('password', '').strip()
        confirm_password = request.POST.get('confirm_password', '').strip()

        form_data = {
            'name': name,
            'email': email,
            'phone_num': phone,
            'username': username,
        }

        if not all([name, email, phone, username, password, confirm_password]):
            errors['required'] = "All fields are required."

        if email and not re.match(r"[^@]+@[^@]+\.[^@]+", email):
            errors['email'] = "Invalid email format."

        if phone and not re.match(r"^\d{11}$", phone):
            errors['phone_num'] = "Phone number must be exactly 11 digits."

        if password != confirm_password:
            errors['confirm_password'] = "Passwords do not match."
        else:
            if len(password) < 8:
                errors['password'] = "Password must be at least 8 characters long."
            elif not re.search(r'[A-Z]', password):
                errors['password'] = "Password must contain at least one uppercase letter."
            elif not re.search(r'[a-z]', password):
                errors['password'] = "Password must contain at least one lowercase letter."
            elif not re.search(r'\d', password):
                errors['password'] = "Password must contain at least one number."
            elif not re.search(r'[!@#$%^&*(),.?\":{}|<>]', password):
                errors['password'] = "Password must contain at least one special character."

        with connection.cursor() as cursor:
            cursor.execute("SELECT admin_id FROM admin WHERE username = %s", [username])
            if cursor.fetchone():
                errors['username'] = "Username already exists."

            cursor.execute("SELECT admin_id FROM admin WHERE email = %s", [email])
            if cursor.fetchone():
                errors['email'] = "Email already exists."

        if errors:
            request.session['show_addadmin_modal'] = True
            request.session['form_errors'] = errors
            request.session['form_data'] = form_data
            return redirect('manage_admins')

        hashed_password = make_password(password)
        try:
            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO admin (name, email, phone_num, username, password, status)
                    VALUES (%s, %s, %s, %s, %s, 'Active')
                """, [name, email, phone, username, hashed_password])

            request.session['form_adminSuccess'] = "Admin added successfully."
        except Exception as e:
            request.session['form_adminError'] = f"Error adding admin: {str(e)}"
            request.session['show_addadmin_modal'] = True
            request.session['form_data'] = form_data

        return redirect('manage_admins')

    return redirect('manage_admins')

    
def update_admin(request):
    if request.method == 'POST':
        errors = {}
        
        admin_id = request.POST.get('id', '').strip()
        name = request.POST.get('name', '').strip()
        email = request.POST.get('email', '').strip()
        phone = request.POST.get('phone_num', '').strip()
        username = request.POST.get('username', '').strip()
        password = request.POST.get('password', '').strip()
        confirm_password = request.POST.get('confirm_password', '').strip()

        form_data = {
            'name': name,
            'email': email,
            'phone_num': phone,
            'username': username,
        }
        
        if password != confirm_password:
            errors['confirm_password'] = "Passwords do not match."
        else:
            if len(password) < 8:
                errors['password'] = "Password must be at least 8 characters long."
            elif not re.search(r'[A-Z]', password):
                errors['password'] = "Password must contain at least one uppercase letter."
            elif not re.search(r'[a-z]', password):
                errors['password'] = "Password must contain at least one lowercase letter."
            elif not re.search(r'\d', password):
                errors['password'] = "Password must contain at least one number."
            elif not re.search(r'[!@#$%^&*(),.?\":{}|<>]', password):
                errors['password'] = "Password must contain at least one special character."

        if not all([name, email, phone, username]):
            errors['required'] = "All fields are required."

        if email and not re.match(r"[^@]+@[^@]+\.[^@]+", email):
            errors['email'] = "Invalid email format."

        if phone and not re.match(r"^\d{11}$", phone):
            errors['phone_num'] = "Phone number must be exactly 11 digits."
            
        with connection.cursor() as cursor:
            cursor.execute("SELECT admin_id FROM admin WHERE username = %s AND admin_id != %s", [username, admin_id])
            if cursor.fetchone():
                errors['username'] = "Username already exists."

            cursor.execute("SELECT admin_id FROM admin WHERE email = %s AND admin_id != %s", [email, admin_id])
            if cursor.fetchone():
                errors['email'] = "Email already exists."

        if errors:
            request.session['show_addadmin_modal'] = True
            request.session['form_errors'] = errors
            request.session['form_data'] = form_data
            return redirect('manage_admins')

        try:
            with connection.cursor() as cursor:
                if password:
                    cursor.execute('''
                        UPDATE admin
                        SET name = %s, email = %s, phone_num = %s, 
                            username = %s, password = %s
                        WHERE admin_id = %s
                    ''', [name, email, phone, username, make_password(password), admin_id])
                else:
                    cursor.execute('''
                        UPDATE admin
                        SET name = %s, email = %s, phone_num = %s, username = %s
                        WHERE admin_id = %s
                    ''', [name, email, phone, username, admin_id])

            request.session['form_adminSuccess'] = "Admin updated successfully."
        except Exception as e:
            messages.error(request, f'An error occurred: {str(e)}')

        return redirect('manage_admins')
    
@csrf_exempt
def deactivate_admin(request, admin_id):
    if request.method == "POST":
        try:
            with connection.cursor() as cursor:
                cursor.execute("UPDATE admin SET status = 'Deactivated' WHERE admin_id = %s", [admin_id])
            request.session['form_adminSuccess'] = "✅ Admin has been successfully deactivated."
        except Exception as e:
            request.session['form_adminError'] = f"❌ Deactivation failed: {str(e)}"
    return redirect('manage_admins')

@csrf_exempt
def activate_admin(request, admin_id):
    if request.method == "POST":
        try:
            with connection.cursor() as cursor:
                cursor.execute("UPDATE admin SET status = 'Active' WHERE admin_id = %s", [admin_id])
            request.session['form_adminSuccess'] = "✅ Admin activated successfully."
        except Exception as e:
            request.session['form_adminError'] = f"❌ Deactivation failed: {str(e)}"
    return redirect('manage_admins')

def change_password(request):
    if 'admin_id' not in request.session:
        return redirect('home')

    if request.method == 'POST':
        admin_id = request.session['admin_id']
        old_password = request.POST.get('old_password')
        new_password = request.POST.get('new_password')
        confirm_password = request.POST.get('confirm_password')

        errors = {}
        
        if len(new_password) < 8:
            errors['password'] = "Password must be at least 8 characters long."
        elif not re.search(r'[A-Z]', new_password):
            errors['password'] = "Password must contain at least one uppercase letter."
        elif not re.search(r'[a-z]', new_password):
            errors['password'] = "Password must contain at least one lowercase letter."
        elif not re.search(r'\d', new_password):
            errors['password'] = "Password must contain at least one number."
        elif not re.search(r'[!@#$%^&*(),.?\":{}|<>]', new_password):
            errors['password'] = "Password must contain at least one special character."
        if not old_password or not new_password or not confirm_password:
            request.session['form_adminError'] = "❌ All password fields are required."
            return redirect('admin_profile')

        if new_password != confirm_password:
            request.session['form_adminError'] = "❌ New password and confirmation do not match."
            return redirect('admin_profile')

        with connection.cursor() as cursor:
            cursor.execute("SELECT password FROM admin WHERE admin_id = %s", [admin_id])
            result = cursor.fetchone()

        if result:
            stored_password = result[0]
            if check_password(old_password, stored_password):
                hashed_password = make_password(new_password)
                with connection.cursor() as cursor:
                    cursor.execute("UPDATE admin SET password = %s WHERE admin_id = %s", [hashed_password, admin_id])
                request.session['form_adminSuccess'] = "✅ Password changed successfully."
            else:
                request.session['form_adminError'] = "❌ Old password is incorrect."
        else:
            request.session['form_adminError'] = "❌ Admin account not found."

    return redirect('admin_profile')

@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def active_user(request):
    if 'admin_id' not in request.session:
        messages.error(request, 'Please login to access this page')
        return redirect('home')
    
    try:
        with connection.cursor() as cursor:
            # Get admin info
            cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [request.session['admin_id']])
            row = cursor.fetchone()
            admin_name = row[0] if row else 'Admin'

            cursor.execute("""
                SELECT user_id, name, address, email, phone_num, username 
                FROM user 
                ORDER BY name
            """)
            users = [{
                'id': row[0],
                'name': row[1],
                'address': row[2],
                'email': row[3],
                'phone_num': row[4],
                'username': row[5],
            } for row in cursor.fetchall()]

        return render(request, 'manageActive_user.html', {
            'users': users,
            'admin': {'name': admin_name},
            'current_url': 'active_user'
        })

    except Exception as e:
        messages.error(request, f'Database error: {str(e)}')
        return redirect('admin_dashboard')

def delete_user(request, user_id):
    if 'admin_id' not in request.session:
        return HttpResponseForbidden("Not authorized")
    
    if request.method != 'POST':
        return HttpResponseForbidden("Invalid request method")

    try:
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM user WHERE user_id = %s", [user_id])
        
        messages.success(request, 'User deleted successfully')
        return redirect('active_user')
        
    except Exception as e:
        messages.error(request, f'Failed to delete user: {str(e)}')
        return redirect('active_user')


@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def sensors(request):
    if 'admin_id' not in request.session:
        messages.error(request, 'Please login to access this page')
        return redirect('home')
    
    try:
        with connection.cursor() as cursor:
            # Get admin info
            cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [request.session['admin_id']])
            row = cursor.fetchone()
            admin_name = row[0] if row else 'Admin'

            # Get all sensors
            cursor.execute("SELECT sensor_id, name, latitude, longitude, radius FROM sensor ORDER BY name")
            sensors = [{
                'id': row[0],
                'name': row[1],
                'latitude': row[2],
                'longitude': row[3],
                'radius': row[4]
            } for row in cursor.fetchall()]

        # Check for form errors from previous submission
        form_errors = request.session.pop('form_errors', {})
        form_data = request.session.pop('form_data', {})

        return render(request, 'sensors.html', {
            'sensors': sensors,
            'sensors_json': json.dumps(sensors),
            'admin': {'name': admin_name},
            'form_errors': form_errors,
            'form_data': form_data,
            'show_add_modal': request.session.pop('show_add_modal', False)
        })

    except Exception as e:
        messages.error(request, f'Database error: {str(e)}')
        return redirect('admin_dashboard')

def add_sensor(request):
    if 'admin_id' not in request.session:
        return HttpResponseForbidden("Not authorized")
    
    if request.method != 'POST':
        return HttpResponseForbidden("Invalid request method")

    name = request.POST.get('name', '').strip()
    latitude = request.POST.get('latitude', '').strip()
    longitude = request.POST.get('longitude', '').strip()
    radius = request.POST.get('radius', '').strip()

    # Validation
    errors = {}
    if not name:
        errors['name'] = 'Name is required'
    if not is_valid_coordinate(latitude, 'latitude'):
        errors['latitude'] = 'Valid latitude is required (-90 to 90)'
    if not is_valid_coordinate(longitude, 'longitude'):
        errors['longitude'] = 'Valid longitude is required (-180 to 180)'
    # radius is required and must be a positive number
    try:
        if radius == '':
            errors['radius'] = 'Radius is required'
        else:
            r = float(radius)
            if r < 0:
                errors['radius'] = 'Radius must be non-negative'
    except ValueError:
        errors['radius'] = 'Radius must be a number'

    if errors:
        request.session['form_errors'] = errors
        request.session['form_data'] = {
            'name': name,
            'latitude': latitude,
            'longitude': longitude,
            'radius': radius
        }
        request.session['show_add_modal'] = True
        return redirect('sensors')

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO sensor (name, latitude, longitude, radius)
                VALUES (%s, %s, %s, %s)
                """,
                [name, latitude, longitude, radius]
            )
        
        messages.success(request, 'Sensor added successfully')
        return redirect('sensors')
        
    except Exception as e:
        messages.error(request, f'Failed to add sensor: {str(e)}')
        return redirect('sensors')

def update_sensor(request):
    if 'admin_id' not in request.session:
        return HttpResponseForbidden("Not authorized")

    if request.method != 'POST':
        return HttpResponseForbidden("Invalid request method")

    sensor_id = request.POST.get('id')
    name = request.POST.get('name', '').strip()
    latitude = request.POST.get('latitude', '').strip()
    longitude = request.POST.get('longitude', '').strip()
    radius = request.POST.get('radius', '').strip()

    form_data = {
        'id': sensor_id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius
    }

    # Validation
    errors = {}
    if not sensor_id:
        errors['id'] = 'Sensor ID is required'
    if not name:
        errors['name'] = 'Name is required'
    if not is_valid_coordinate(latitude, 'latitude'):
        errors['latitude'] = 'Valid latitude is required (-90 to 90)'
    if not is_valid_coordinate(longitude, 'longitude'):
        errors['longitude'] = 'Valid longitude is required (-180 to 180)'
    if not radius:
        errors['radius'] = 'Radius is required'

    if errors:
        request.session['form_errors'] = errors
        request.session['form_data'] = form_data
        return redirect('sensors')

    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                UPDATE sensor
                SET name = %s, latitude = %s, longitude = %s, radius = %s
                WHERE sensor_id = %s
            """, [name, latitude, longitude, radius, sensor_id])

        messages.success(request, 'Sensor updated successfully')
        return redirect('sensors')

    except Exception as e:
        messages.error(request, f'Failed to update sensor: {str(e)}')
        return redirect('sensors')

def delete_sensor(request, sensor_id):
    if 'admin_id' not in request.session:
        return HttpResponseForbidden("Not authorized")
    
    if request.method != 'POST':
        return HttpResponseForbidden("Invalid request method")

    try:
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM sensor WHERE sensor_id = %s", [sensor_id])
        
        messages.success(request, 'Sensor deleted successfully')
        return redirect('sensors')
        
    except Exception as e:
        messages.error(request, f'Failed to delete sensor: {str(e)}')
        return redirect('sensors')

def is_valid_coordinate(value, coord_type):
    try:
        num = float(value)
        if coord_type == 'latitude':
            return -90 <= num <= 90
        return -180 <= num <= 180
    except ValueError:
        return False


@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def weather_reports(request):
    # Authentication check
    if 'admin_id' not in request.session:
        return redirect('home')
    
    admin_id = request.session['admin_id']
    
    # Get admin name
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [admin_id])
        row = cursor.fetchone()
        admin_name = row[0] if row else 'Admin'

    # Get filter parameters
    start_date = request.GET.get('start_date')
    end_date = request.GET.get('end_date')
    sensor_id = request.GET.get('sensor_id')
    intensity_id = request.GET.get('intensity_id')

    # Base query
    query = """
        SELECT  
            s.name AS name, 
            wr.temperature, 
            wr.humidity,
            wr.wind_speed,
            wr.barometric_pressure,
            wr.altitude,
            wr.dew_point, 
            wr.date_time, 
            wr.rain_rate, 
            i.intensity AS intensity, 
            wr.rain_accumulated 
        FROM weather_reports wr
        JOIN sensor s ON wr.sensor_id = s.sensor_id 
        JOIN intensity i ON wr.intensity_id = i.intensity_id
    """
    
    conditions = []
    params = []
    
    if start_date:
        conditions.append("wr.date_time >= %s")
        params.append(start_date)
    if end_date:
        conditions.append("wr.date_time <= %s")
        params.append(end_date)
    if sensor_id:
        conditions.append("wr.sensor_id = %s")
        params.append(sensor_id)
    if intensity_id:
        conditions.append("wr.intensity_id = %s")
        params.append(intensity_id)
    
    if conditions:
        query += " WHERE " + " AND ".join(conditions)
    
    query += " ORDER BY wr.date_time DESC"
    
    # Execute report query
    with connection.cursor() as cursor:
        cursor.execute(query, params)
        columns = [col[0] for col in cursor.description]
        reports = []
        for row in cursor.fetchall():
            report = dict(zip(columns, row))
            # Convert datetime to ISO format
            if 'date_time' in report and report['date_time']:
                if isinstance(report['date_time'], str):
                    try:
                        report['date_time'] = datetime.fromisoformat(report['date_time']).isoformat()
                    except ValueError:
                        report['date_time'] = None
                elif isinstance(report['date_time'], datetime):
                    report['date_time'] = report['date_time'].isoformat()
            reports.append(report)
    
    # Get summary statistics
    summary_query = """
        SELECT
            MIN(wr.temperature) AS min_temp,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.temperature = MIN(wr.temperature)
            ORDER BY wr2.date_time ASC LIMIT 1) AS min_temp_date,
            MAX(wr.temperature) AS max_temp,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.temperature = MAX(wr.temperature)
            ORDER BY wr2.date_time ASC LIMIT 1) AS max_temp_date,

            MIN(wr.wind_speed) AS min_wind,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.wind_speed = MIN(wr.wind_speed)
            ORDER BY wr2.date_time ASC LIMIT 1) AS min_wind_date,
            MAX(wr.wind_speed) AS max_wind,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.wind_speed = MAX(wr.wind_speed)
            ORDER BY wr2.date_time ASC LIMIT 1) AS max_wind_date,

            MIN(wr.humidity) AS min_humidity,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.humidity = MIN(wr.humidity)
            ORDER BY wr2.date_time ASC LIMIT 1) AS min_humidity_date,
            MAX(wr.humidity) AS max_humidity,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.humidity = MAX(wr.humidity)
            ORDER BY wr2.date_time ASC LIMIT 1) AS max_humidity_date,

            MIN(wr.rain_accumulated) AS min_rain,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.rain_accumulated = MIN(wr.rain_accumulated)
            ORDER BY wr2.date_time ASC LIMIT 1) AS min_rain_date,
            MAX(wr.rain_accumulated) AS max_rain,
            (SELECT wr2.date_time 
            FROM weather_reports wr2 
            WHERE wr2.rain_accumulated = MAX(wr.rain_accumulated)
            ORDER BY wr2.date_time ASC LIMIT 1) AS max_rain_date
        FROM weather_reports wr
    """

    summary_conditions = []
    summary_params = []
    
    if start_date:
        summary_conditions.append("wr.date_time >= %s")
        summary_params.append(start_date)
    if end_date:
        summary_conditions.append("wr.date_time <= %s")
        summary_params.append(end_date)
    if sensor_id:
        summary_conditions.append("wr.sensor_id = %s")
        summary_params.append(sensor_id)
    if intensity_id:
        summary_conditions.append("wr.intensity_id = %s")
        summary_params.append(intensity_id)
    
    if summary_conditions:
        summary_query += " WHERE " + " AND ".join(summary_conditions)
    
    with connection.cursor() as cursor:
        cursor.execute(summary_query, summary_params)
        summary_row = cursor.fetchone()
        summary_stats = {
            'min_temp': summary_row[0],
            'min_temp_date': summary_row[1],
            'max_temp': summary_row[2],
            'max_temp_date': summary_row[3],
            
            'min_wind': summary_row[4],
            'min_wind_date': summary_row[5],
            'max_wind': summary_row[6],
            'max_wind_date': summary_row[7],

            'min_humidity': summary_row[8],
            'min_humidity_date': summary_row[9],
            'max_humidity': summary_row[10],
            'max_humidity_date': summary_row[11],

            'min_rain': summary_row[12],
            'min_rain_date': summary_row[13],
            'max_rain': summary_row[14],
            'max_rain_date': summary_row[15],
        }

    # Get all sensors and intensities for filters
    with connection.cursor() as cursor:
        cursor.execute("SELECT sensor_id, name FROM sensor ORDER BY name")
        sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]
        
        cursor.execute("SELECT intensity_id, intensity FROM intensity ORDER BY intensity")
        intensities = [{'intensity_id': row[0], 'intensity': row[1]} for row in cursor.fetchall()]

    context = {
        'reports': reports,
        'summary_stats': summary_stats,
        'sensors': sensors,
        'intensities': intensities,
        'admin': {'name': admin_name},
        'default_start_date': (datetime.now() - timedelta(days=7)).strftime('%Y-%m-%d'),
        'default_end_date': datetime.now().strftime('%Y-%m-%d')
    }

    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({
            'reports': reports,
            'summary_stats': summary_stats
        }, json_dumps_params={'default': str})

    return render(request, 'weather_reports.html', context)

@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def daily_reports(request):
    if 'admin_id' not in request.session:
        return redirect('home')
    
    admin_id = request.session['admin_id']
    
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [admin_id])
        row = cursor.fetchone()
        admin_name = row[0] if row else 'Admin'

    start_date = request.GET.get('start_date')
    end_date = request.GET.get('end_date')
    sensor_id = request.GET.get('sensor_id')

    report_query = """
        SELECT 
            s.name AS name,
            DATE(wr.date_time) AS date,
            AVG(wr.temperature) AS avg_temperature,
            AVG(wr.humidity) AS avg_humidity,
            AVG(wr.wind_speed) AS avg_wind_speed,
            AVG(wr.barometric_pressure) AS avg_barometric_pressure,
            AVG(wr.altitude) AS avg_altitude,
            AVG(wr.dew_point) AS avg_dew_point,
            AVG(wr.rain_rate) AS avg_rain_rate,
            SUM(wr.rain_accumulated) AS total_rain_accumulated
        FROM weather_reports wr
        JOIN sensor s ON wr.sensor_id = s.sensor_id
    """
    
    summary_query = """
    WITH daily AS (
        SELECT 
            DATE(wr.date_time) AS date,
            AVG(wr.temperature) AS avg_temperature,
            AVG(wr.wind_speed) AS avg_wind_speed,
            AVG(wr.humidity) AS avg_humidity,
            SUM(wr.rain_accumulated) AS total_rain
        FROM weather_reports wr
        {where_clause}
        GROUP BY DATE(wr.date_time)
    ),
    minmax AS (
        SELECT
            MIN(avg_temperature) AS min_temp,
            MAX(avg_temperature) AS max_temp,
            MIN(avg_wind_speed) AS min_wind,
            MAX(avg_wind_speed) AS max_wind,
            MIN(avg_humidity) AS min_humidity,
            MAX(avg_humidity) AS max_humidity,
            MIN(total_rain) AS min_rain,
            MAX(total_rain) AS max_rain
        FROM daily
    )
    SELECT
        min_temp,
        (SELECT date FROM daily WHERE avg_temperature = min_temp LIMIT 1) AS min_temp_date,
        max_temp,
        (SELECT date FROM daily WHERE avg_temperature = max_temp LIMIT 1) AS max_temp_date,
        
        min_wind,
        (SELECT date FROM daily WHERE avg_wind_speed = min_wind LIMIT 1) AS min_wind_date,
        max_wind,
        (SELECT date FROM daily WHERE avg_wind_speed = max_wind LIMIT 1) AS max_wind_date,
        
        min_humidity,
        (SELECT date FROM daily WHERE avg_humidity = min_humidity LIMIT 1) AS min_humidity_date,
        max_humidity,
        (SELECT date FROM daily WHERE avg_humidity = max_humidity LIMIT 1) AS max_humidity_date,
        
        min_rain,
        (SELECT date FROM daily WHERE total_rain = min_rain LIMIT 1) AS min_rain_date,
        max_rain,
        (SELECT date FROM daily WHERE total_rain = max_rain LIMIT 1) AS max_rain_date
    FROM minmax;
    """

    conditions = []
    params = []
    
    if start_date:
        conditions.append("DATE(wr.date_time) >= %s")
        params.append(start_date)
    if end_date:
        conditions.append("DATE(wr.date_time) <= %s")
        params.append(end_date)
    if sensor_id:
        conditions.append("wr.sensor_id = %s")
        params.append(sensor_id)
    
    if conditions:
        where_clause = " WHERE " + " AND ".join(conditions)
    else:
        where_clause = ""

    # Reports query
    report_query += where_clause
    report_query += " GROUP BY s.name, DATE(wr.date_time) ORDER BY date DESC"

    with connection.cursor() as cursor:
        cursor.execute(report_query, params)
        columns = [col[0] for col in cursor.description]
        reports = [dict(zip(columns, row)) for row in cursor.fetchall()]

        # New min/max + date summary query
        cursor.execute(summary_query.format(where_clause=where_clause), params)
        row = cursor.fetchone()
        summary_stats = {
            'min_temp': round(row[0], 1) if row[0] is not None else "N/A",
            'min_temp_date': row[1],
            'max_temp': round(row[2], 1) if row[2] is not None else "N/A",
            'max_temp_date': row[3],

            'min_wind': round(row[4], 1) if row[4] is not None else "N/A",
            'min_wind_date': row[5],
            'max_wind': round(row[6], 1) if row[6] is not None else "N/A",
            'max_wind_date': row[7],

            'min_humidity': round(row[8], 1) if row[8] is not None else "N/A",
            'min_humidity_date': row[9],
            'max_humidity': round(row[10], 1) if row[10] is not None else "N/A",
            'max_humidity_date': row[11],

            'min_rain': round(row[12], 2) if row[12] is not None else "N/A",
            'min_rain_date': row[13],
            'max_rain': round(row[14], 2) if row[14] is not None else "N/A",
            'max_rain_date': row[15],
        }

        cursor.execute("SELECT sensor_id, name FROM sensor")
        sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]


    context = {
        'reports': reports,
        'summary_stats': summary_stats,
        'sensors': sensors,
        'admin': {'name': admin_name}
    }

    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({
            'reports': reports,
            'summary_stats': summary_stats
        })
    
    return render(request, 'daily_reports.html', context)

@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def monthly_reports(request):
    if 'admin_id' not in request.session:
        return redirect('home')
    
    admin_id = request.session['admin_id']
    
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [admin_id])
        row = cursor.fetchone()
        admin_name = row[0] if row else 'Admin'

    year = request.GET.get('year')
    month = request.GET.get('month')
    sensor_id = request.GET.get('sensor_id')

    # Main report query for monthly averages
    report_query = """
        SELECT 
            s.name AS name,
            DATE_FORMAT(wr.date_time, '%%Y-%%m') AS month,
            AVG(wr.temperature) AS avg_temperature,
            AVG(wr.humidity) AS avg_humidity,
            AVG(wr.wind_speed) AS avg_wind_speed,
            AVG(wr.barometric_pressure) AS avg_barometric_pressure,
            AVG(wr.altitude) AS avg_altitude,
            AVG(wr.dew_point) AS avg_dew_point,
            AVG(wr.rain_rate) AS avg_rain_rate,
            SUM(wr.rain_accumulated) AS total_rain_accumulated
        FROM weather_reports wr
        JOIN sensor s ON wr.sensor_id = s.sensor_id
    """
    
    # Monthly summary query (similar to daily but grouped by month)
    summary_query = """
    WITH monthly AS (
        SELECT 
            DATE_FORMAT(wr.date_time, '%%Y-%%m') AS month,
            AVG(wr.temperature) AS avg_temperature,
            AVG(wr.wind_speed) AS avg_wind_speed,
            AVG(wr.humidity) AS avg_humidity,
            SUM(wr.rain_accumulated) AS total_rain
        FROM weather_reports wr
        {where_clause}
        GROUP BY DATE_FORMAT(wr.date_time, '%%Y-%%m')
    ),
    minmax AS (
        SELECT
            MIN(avg_temperature) AS min_temp,
            MAX(avg_temperature) AS max_temp,
            MIN(avg_wind_speed) AS min_wind,
            MAX(avg_wind_speed) AS max_wind,
            MIN(avg_humidity) AS min_humidity,
            MAX(avg_humidity) AS max_humidity,
            MIN(total_rain) AS min_rain,
            MAX(total_rain) AS max_rain
        FROM monthly
    )
    SELECT
        min_temp,
        (SELECT month FROM monthly WHERE avg_temperature = min_temp LIMIT 1) AS min_temp_date,
        max_temp,
        (SELECT month FROM monthly WHERE avg_temperature = max_temp LIMIT 1) AS max_temp_date,
        
        min_wind,
        (SELECT month FROM monthly WHERE avg_wind_speed = min_wind LIMIT 1) AS min_wind_date,
        max_wind,
        (SELECT month FROM monthly WHERE avg_wind_speed = max_wind LIMIT 1) AS max_wind_date,
        
        min_humidity,
        (SELECT month FROM monthly WHERE avg_humidity = min_humidity LIMIT 1) AS min_humidity_date,
        max_humidity,
        (SELECT month FROM monthly WHERE avg_humidity = max_humidity LIMIT 1) AS max_humidity_date,
        
        min_rain,
        (SELECT month FROM monthly WHERE total_rain = min_rain LIMIT 1) AS min_rain_date,
        max_rain,
        (SELECT month FROM monthly WHERE total_rain = max_rain LIMIT 1) AS max_rain_date
    FROM minmax;
    """

    conditions = []
    params = []
    
    if year:
        conditions.append("YEAR(wr.date_time) = %s")
        params.append(year)
    if month:
        conditions.append("MONTH(wr.date_time) = %s")
        params.append(month)
    if sensor_id:
        conditions.append("wr.sensor_id = %s")
        params.append(sensor_id)
    
    if conditions:
        where_clause = " WHERE " + " AND ".join(conditions)
    else:
        where_clause = ""

    # Reports query
    report_query += where_clause
    report_query += " GROUP BY s.name, YEAR(wr.date_time), MONTH(wr.date_time) ORDER BY YEAR(wr.date_time) DESC, MONTH(wr.date_time) DESC"

    with connection.cursor() as cursor:
        # Get monthly reports
        cursor.execute(report_query, params)
        columns = [col[0] for col in cursor.description]
        reports = []
        for row in cursor.fetchall():
            report = dict(zip(columns, row))
            report['month'] = datetime.strptime(report['month'], '%Y-%m').date()
            reports.append(report)

        # Get monthly summary stats
        cursor.execute(summary_query.format(where_clause=where_clause), params)
        row = cursor.fetchone()
        summary_stats = {
            'min_temp': round(row[0], 1) if row[0] is not None else "N/A",
            'min_temp_date': datetime.strptime(row[1], '%Y-%m').date() if row[1] else None,
            'max_temp': round(row[2], 1) if row[2] is not None else "N/A",
            'max_temp_date': datetime.strptime(row[3], '%Y-%m').date() if row[3] else None,

            'min_wind': round(row[4], 1) if row[4] is not None else "N/A",
            'min_wind_date': datetime.strptime(row[5], '%Y-%m').date() if row[5] else None,
            'max_wind': round(row[6], 1) if row[6] is not None else "N/A",
            'max_wind_date': datetime.strptime(row[7], '%Y-%m').date() if row[7] else None,

            'min_humidity': round(row[8], 1) if row[8] is not None else "N/A",
            'min_humidity_date': datetime.strptime(row[9], '%Y-%m').date() if row[9] else None,
            'max_humidity': round(row[10], 1) if row[10] is not None else "N/A",
            'max_humidity_date': datetime.strptime(row[11], '%Y-%m').date() if row[11] else None,

            'min_rain': round(row[12], 2) if row[12] is not None else "N/A",
            'min_rain_date': datetime.strptime(row[13], '%Y-%m').date() if row[13] else None,
            'max_rain': round(row[14], 2) if row[14] is not None else "N/A",
            'max_rain_date': datetime.strptime(row[15], '%Y-%m').date() if row[15] else None,
        }

        # Get available years for filter dropdown
        cursor.execute("SELECT DISTINCT YEAR(date_time) FROM weather_reports ORDER BY YEAR(date_time) DESC")
        available_years = [row[0] for row in cursor.fetchall()]

        cursor.execute("SELECT sensor_id, name FROM sensor")
        sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]

    context = {
        'reports': reports,
        'summary_stats': summary_stats,
        'sensors': sensors,
        'available_years': available_years,
        'current_year': datetime.now().year,
        'current_month': datetime.now().month,
        'month_names': ['January', 'February', 'March', 'April', 'May', 'June', 
                       'July', 'August', 'September', 'October', 'November', 'December'],
        'admin': {'name': admin_name}
    }

    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        json_reports = []
        for report in reports:
            json_report = report.copy()
            json_report['month'] = report['month'].strftime('%Y-%m')
            json_reports.append(json_report)
        
        return JsonResponse({
            'reports': json_reports,
            'summary_stats': summary_stats
        }, safe=False)
    
    return render(request, 'monthly_reports.html', context)

def get_rain_intensity(amount):
    if amount == 0:
        return "No Rain"
    elif 0 < amount < 2.5:
        return "Light"
    elif 2.5 <= amount < 7.6:
        return "Moderate"
    elif 7.6 <= amount < 15:
        return "Heavy"
    elif 15 <= amount < 30:
        return "Intense"
    else:
        return "Torrential"

@csrf_exempt
def receive_sensor_data(request):
    print("==== Incoming Request ====")
    print("Method:", request.method)
    print("Headers:", dict(request.headers))
    print("Raw body:", request.body)
    print("==========================")

    if request.method != "POST":
        return JsonResponse({"error": "Invalid request method, must be POST"}, status=405)

    try:
        data = json.loads(request.body)
        try:
            temperature = float(data.get('temperature', 0))
        except (ValueError, TypeError):
            temperature = 0

        try:
            humidity = float(data.get('humidity', 0))
        except (ValueError, TypeError):
            humidity = 0

        try:
            sensor_id = int(data.get('sensor_id', 0))
        except (ValueError, TypeError):
            sensor_id = 0

        try:
            rainfall_mm = float(data.get('rainfall_mm', 0))
        except (ValueError, TypeError):
            rainfall_mm = 0

        try:
            rain_tip_count = int(data.get('rain_tip_count', 0))
        except (ValueError, TypeError):
            rain_tip_count = 0

        try:
            wind_speed = float(data.get('wind_speed', 0))
        except (ValueError, TypeError):
            wind_speed = 0

        try:    
            pressure = float(data.get('barometric_pressure', 0))
        except (ValueError, TypeError):
            pressure = 0

        try:
            altitude = float(data.get('altitude_m', 0))
        except (ValueError, TypeError):
            altitude = 0

        dew_point = temperature - ((100 - humidity) / 5)

        # Since the interval is fixed at 1 minutes:
        rain_rate = rainfall_mm * 60
        rain_accumulated = rainfall_mm

        intensity_label = get_rain_intensity(rain_rate)

        with connection.cursor() as cursor:
            cursor.execute("SELECT intensity_id FROM intensity WHERE intensity = %s", [intensity_label])
            row = cursor.fetchone()
            if not row:
                return JsonResponse({"error": f"Invalid intensity label: {intensity_label}"}, status=400)
            intensity_id = row[0]

        ph_time = now().astimezone(pytz.timezone('Asia/Manila'))

        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO weather_reports (
                    sensor_id, intensity_id, temperature, humidity,
                    wind_speed, barometric_pressure, altitude,
                    dew_point, date_time, rain_rate, rain_accumulated
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, [
                sensor_id, intensity_id, temperature, humidity,
                wind_speed, pressure, altitude,
                dew_point, ph_time, rain_rate, rain_accumulated
            ])

        return JsonResponse({"status": "success"}, status=201)

    except Exception as e:
        return JsonResponse({"error": str(e)}, status=400)

LAND_TYPE_FLOOD_RISK = {
    "low_lying": {"risk_multiplier": 1.5, "description": "High flood risk - prone to water accumulation"},
    "rural_agricultural": {"risk_multiplier": 1.2, "description": "Moderate flood risk - agricultural drainage"},
    "mixed_lowland_elevated": {"risk_multiplier": 1.1, "description": "Moderate flood risk - mixed terrain"},
    "mixed_lowland_upland": {"risk_multiplier": 0.9, "description": "Lower flood risk - elevated areas"},
    "mixed_lowland_hilly": {"risk_multiplier": 0.8, "description": "Lower flood risk - hilly terrain"},
    "mixed_flat_elevated": {"risk_multiplier": 1.0, "description": "Standard flood risk - balanced terrain"},
    "mixed_flat_hilly": {"risk_multiplier": 0.7, "description": "Lower flood risk - hilly drainage"},
    "moderately_sloping": {"risk_multiplier": 0.6, "description": "Lower flood risk - good drainage"},
    "highland": {"risk_multiplier": 0.3, "description": "Minimal flood risk - elevated terrain"}
}


@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def barangays(request):
    if 'admin_id' not in request.session:
        messages.error(request, 'Please login to access this page')
        return redirect('home')
    
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [request.session['admin_id']])
            row = cursor.fetchone()
            admin_name = row[0] if row else 'Admin'

            cursor.execute("SELECT id, barangay_name, land_description, flood_risk_multiplier, flood_risk_summary FROM bago_city_barangay_risk ORDER BY barangay_name")
            
            barangays = [{
                'id': row[0],
                'barangay_name': row[1],
                'land_description': row[2],
                'flood_risk_multiplier': row[3],
                'flood_risk_summary': row[4]
            } for row in cursor.fetchall()]

        form_errors = request.session.pop('form_errors', {})
        form_data = request.session.pop('form_data', {})

        return render(request, 'barangays.html', {
            'barangays': barangays,
            'admin': {'name': admin_name},
            'form_errors': form_errors,
            'form_data': form_data,
            'LAND_RISK_OPTIONS': LAND_TYPE_FLOOD_RISK 
        })

    except Exception as e:
        messages.error(request, f'Database error loading barangays: {str(e)}')
        return redirect('admin_dashboard')
    
def update_barangay(request):
    if 'admin_id' not in request.session:
        return HttpResponseForbidden("Not authorized")
    
    if request.method != 'POST':
        return HttpResponseForbidden("Invalid request method")

    id = request.POST.get('id')
    barangay_name = request.POST.get('barangay_name', '').strip()
    land_description = request.POST.get('land_description', '').strip()
    flood_risk_multiplier = request.POST.get('flood_risk_multiplier', '').strip()
    flood_risk_summary = request.POST.get('flood_risk_summary', '').strip()

    errors = {}
    if not barangay_name:
        errors['barangay_name'] = 'Barangay name is required'
    if not land_description:
        errors['land_description'] = 'Land description is required'
    if not flood_risk_multiplier:
        errors['flood_risk_multiplier'] = 'Flood risk multiplier is required'
    if not flood_risk_summary:
        errors['flood_risk_summary'] = 'Flood risk summary is required'

    if errors:
        messages.error(request, 'Invalid barangay data')
        return redirect('barangays')

    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                UPDATE bago_city_barangay_risk 
                SET barangay_name = %s, land_description = %s, flood_risk_multiplier = %s, flood_risk_summary = %s
                WHERE id = %s
            """, [barangay_name, land_description, flood_risk_multiplier, flood_risk_summary, id])
        
        messages.success(request, 'Barangay updated successfully')
        return redirect('barangays')
        
    except Exception as e:
        messages.error(request, f'Failed to update barangay: {str(e)}')
        return redirect('barangays') 