import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0' 
import tensorflow as tf
import time
import sys
import django
from django.conf import settings
from django.db import connection
from dotenv import load_dotenv
import numpy as np
import joblib

# Load environment variables (needed for Django settings/DB config)
load_dotenv()

# Define file paths for the model and scalers.
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_FILE = os.path.join(BASE_DIR, "rain_model.h5")
SCALER_X_FILE = os.path.join(BASE_DIR, "scaler_X.pkl")
SCALER_Y_FILE = os.path.join(BASE_DIR, "scaler_y.pkl")

# Define the number of time steps (sequence length) the model requires.
SEQUENCE_LENGTH = 6

# =======================================================
# Barangay Land Description Data (REMOVED - Data now in DB)
# =======================================================
# The hardcoded dictionaries are removed as requested.
# The data is now fetched from the 'bago_city_barangay_risk' DB table.

# New global variable to store the data fetched from the DB
BARANGAY_RISK_DATA = {}

# =======================================================
# NEW: Database Function to fetch ALL Barangay Risk Data
# =======================================================
def get_all_barangay_risk_data_from_db():
    """
    Fetches all land and risk data from the new database table.
    
    Returns:
        dict: A dictionary mapping barangay name to its risk data.
    """
    global BARANGAY_RISK_DATA
    print("Fetching all barangay risk data from bago_city_barangay_risk table...")
    try:
        with connection.cursor() as cursor:
            query = """
            SELECT barangay_name, land_description, flood_risk_multiplier, flood_risk_summary
            FROM bago_city_barangay_risk
            """
            cursor.execute(query)
            data = cursor.fetchall()
            
            if not data:
                print("Error: No risk data found in the database. Using fallback.")
                return {}

            # Populate the global dictionary BARANGAY_RISK_DATA
            for name, land_type, multiplier, description in data:
                BARANGAY_RISK_DATA[name] = {
                    "land_type": land_type,
                    "risk_multiplier": float(multiplier),
                    "description": description
                }
            print(f"✅ Loaded risk data for {len(BARANGAY_RISK_DATA)} barangays.")
            return BARANGAY_RISK_DATA

    except Exception as e:
        print(f"❌ Error reading database for barangay risk data: {e}")
        print("Please ensure the 'bago_city_barangay_risk' table exists.")
        return {}


# =======================================================
# 1. Database Function (Sequence Data)
# =======================================================
def get_sequence_data_from_db():
    """
    Fetches the last SEQUENCE_LENGTH time steps of all required features
    from the database: temperature, humidity, wind_speed, barometric_pressure,
    and the hour of the day (derived from date_time).

    Returns:
        list[list]: A sequence of historical weather data (oldest to newest),
                    or None if insufficient data is found.
    """
    print(f"Fetching last {SEQUENCE_LENGTH} time steps of data from database...")
    try:
        with connection.cursor() as cursor:
            # NOTE: We assume 'weather_reports' now contains wind_speed and barometric_pressure.
            # We fetch date_time to calculate the 'hour_of_day' feature (0-23).
            query = """
            SELECT temperature, humidity, wind_speed, barometric_pressure, date_time
            FROM weather_reports
            ORDER BY date_time DESC
            LIMIT %s
            """
            cursor.execute(query, [SEQUENCE_LENGTH])
            data = cursor.fetchall()
            
            if not data or len(data) < SEQUENCE_LENGTH:
                print(f"Error: Found only {len(data)} records. {SEQUENCE_LENGTH} required for prediction.")
                return None
            
            # The data is fetched in reverse chronological order (newest first).
            # The sequence must be oldest to newest for the model.
            data.reverse()
            
            sequence = []
            for temp, humid, wind, pressure, dt in data:
                # dt is a datetime object from the database, extract the hour (0-23).
                hour_of_day = float(dt.hour)
                # The 5 features must be in the same order as the model training data.
                sequence.append([
                    float(temp),
                    float(humid),
                    float(wind),
                    float(pressure),
                    hour_of_day
                ])

            return sequence

    except Exception as e:
        print(f"Error reading database for sequence data: {e}")
        print("Please check your database configuration and table schema.")
        return None

