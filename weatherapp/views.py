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
from datetime import datetime, timedelta
from calendar import month_name
import pytz
from decimal import Decimal
import requests
import time
from django.conf import settings

def register_user(request):
    if request.method == 'POST':
        errors = {}
        
        name = request.POST.get('name')
        province = request.POST.get('province')
        city = request.POST.get('city')
        barangay = request.POST.get('barangay')
        email = request.POST.get('email')
        phone = request.POST.get('phone_num')
        id_card = request.FILES.get('id_card')
        username = request.POST.get('username')
        password = request.POST.get('password')
        confirm_password = request.POST.get('confirm_password')

        address = f"{barangay}, {city}, {province}"
        
        id_card_path = None

        # Validation (same as before)
        if not id_card:
            errors['id_card'] = "ID Card is required."
        else:
            allowed_types = ['image/jpeg', 'image/png', 'application/pdf']
            max_size = 2 * 1024 * 1024

            if id_card.content_type not in allowed_types:
                errors['id_card'] = "Only JPG, PNG, or PDF files are allowed."
            elif id_card.size > max_size:
                errors['id_card'] = "ID Card must be under 2MB."
            else:
                fs = FileSystemStorage(location=os.path.join(settings.MEDIA_ROOT, 'id_cards'))
                filename = fs.save(id_card.name, id_card)
                id_card_path = 'id_cards/' + filename

        if not re.match(r"[^@]+@[^@]+\.[^@]+", email):
            errors['email'] = "Invalid email format."

        if not re.match(r"^\d{11}$", phone):
            errors['phone_num'] = "Phone number must be exactly 11 digits."

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

        if password != confirm_password:
            errors['confirm_password'] = "Passwords do not match."

        # Database checks
        with connection.cursor() as cursor:
            cursor.execute("SELECT user_id FROM user WHERE username = %s", [username])
            if cursor.fetchone():
                errors['username'] = "Username already exists."

            cursor.execute("SELECT user_id FROM user WHERE name = %s", [name])
            if cursor.fetchone():
                errors['name'] = "Name already exists."

        if errors:
            return JsonResponse({
                'success': False,
                'errors': errors,
            })

        hashed_password = make_password(password)

        try:
            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO user (name, address, email, phone_num, username, password, id_card, status)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, 'Active')
                """, [name, address, email, phone, username, hashed_password, id_card_path])
            
            return JsonResponse({
                'success': True,
                'message': "Registration successful!",
            })

        except Exception as e:
            return JsonResponse({
                'success': False,
                'errors': {'database': f"Error during registration: {str(e)}"}
            })
    
    return JsonResponse({
        'success': False,
        'errors': {'method': 'Invalid request method.'}
    })

def check_username(request):
    username = request.GET.get('username')
    if not username:
        return JsonResponse({'exists': False})
    
    with connection.cursor() as cursor:
        cursor.execute("SELECT user_id FROM user WHERE username = %s", [username])
        exists = cursor.fetchone() is not None
    
    return JsonResponse({'exists': exists})

def check_name(request):
    name = request.GET.get('name')
    if not name:
        return JsonResponse({'exists': False})
    
    with connection.cursor() as cursor:
        cursor.execute("SELECT user_id FROM user WHERE name = %s", [name])
        exists = cursor.fetchone() is not None
    
    return JsonResponse({'exists': exists})


def home(request):
    
    logout_success = request.session.pop('form_logoutSuccess', None)
    
    return render(request, 'home.html', {
        'form_logoutSuccess': logout_success
    })


def login_view(request):
    if request.method == "POST":
        username = request.POST.get('username')
        password = request.POST.get('password')
        remember_me = request.POST.get('remember_me')  # Checkbox value (None if unchecked)

        with connection.cursor() as cursor:
            cursor.execute("SELECT user_id, username, password, status FROM user WHERE username = %s", [username])
            user_data = cursor.fetchone()

        if user_data:
            user_id, db_username, db_hashed_password, status = user_data
            if status == 'Pending':
                form_loginError = "Your account is still pending for approval."
            elif check_password(password, db_hashed_password):
                request.session['user_id'] = user_id
                request.session['username'] = db_username
                
                # Set session expiry based on "Remember Me" selection
                if remember_me:
                    # Persistent session for 30 days
                    request.session.set_expiry(30 * 24 * 60 * 60)  # 30 days in seconds
                else:
                    # Session expires when browser closes
                    request.session.set_expiry(0)
                
                return redirect('user_dashboard')
            else:
                form_loginError = "Invalid username or password."
        else:
            with connection.cursor() as cursor:
                cursor.execute("SELECT admin_id, username, password, status FROM admin WHERE username = %s", [username])
                admin_data = cursor.fetchone()

            if admin_data:
                admin_id, db_username, db_hashed_password, status = admin_data
                if status != 'Active':
                    form_loginError = "Account has been deactivated."
                elif check_password(password, db_hashed_password):
                    request.session['admin_id'] = admin_id
                    request.session['username'] = db_username
                    
                    # Set session expiry for admin as well
                    if remember_me:
                        request.session.set_expiry(30 * 24 * 60 * 60)
                    else:
                        request.session.set_expiry(0)
                    
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

@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def admin_dashboard(request):
    if 'admin_id' not in request.session:
        return redirect('home')
    
    admin_id = request.session['admin_id']
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [admin_id])
        row = cursor.fetchone()
        admin_name = row[0] if row else 'Admin'
    
    def get_rain_intensity(amount):
        if amount == 0:
            return "None"
        elif amount > 0 and amount < 2.5:
            return "Light"
        elif amount > 2.5 and amount < 7.6:
            return "Moderate"
        elif amount > 7.6 and amount < 15:
            return "Heavy"
        elif amount > 15 and amount < 30:
            return "Intense"
        else:
            return "Torrential"
    
    selected_sensor_id = request.GET.get('sensor_id')
    
    with connection.cursor() as cursor:
        # Get admin name
        cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [admin_id])
        row = cursor.fetchone()
        admin_name = row[0] if row else 'Admin'

        # Get all available sensors
        cursor.execute("SELECT sensor_id, name FROM sensor ORDER BY name")
        available_sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]

        # Get weather data for selected sensor (or first sensor if none selected)
        if selected_sensor_id:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.date_time, s.name
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                WHERE wr.sensor_id = %s
                ORDER BY wr.date_time DESC
                LIMIT 1
            """, [selected_sensor_id])
        else:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.date_time, s.name
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                ORDER BY wr.date_time DESC
                LIMIT 1
            """)
        
        row = cursor.fetchone()
        if row:
            weather = {
                'temperature': row[0],
                'humidity': row[1],
                'rain_rate': row[2],
                'dew_point': row[3],
                'wind_speed': row[4],
                'date_time': row[5].strftime('%Y-%m-%d %H:%M:%S'),
                'location': row[6],
                'error': None
            }
            current_sensor_id = selected_sensor_id if selected_sensor_id else available_sensors[0]['sensor_id']
        else:
            weather = {
                'error': 'No weather data available',
                'temperature': 'N/A',
                'humidity': 'N/A',
                'rain_rate': 'N/A',
                'dew_point': 'N/A',
                'wind_speed': 'N/A',
                'date_time': 'N/A',
                'location': 'Unknown'
            }
            current_sensor_id = None

    forecast = get_five_day_forecast()
    if isinstance(forecast, dict) and 'error' in forecast:
        forecast = []

    locations_dict = {}
    with connection.cursor() as cursor:
        cursor.execute("SELECT sensor_id, name, latitude, longitude FROM sensor")
        rows = cursor.fetchall()
        for sensor_id, name, lat, lon in rows:
            locations_dict[sensor_id] = {
                'name': name,
                'latitude': lat,
                'longitude': lon,
                'has_alert': False
            }

    alerts = []
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT sensor.sensor_id, sensor.name, weather_reports.rain_rate, weather_reports.wind_speed
            FROM weather_reports
            JOIN sensor ON weather_reports.sensor_id = sensor.sensor_id
        """)
        rows = cursor.fetchall()
        for sensor_id, name, rain_rate, wind_speed in rows:
            if rain_rate is not None:
                intensity = get_rain_intensity(rain_rate)
                if intensity in ["Heavy", "Intense", "Torrential"]:
                    alerts.append(f"⚠️ {intensity} Rainfall Alert in {name} ({rain_rate} mm)")
                    if sensor_id in locations_dict:
                        locations_dict[sensor_id]['has_alert'] = True
            if wind_speed and wind_speed > 30:
                alerts.append(f"⚠️ Wind Advisory for {name} ({wind_speed} m/s)")
                if sensor_id in locations_dict:
                    locations_dict[sensor_id]['has_alert'] = True

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT DATE_FORMAT(date_time, '%a %b %d') AS label, temperature
            FROM weather_reports
            ORDER BY date_time DESC
            LIMIT 10
        """)
        rows = cursor.fetchall()

    labels = [row[0] for row in rows]
    temps = [float(row[1]) for row in rows]

    context = {
        'admin': {'name': admin_name},
        'locations': list(locations_dict.values()),
        'weather': weather,
        'forecast': forecast,
        'alerts': alerts,
        'labels': json.dumps(labels),
        'data': json.dumps(temps),
        'available_sensors': available_sensors,
        'current_sensor_id': current_sensor_id
    }

    return render(request, 'admin_dashboard.html', context)


@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def user_dashboard(request):
    if 'user_id' not in request.session:
        return redirect('home')
    
    selected_sensor_id = request.GET.get('sensor_id')

    
    user_id = request.session['user_id']
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM user WHERE user_id = %s", [user_id])
        row = cursor.fetchone()
        user_name = row[0] if row else 'User'
    
        cursor.execute("SELECT sensor_id, name FROM sensor ORDER BY name")
        available_sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]

        # Get weather data for selected sensor (or first sensor if none selected)
        if selected_sensor_id:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.date_time, s.name
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                WHERE wr.sensor_id = %s
                ORDER BY wr.date_time DESC
                LIMIT 1
            """, [selected_sensor_id])
        else:
            cursor.execute("""
                SELECT wr.temperature, wr.humidity, wr.rain_rate, wr.dew_point, 
                       wr.wind_speed, wr.date_time, s.name
                FROM weather_reports wr
                JOIN sensor s ON wr.sensor_id = s.sensor_id
                ORDER BY wr.date_time DESC
                LIMIT 1
            """)
        
        row = cursor.fetchone()
        if row:
            weather = {
                'temperature': row[0],
                'humidity': row[1],
                'rain_rate': row[2],
                'dew_point': row[3],
                'wind_speed': row[4],
                'date_time': row[5].strftime('%Y-%m-%d %H:%M:%S'),
                'location': row[6],
                'error': None
            }
            current_sensor_id = selected_sensor_id if selected_sensor_id else available_sensors[0]['sensor_id']
        else:
            weather = {
                'error': 'No weather data available',
                'temperature': 'N/A',
                'humidity': 'N/A',
                'rain_rate': 'N/A',
                'dew_point': 'N/A',
                'wind_speed': 'N/A',
                'date_time': 'N/A',
                'location': 'Unknown'
            }
            current_sensor_id = None
    
    forecast = get_five_day_forecast()
    if isinstance(forecast, dict) and 'error' in forecast:
        forecast = []
    
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT DATE_FORMAT(date_time, '%a %b %d') AS label, temperature
            FROM weather_reports
            ORDER BY date_time DESC
            LIMIT 10
        """)
        rows = cursor.fetchall()

    labels = [row[0] for row in rows]
    temps = [float(row[1]) for row in rows]
    
    context = {
        'user': {'name': user_name},
        'weather': weather,
        'forecast': forecast,
        'labels': json.dumps(labels),
        'data': json.dumps(temps),
        'available_sensors': available_sensors,
        'current_sensor_id': current_sensor_id
    }
    
    return render(request, 'user_dashboard.html', context)

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

    if row:
        user_profile = {
            'name': row[0],
            'email': row[1],
            'phone_num': row[2],
            'username': row[3]
        }
    else:
        user_profile = {}

    form_userSuccess = request.session.pop('form_userSuccess', None)
    form_userError = request.session.pop('form_userError', None)

    context = {
        'user_profile': user_profile,
        'form_userSuccess': form_userSuccess,
        'form_userError': form_userError,
    }
    
    return render(request, 'user_profile.html', context)
    
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

            # Get active users
            cursor.execute("""
                SELECT user_id, name, address, email, phone_num, id_card, status, username 
                FROM user 
                WHERE status = 'Active'
                ORDER BY name
            """)
            users = [{
                'id': row[0],
                'name': row[1],
                'address': row[2],
                'email': row[3],
                'phone_num': row[4],
                'id_card': row[5],
                'status': row[6],
                'username': row[7],
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
def pending_user(request):
    if 'admin_id' not in request.session:
        messages.error(request, 'Please login to access this page')
        return redirect('home')
    
    try:
        with connection.cursor() as cursor:
            # 1. Get admin info - handle case where admin doesn't exist
            cursor.execute("SELECT name FROM admin WHERE admin_id = %s", [request.session['admin_id']])
            admin_row = cursor.fetchone()
            
            if not admin_row:  # Admin not found
                messages.error(request, 'Admin account not found')
                return redirect('admin_dashboard')
                
            admin_name = admin_row[0]

            # 2. Get pending users - empty list is acceptable
            cursor.execute("""
                SELECT user_id, name, address, email, phone_num, id_card, status, username 
                FROM user 
                WHERE status = 'Pending'
                ORDER BY name
            """)
            
            # This will be empty if no pending users exist
            users = [{
                'id': row[0],
                'name': row[1],
                'address': row[2],
                'email': row[3],
                'phone_num': row[4],
                'id_card': row[5],
                'status': row[6],
                'username': row[7],
            } for row in cursor.fetchall()]

        # This will render even with empty users list
        return render(request, 'managePending_user.html', {
            'users': users,  # Could be empty list
            'admin': {'name': admin_name},
            'current_url': 'pending_user'
        })

    except Exception as e:
        messages.error(request, f'Database error: {str(e)}')
        return redirect('admin_dashboard')

def activate_user(request, user_id):
    if 'admin_id' not in request.session:
        return HttpResponseForbidden("Not authorized")
    
    if request.method != 'POST':
        return HttpResponseForbidden("Invalid request method")

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT email, name FROM user WHERE user_id = %s", [user_id])
            result = cursor.fetchone()

        if not result:
            messages.error(request, "User not found")
            return redirect('pending_user')

        email, name = result

        with connection.cursor() as cursor:
            cursor.execute("UPDATE user SET status = 'Active' WHERE user_id = %s", [user_id])

        try:
            send_mail(
                subject='Your WeatherAlert Account Has Been Activated',
                message=f'Hello {name},\n\nYour account has been successfully activated. You may now log in and use the system.\n\nThank you!',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=False,
            )
            messages.success(request, "User activated successfully and email sent")
        except Exception as e:
            messages.warning(request, f"User activated but email failed to send: {str(e)}")

    except Exception as e:
        messages.error(request, f"Activation failed: {str(e)}")

    return redirect('pending_user')

def decline_user(request, user_id):
    if 'admin_id' not in request.session:
        return HttpResponseForbidden("Not authorized")
    
    if request.method != 'POST':
        return HttpResponseForbidden("Invalid request method")

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT email, name FROM user WHERE user_id = %s", [user_id])
            result = cursor.fetchone()

        if not result:
            messages.error(request, "User not found")
            return redirect('pending_user')

        email, name = result

        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM user WHERE user_id = %s", [user_id])

        try:
            send_mail(
                subject='Your WeatherAlert Account Registration Was Declined',
                message=f'Hello {name},\n\nWe regret to inform you that your registration for the WeatherAlert system has been declined.\n\nFor further inquiries, please contact support.\n\nThank you.',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=False,
            )
            messages.success(request, "User declined and email sent")
        except Exception as e:
            messages.warning(request, f"User declined but email failed to send: {str(e)}")

    except Exception as e:
        messages.error(request, f"Decline failed: {str(e)}")

    return redirect('pending_user')


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
            cursor.execute("SELECT sensor_id, name, latitude, longitude FROM sensor ORDER BY name")
            sensors = [{
                'id': row[0],
                'name': row[1],
                'latitude': row[2],
                'longitude': row[3]
            } for row in cursor.fetchall()]

        # Check for form errors from previous submission
        form_errors = request.session.pop('form_errors', {})
        form_data = request.session.pop('form_data', {})

        return render(request, 'sensors.html', {
            'sensors': sensors,
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

    # Validation
    errors = {}
    if not name:
        errors['name'] = 'Name is required'
    if not is_valid_coordinate(latitude, 'latitude'):
        errors['latitude'] = 'Valid latitude is required (-90 to 90)'
    if not is_valid_coordinate(longitude, 'longitude'):
        errors['longitude'] = 'Valid longitude is required (-180 to 180)'

    if errors:
        request.session['form_errors'] = errors
        request.session['form_data'] = {
            'name': name,
            'latitude': latitude,
            'longitude': longitude
        }
        request.session['show_add_modal'] = True
        return redirect('sensors')

    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO sensor (name, latitude, longitude)
                VALUES (%s, %s, %s)
            """, [name, latitude, longitude])
        
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

    # Validation
    errors = {}
    if not name:
        errors['name'] = 'Name is required'
    if not is_valid_coordinate(latitude, 'latitude'):
        errors['latitude'] = 'Valid latitude is required (-90 to 90)'
    if not is_valid_coordinate(longitude, 'longitude'):
        errors['longitude'] = 'Valid longitude is required (-180 to 180)'

    if errors:
        messages.error(request, 'Invalid sensor data')
        return redirect('sensors')

    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                UPDATE sensor
                SET name = %s, latitude = %s, longitude = %s
                WHERE sensor_id = %s
            """, [name, latitude, longitude, sensor_id])
        
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
            wr.wind_direction,
            wr.barometric_pressure,
            wr.dew_point, 
            wr.date_time, 
            wr.rain_rate, 
            i.intensity AS intensity, 
            wr.rain_accumulated 
        FROM weather_reports wr
        JOIN sensor s ON wr.sensor_id = s.sensor_id 
        JOIN intensity i ON wr.intensity_id = i.intensity_id
    """
    
    # Build WHERE conditions
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
            AVG(temperature) as avg_temp,
            MAX(wind_speed) as max_wind,
            AVG(humidity) as avg_humidity,
            SUM(rain_accumulated) as total_rain
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
            'avg_temp': round(summary_row[0], 1) if summary_row[0] is not None else None,
            'max_wind': round(summary_row[1], 1) if summary_row[1] is not None else None,
            'avg_humidity': round(summary_row[2], 1) if summary_row[2] is not None else None,
            'total_rain': round(summary_row[3], 2) if summary_row[3] is not None else None
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
            AVG(wr.wind_direction) AS avg_wind_direction,
            AVG(wr.barometric_pressure) AS avg_barometric_pressure,
            AVG(wr.dew_point) AS avg_dew_point,
            AVG(wr.rain_rate) AS avg_rain_rate,
            SUM(wr.rain_accumulated) AS total_rain_accumulated
        FROM weather_reports wr
        JOIN sensor s ON wr.sensor_id = s.sensor_id
    """
    
    summary_query = """
        SELECT 
            AVG(wr.temperature) AS avg_temp,
            MAX(wr.wind_speed) AS max_wind,
            AVG(wr.humidity) AS avg_humidity,
            SUM(wr.rain_accumulated) AS total_rain
        FROM weather_reports wr
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
        report_query += where_clause
        summary_query += where_clause
    
    report_query += " GROUP BY s.name, DATE(wr.date_time) ORDER BY date DESC"
    
    with connection.cursor() as cursor:
        cursor.execute(report_query, params)
        columns = [col[0] for col in cursor.description]
        reports = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        cursor.execute(summary_query, params)
        summary_row = cursor.fetchone()
        summary_stats = {
            'avg_temp': round(summary_row[0], 1) if summary_row[0] is not None else "N/A",
            'max_wind': round(summary_row[1], 1) if summary_row[1] is not None else "N/A",
            'avg_humidity': round(summary_row[2], 1) if summary_row[2] is not None else "N/A",
            'total_rain': round(summary_row[3], 2) if summary_row[3] is not None else "N/A"
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

    current_date = datetime.now()
    current_year = current_date.year
    current_month = current_date.month

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT DISTINCT YEAR(date_time) as year 
            FROM weather_reports 
            ORDER BY year DESC
        """)
        available_years = [row[0] for row in cursor.fetchall()]

    report_query = """
        SELECT 
            s.name AS name,
            DATE_FORMAT(wr.date_time, '%%Y-%%m') AS month,
            AVG(wr.temperature) AS avg_temperature,
            AVG(wr.humidity) AS avg_humidity,
            AVG(wr.wind_speed) AS avg_wind_speed,
            AVG(wr.wind_direction) AS avg_wind_direction,
            AVG(wr.barometric_pressure) AS avg_barometric_pressure,
            AVG(wr.dew_point) AS avg_dew_point,
            AVG(wr.rain_rate) AS avg_rain_rate,
            SUM(wr.rain_accumulated) AS total_rain_accumulated
        FROM weather_reports wr
        JOIN sensor s ON wr.sensor_id = s.sensor_id
    """
    
    summary_query = """
        SELECT 
            AVG(wr.temperature) AS avg_temp,
            MAX(wr.wind_speed) AS max_wind,
            AVG(wr.humidity) AS avg_humidity,
            SUM(wr.rain_accumulated) AS total_rain
        FROM weather_reports wr
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
        report_query += where_clause
        summary_query += where_clause
    
    report_query += """
        GROUP BY s.name, YEAR(wr.date_time), MONTH(wr.date_time)
        ORDER BY YEAR(wr.date_time) DESC, MONTH(wr.date_time) DESC
    """
    
    with connection.cursor() as cursor:
        cursor.execute(report_query, params)
        columns = [col[0] for col in cursor.description]
        reports = []
        for row in cursor.fetchall():
            report = dict(zip(columns, row))
            report['month'] = datetime.strptime(report['month'], '%Y-%m').date()
            reports.append(report)
        
        cursor.execute(summary_query, params)
        summary_row = cursor.fetchone()
        summary_stats = {
            'avg_temp': round(summary_row[0], 1) if summary_row[0] is not None else "N/A",
            'max_wind': round(summary_row[1], 1) if summary_row[1] is not None else "N/A",
            'avg_humidity': round(summary_row[2], 1) if summary_row[2] is not None else "N/A",
            'total_rain': round(summary_row[3], 2) if summary_row[3] is not None else "N/A"
        }
        
        cursor.execute("SELECT sensor_id, name FROM sensor")
        sensors = [{'sensor_id': row[0], 'name': row[1]} for row in cursor.fetchall()]

    month_names = [month_name[i] for i in range(1, 13)]

    context = {
        'reports': reports,
        'summary_stats': summary_stats,
        'sensors': sensors,
        'available_years': available_years,
        'current_year': current_year,
        'current_month': current_month,
        'month_names': month_names,
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
        elif amount > 0 and amount < 2.5:
            return "Light"
        elif amount > 2.5 and amount < 7.6:
            return "Moderate"
        elif amount > 7.6 and amount < 15:
            return "Heavy"
        elif amount > 15 and amount < 30:
            return "Intense"
        else:
            return "Torrential"

@csrf_exempt
def receive_sensor_data(request):
    if request.method == "POST":
        try:
            data = json.loads(request.body)

            temperature = float(data.get('temperature'))
            humidity = float(data.get('humidity'))
            sensor_id = int(data.get('sensor_id'))

            rain_rate = 0.0 
            rain_accumulated = float(data.get('rain_accumulated', 0))
            wind_speed = float(data.get('wind_speed', 0))
            wind_direction = data.get('wind_direction', '')
            pressure = float(data.get('barometric_pressure', 0))

            dew_point = temperature - ((100 - humidity) / 5)

            intensity_label = get_rain_intensity(rain_rate)

            with connection.cursor() as cursor:
                cursor.execute("SELECT intensity_id FROM intensity WHERE intensity = %s", [intensity_label])
                row = cursor.fetchone()
                if row:
                    intensity_id = row[0]
                else:
                    return JsonResponse({"error": f"Invalid intensity label: {intensity_label}"}, status=400)

            ph_time = now().astimezone(pytz.timezone('Asia/Manila'))
            
            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO weather_reports (
                        sensor_id, intensity_id, temperature, humidity,
                        wind_speed, wind_direction, barometric_pressure,
                        dew_point, date_time, rain_rate, rain_accumulated
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, [
                    sensor_id, intensity_id, temperature, humidity,
                    wind_speed, wind_direction, pressure,
                    dew_point, ph_time, rain_rate, rain_accumulated
                ])

            return JsonResponse({"status": "success"}, status=201)

        except Exception as e:
            return JsonResponse({"error": str(e)}, status=400)

    return JsonResponse({"error": "Invalid request"}, status=405)

@csrf_exempt
def send_alert(request):
    if request.method == "POST":
        try:
            addresses = request.POST.getlist("address") or [request.POST.get("address")]
            alert_type = request.POST.get("alert_type")
            severity = request.POST.get("severity")

            if not addresses or not alert_type or not severity:
                return HttpResponse("All fields are required", status=400)

            message = f"{severity.upper()} {alert_type.upper()} ALERT in {', '.join(addresses)}. Stay safe and take precautions."

            # Save alert to database
            with connection.cursor() as cursor:
                for address in addresses:
                    cursor.execute(
                        """
                        INSERT INTO alerts (alert_type, severity, message, address, sent_at)
                        VALUES (%s, %s, %s, %s, %s)
                        """,
                        [alert_type, severity, message, address, now()]
                    )

            # Get phone numbers
            phone_numbers = []
            with connection.cursor() as cursor:
                format_strings = ','.join(['%s'] * len(addresses))
                query = f"SELECT phone_num FROM user WHERE address IN ({format_strings})"
                cursor.execute(query, addresses)
                rows = cursor.fetchall()
                phone_numbers = [
                    "63" + row[0][1:] if row[0].startswith("0") else row[0]
                    for row in rows if row[0]
                ]

            # SMS sending with rate limiting
            headers = {
                'apikey': settings.SMS_API_KEY
            }
            sent_count = 0

            for number in phone_numbers:
                if sent_count >= 2:  # Limit to 2 SMS
                    time.sleep(2)  # Wait 2 seconds before next batch
                    sent_count = 0

                params = {
                    'message': message,
                    'mobile_number': number,
                    'device': settings.SMS_DEVICE_ID
                }

                try:
                    response = requests.post(
                        settings.SMS_API_URL,
                        headers=headers,
                        data=params,
                        timeout=2  # 2-second timeout
                    )

                    if response.status_code == 200:
                        print(f"[SMS SUCCESS] To: {number}")
                    else:
                        print(f"[SMS ERROR] To: {number} - {response.text}")

                    sent_count += 1

                except requests.exceptions.RequestException as e:
                    print(f"[SMS ERROR] To: {number} - {str(e)}")

            return HttpResponse("Alert sent successfully")

        except Exception as e:
            print(f"[ERROR] {e}")
            return HttpResponse("Failed to send alert", status=500)

    return HttpResponse("Invalid request method.", status=405)