# =======================================================
# 2. Model and Scalers Loading
# =======================================================
model = None
scaler_X = None
scaler_y = None

# Define the expected sequence length and feature count
SEQUENCE_LENGTH = 6 
FEATURE_COUNT = 5

# --- FIX START: Define dummy classes to handle deprecated/missing objects ---
# 1. Fix for InputLayer issues
class FixedInputLayer(tf.keras.layers.InputLayer):
    """Fixes multiple InputLayer compatibility issues."""
    def __init__(self, **kwargs):
        
        # 1. Handle the deprecated 'batch_shape' argument
        if 'batch_shape' in kwargs:
            kwargs.pop('batch_shape')
        
        # 2. Handle the shape issue causing the 'as_list() is not defined' error
        kwargs['input_shape'] = (SEQUENCE_LENGTH, FEATURE_COUNT)

        super(FixedInputLayer, self).__init__(**kwargs)

# 2. Fix for 'DTypePolicy' issues (Now with .variable_dtype)
class DTypePolicy:
    """Fixes 'DTypePolicy' compatibility issues by providing a dummy class 
    with placeholder attributes: .name, .compute_dtype, and .variable_dtype.
    """
    def __init__(self, *args, **kwargs):
        pass

    @property
    def name(self):
        return 'float32'
        
    @property
    def compute_dtype(self):
        return tf.float32 
        
    @property
    def variable_dtype(self):
        # ✨ NEW FIX: Fixes 'DTypePolicy' object has no attribute 'variable_dtype'
        return tf.float32 
# --- FIX END ---

try:
    # Include BOTH dummy objects in the custom_object_scope
    custom_objects = {
        'InputLayer': FixedInputLayer,
        'DTypePolicy': DTypePolicy
    }
    
    with tf.keras.utils.custom_object_scope(custom_objects):
        # The model loader will now use the custom classes for the problematic components
        model = tf.keras.models.load_model(MODEL_FILE, compile=False)

    model.compile(optimizer="adam", loss="mean_squared_error")
    print("✅ Model loaded successfully.")
    
    scaler_X = joblib.load(SCALER_X_FILE)
    scaler_y = joblib.load(SCALER_Y_FILE)
    print("✅ Scalers loaded successfully.")

except FileNotFoundError as e:
    print(f"Warning: One of the required files was not found: {e.filename}")
    print("Please ensure 'rain_model.h5', 'scaler_X.pkl', and 'scaler_y.pkl' are in the same directory.")
    print("ML prediction will be disabled.")
except Exception as e:
    print(f"Warning: An unexpected error occurred during file loading: {e}")
    print("ML prediction will be disabled.")

# =======================================================
# 3. Helper and Prediction Functions
# =======================================================
def get_rain_intensity(amount):
    """Categorizes rainfall amount into a label."""
    if amount <= 0.01:
        return "None"
    elif 0.01 < amount < 2.5:
        return "Light"
    elif 2.5 <= amount < 7.6:
        return "Moderate"
    elif 7.6 <= amount < 15:
        return "Heavy"
    elif 15 <= amount < 30:
        return "Intense"
    else:
        return "Torrential"

def predict_rain(input_features):
    """
    Predicts rainfall rate and duration using the loaded model.
    This function expects a NumPy array of shape (6, 5).
    
    Args:
        input_features (np.ndarray): The (6, 5) sequence of features.

    Returns:
        tuple: (rain_rate, duration, intensity_label)
    """
    
    # Extract the latest data point for fallback prediction
    latest_data = input_features[-1]
    latest_temp, latest_humidity, _, _, _ = latest_data

    if model is None or scaler_X is None or scaler_y is None:
        print("Warning: ML model not loaded. Using fallback prediction.")
        
        # Fallback logic using the latest temperature and humidity
        if latest_humidity > 80 and latest_temp < 30:
            rain_rate = 5.0
            duration = 30.0
        elif latest_humidity > 70:
            rain_rate = 2.0
            duration = 15.0
        else:
            rain_rate = 0.5
            duration = 5.0
        
        intensity = get_rain_intensity(rain_rate)
        return rain_rate, duration, intensity
    
    try:
        # Scale the entire 6-step input array
        # Reshaping to (6, 5) ensures the scaler works correctly on all 6 steps
        input_scaled = scaler_X.transform(input_features)
    except ValueError as e:
        print(f"Error during scaling: {e}")
        print("This may be due to a mismatch in the number of features (should be 5).")
        return None, None, "Error"

    # Reshape the data for the model (1 sample, 6 time steps, 5 features)
    X_seq = input_scaled.reshape(1, SEQUENCE_LENGTH, -1)
    
    y_pred_scaled = model.predict(X_seq, verbose=0)
    y_pred = scaler_y.inverse_transform(y_pred_scaled)
    
    rain_rate = max(0, float(y_pred[0][0]))
    duration = max(0, float(y_pred[0][1]))
    
    intensity = get_rain_intensity(rain_rate)
    return rain_rate, duration, intensity

def assess_flood_risk_by_barangay(rain_rate, duration, intensity_label):
    """
    Assesses flood risk for each of the 24 barangays of Bago City based on their
    land descriptions and geographical characteristics, using data loaded from the DB.

    Args:
        rain_rate (float): Predicted rainfall rate in mm
        duration (float): Predicted duration in minutes
        intensity_label (str): Rain intensity category

    Returns:
        list[dict]: A list of flood warnings for affected barangays
    """
    warnings = []
    
    # Iterate over the globally loaded DB data (BARANGAY_RISK_DATA)
    # This fulfills the request to use DB data without changing the function's core logic.
    for barangay, data in BARANGAY_RISK_DATA.items():
        land_type = data["land_type"]
        risk_multiplier = data["risk_multiplier"]
        land_description = data["description"]
        
        # Calculate adjusted risk based on land type
        adjusted_rain_threshold = 2.5 / risk_multiplier  # Lower threshold for high-risk areas
        adjusted_duration_threshold = 60 / risk_multiplier  # Lower duration threshold for high-risk areas
        
        # Determine risk level based on adjusted thresholds
        if rain_rate >= adjusted_rain_threshold or (rain_rate > 0.5 and duration > adjusted_duration_threshold):
            # High risk conditions
            if intensity_label in ["Heavy", "Intense", "Torrential"] or rain_rate >= 7.6:
                risk_level = "High"
                message = f"High flood risk in {barangay} due to predicted {intensity_label} rain ({rain_rate:.1f}mm) over {duration:.0f} minutes. {land_description}."
            else:
                risk_level = "Moderate"
                message = f"Moderate flood risk in {barangay} due to predicted {intensity_label} rain. {land_description}."
                
            warning = {
                "barangay": barangay,
                "land_type": land_type,
                "area": f"{barangay} ({land_type.replace('_', ' ').title()})",
                "risk_level": risk_level,
                "message": message,
                "rain_rate": rain_rate,
                "duration": duration,
                "intensity": intensity_label
            }
            warnings.append(warning)
            
        elif rain_rate > 1.0 and risk_multiplier > 1.0:  # Only warn low-lying areas for light rain
            # Low risk conditions for high-risk areas only
            warning = {
                "barangay": barangay,
                "land_type": land_type,
                "area": f"{barangay} ({land_type.replace('_', ' ').title()})",
                "risk_level": "Low",
                "message": f"Low flood risk in {barangay}. Monitor conditions as {land_description}.",
                "rain_rate": rain_rate,
                "duration": duration,
                "intensity": intensity_label
            }
            warnings.append(warning)
    
    # Sort warnings by risk level (High, Moderate, Low)
    risk_priority = {"High": 3, "Moderate": 2, "Low": 1}
    warnings.sort(key=lambda x: risk_priority.get(x["risk_level"], 0), reverse=True)
    
    return warnings

def get_barangay_info(barangay_name):
    """
    Get land description and risk information for a specific barangay, now using 
    the globally loaded DB data.
    """
    data = BARANGAY_RISK_DATA.get(barangay_name, {})
    land_type = data.get("land_type", "unknown")
    
    return {
        "barangay": barangay_name,
        "land_type": land_type,
        "risk_multiplier": data.get("risk_multiplier", 1.0),
        "description": data.get("description", "Unknown risk level"),
        "area_type": land_type.replace('_', ' ').title()
    }

def get_all_barangays_info():
    """
    Get information for all 24 barangays of Bago City, now using 
    the globally loaded DB data.
    """
    return [get_barangay_info(barangay) for barangay in BARANGAY_RISK_DATA.keys()]

def get_users_by_barangay(barangay_name):
    """
    Get all users from a specific barangay for targeted SMS alerts.
    
    Args:
        barangay_name (str): Name of the barangay
        
    Returns:
        list[dict]: List of user information with phone numbers
    """
    try:
        from django.db import connection
        
        with connection.cursor() as cursor:
            # Get users from the specified barangay (using address field to match barangay)
            cursor.execute("""
                SELECT u.user_id, u.name, u.phone_num, u.address
                FROM user u
                WHERE u.address LIKE %s AND u.phone_num IS NOT NULL AND u.phone_num != ''
            """, [f"%{barangay_name}%"])
            
            users = []
            for row in cursor.fetchall():
                user_id, name, phone_num, address = row
                users.append({
                    'user_id': user_id,
                    'name': name,
                    'phone_num': phone_num,
                    'barangay': barangay_name,
                    'address': address
                })
            
            return users
            
    except Exception as e:
        print(f"Error getting users by barangay {barangay_name}: {e}")
        return []

def get_users_by_affected_barangays(flood_warnings):
    """
    Get all users from barangays that have flood warnings.
    
    Args:
        flood_warnings (list): List of flood warning dictionaries
        
    Returns:
        dict: Dictionary with barangay names as keys and user lists as values
    """
    affected_users = {}
    
    for warning in flood_warnings:
        barangay = warning.get('barangay')
        if barangay and barangay not in affected_users:
            users = get_users_by_barangay(barangay)
            if users:
                affected_users[barangay] = users
    
    return affected_users

def assess_flood_risk(rain_rate, duration, intensity_label):
    """
    Legacy function maintained for backward compatibility.
    Now calls the enhanced barangay-specific assessment.
    """
    return assess_flood_risk_by_barangay(rain_rate, duration, intensity_label)

# =======================================================
# 4. Main Execution Block
# =======================================================
def main():
    """Main function to orchestrate data fetching and prediction."""
    print("\n--- Live Rainfall Prediction Demo (Database Only) ---")
    
    try:
        # Django setup (copied from original)
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        sys.path.append(project_root)
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weather_app.settings')
        django.setup()
        
        # --- NEW STEP: Load the land and risk data from the DB first ---
        get_all_barangay_risk_data_from_db()
        if not BARANGAY_RISK_DATA:
            print("Prediction cannot proceed without barangay risk data. Exiting.")
            return
            
        # --- Step 1: Fetch 6 steps of data from your database ---
        sequence_data_list = get_sequence_data_from_db()
        
        if sequence_data_list is None:
            print("Prediction failed due to insufficient or missing data. Exiting.")
            return

        # Convert list of lists (6, 5) to NumPy array for ML processing
        input_features_array = np.array(sequence_data_list, dtype=np.float32)

        # Extract the latest data point for display
        # Order: [temp, humid, wind, pressure, hour_of_day]
        latest_temp, latest_humidity, wind_speed, barometric_pressure, current_hour = input_features_array[-1]
        
        print("\nData collected from the database (latest entry):")
        print(f"Temperature: {latest_temp:.2f}°C, Humidity: {latest_humidity:.2f}%")
        print(f"Wind Speed: {wind_speed:.2f} m/s, Barometric Pressure: {barometric_pressure:.2f} hPa")
        print(f"Hour of Day: {int(current_hour)}")
        
        # --- Step 2: Make the prediction ---
        # Pass the full (6, 5) feature array to the prediction function
        predicted_rain_rate, predicted_duration, intensity_label = predict_rain(input_features_array)
        
        if predicted_rain_rate is None:
            print("Prediction failed during ML model execution.")
            return

        print("\n--- Prediction Results ---")
        print(f"Predicted Rainfall: {predicted_rain_rate:.2f} mm")
        print(f"Estimated Duration: {predicted_duration:.2f} minutes")
        print(f"Rainfall Intensity: {intensity_label}")

        # --- Step 3: Insert Rain Prediction results into the database ---
        try:
            with connection.cursor() as cursor:
                # Insert the prediction results
                cursor.execute("""
                    INSERT INTO ai_predictions (predicted_rain, duration, intensity, prediction_date)
                    VALUES (%s, %s, %s, NOW())
                """, [predicted_rain_rate, predicted_duration, intensity_label])
            print("✅ Rain prediction results successfully inserted into the database.")
        except Exception as e:
            print(f"❌ Error inserting rain prediction results into the database: {e}")
            
        # ------------------------------------------------------------------
        # --- Step 4: Assess Flood Risk by Barangay and Insert Warnings ---
        # ------------------------------------------------------------------
        flood_warnings = assess_flood_risk_by_barangay(predicted_rain_rate, predicted_duration, intensity_label)
        
        if flood_warnings:
            print(f"\n--- FLOOD WARNINGS ISSUED FOR {len(flood_warnings)} BARANGAYS ---")
            try:
                with connection.cursor() as cursor:
                    # Clear previous warnings to avoid duplicates (e.g., within the last hour)
                    cursor.execute("DELETE FROM flood_warnings WHERE prediction_date >= DATE_SUB(NOW(), INTERVAL 1 HOUR)")
                    
                    for warning in flood_warnings:
                        # Print to console
                        print(f"🚨 {warning['risk_level']} Risk for {warning['barangay']} ({warning['land_type']}): {warning['message']}")
                        
                        # Insert the enhanced flood warning results with barangay information
                        cursor.execute("""
                            INSERT INTO flood_warnings (area, risk_level, message, prediction_date)
                            VALUES (%s, %s, %s, NOW())
                        """, [warning['area'], warning['message'], warning['risk_level']])
                        
                print(f"✅ {len(flood_warnings)} flood warnings successfully inserted into the database.")
                
                # Print summary by risk level
                high_risk = [w for w in flood_warnings if w['risk_level'] == 'High']
                moderate_risk = [w for w in flood_warnings if w['risk_level'] == 'Moderate']
                low_risk = [w for w in flood_warnings if w['risk_level'] == 'Low']
                
                if high_risk:
                    print(f"🔴 HIGH RISK: {len(high_risk)} barangays - {', '.join([w['barangay'] for w in high_risk])}")
                if moderate_risk:
                    print(f"🟡 MODERATE RISK: {len(moderate_risk)} barangays - {', '.join([w['barangay'] for w in moderate_risk])}")
                if low_risk:
                    print(f"🟢 LOW RISK: {len(low_risk)} barangays - {', '.join([w['barangay'] for w in low_risk])}")
                
                # ------------------------------------------------------------------
                # --- Step 5: Send Targeted SMS Alerts to Affected Barangays ---
                # ------------------------------------------------------------------
                try:
                    # NOTE: Assuming this path is correct for your project structure
                    from weatherapp.sms_targeted_alerts import send_targeted_sms_alerts
                    
                    sms_result = send_targeted_sms_alerts(
                        flood_warnings, 
                        predicted_rain_rate, 
                        predicted_duration, 
                        intensity_label
                    )
                    
                    if sms_result["success"]:
                        print(f"✅ SMS Alerts: {sms_result['total_sent']} sent, {sms_result['total_failed']} failed")
                    else:
                        print(f"❌ SMS Alert Error: {sms_result.get('error', 'Unknown error')}")
                        
                except Exception as e:
                    print(f"❌ Error sending targeted SMS alerts: {e}")
                    
            except Exception as e:
                print(f"❌ Error inserting flood warnings into the database: {e}")
        else:
            print("\n✅ No flood warnings issued - all barangays are safe from flooding.")


    except Exception as e:
        print(f"An unexpected error occurred in the main function: {e}")

if __name__ == "__main__":
    main()