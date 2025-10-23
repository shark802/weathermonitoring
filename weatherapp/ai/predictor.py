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
from datetime import datetime
import pytz 

# Load environment variables (needed for Django settings/DB config)
load_dotenv()

# --- Timezone Definitions ---
PHILIPPINE_TZ = pytz.timezone('Asia/Manila')
# ----------------------------

# Define file paths for the model and scalers.
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_FILE = os.path.join(BASE_DIR, "rain_model.h5")
SCALER_X_FILE = os.path.join(BASE_DIR, "scaler_X.pkl")
SCALER_Y_FILE = os.path.join(BASE_DIR, "scaler_y.pkl")

# Define the number of time steps (sequence length) the model requires.
SEQUENCE_LENGTH = 6
PREDICTION_INTERVAL_SECONDS = 3600 
BARANGAY_RISK_DATA = {}

# =======================================================
# Database Function to fetch ALL Barangay Risk Data
# =======================================================
def get_all_barangay_risk_data_from_db():
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
        return {}


# =======================================================
# 1. Database Function (Sequence Data)
# =======================================================
def get_sequence_data_from_db():
    print(f"Fetching last {SEQUENCE_LENGTH} time steps of data from database...")
    try:
        with connection.cursor() as cursor:
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
            
            data = list(data)
            data.reverse() 
            
            sequence = []
            for temp, humid, wind, pressure, dt in data:
                hour_of_day = float(dt.hour)
                
                sequence.append([
                    float(temp), float(humid), float(wind), float(pressure), hour_of_day
                ])

            return sequence

    except Exception as e:
        print(f"Error reading database for sequence data: {e}")
        return None

# =======================================================
# 2. Model and Scalers Loading
# =======================================================
model = None
scaler_X = None
scaler_y = None
FEATURE_COUNT = 5

# --- Compatibility Fixes for TensorFlow Model Loading ---
class FixedInputLayer(tf.keras.layers.InputLayer):
    def __init__(self, **kwargs):
        if 'batch_shape' in kwargs: kwargs.pop('batch_shape')
        kwargs['input_shape'] = (SEQUENCE_LENGTH, FEATURE_COUNT)
        super(FixedInputLayer, self).__init__(**kwargs)

class DTypePolicy:
    def __init__(self, *args, **kwargs): pass
    @property
    def name(self): return 'float32'
    @property
    def compute_dtype(self): return tf.float32 
    @property
    def variable_dtype(self): return tf.float32 

try:
    custom_objects = {'InputLayer': FixedInputLayer, 'DTypePolicy': DTypePolicy}
    with tf.keras.utils.custom_object_scope(custom_objects):
        model = tf.keras.models.load_model(MODEL_FILE, compile=False)

    model.compile(optimizer="adam", loss="mean_squared_error")
    print("✅ Model loaded successfully.")
    
    scaler_X = joblib.load(SCALER_X_FILE)
    scaler_y = joblib.load(SCALER_Y_FILE)
    print("✅ Scalers loaded successfully.")

except FileNotFoundError as e:
    print(f"Warning: One of the required files was not found: {e.filename}")
except Exception as e:
    print(f"Warning: An unexpected error occurred during file loading: {e}")

# =======================================================
# 3. Helper and Prediction Functions
# =======================================================

# 🚨 UPDATED: This function now accepts the HOURLY RATE (mm/h) for classification.
def get_rain_intensity(rate_mm_h):
    """Classifies rainfall based on standard hourly rate (mm/h)."""
    if rate_mm_h <= 0.01: 
        return "None"
    elif 0.01 < rate_mm_h < 2.5: 
        return "Light"
    elif 2.5 <= rate_mm_h < 7.6: 
        return "Moderate"
    elif 7.6 <= rate_mm_h < 15: 
        return "Heavy"
    elif 15 <= rate_mm_h < 30: 
        return "Intense"
    else: 
        return "Torrential"

# 🚨 UPDATED: Calculates mm/h rate and uses it to get the intensity label.
def predict_rain(input_features):
    latest_data = input_features[-1]
    latest_temp, latest_humidity, _, _, _ = latest_data

    # --- Fallback Logic (same as before) ---
    if model is None or scaler_X is None or scaler_y is None:
        # Fallback will return TOTAL AMOUNT and DURATION. We need to calculate the rate here.
        if latest_humidity > 80 and latest_temp < 30:
            predicted_amount_mm, duration_min = 5.0, 30.0
        elif latest_humidity > 70:
            predicted_amount_mm, duration_min = 2.0, 15.0
        else:
            predicted_amount_mm, duration_min = 0.5, 5.0
        
        # Calculate rate for fallback intensity
        rate_mm_h = (predicted_amount_mm / duration_min) * 60 if duration_min > 0 else 0.0
        intensity = get_rain_intensity(rate_mm_h)
        
        # Return predicted amount, duration, and the rate-based intensity
        return predicted_amount_mm, duration_min, intensity, rate_mm_h
    
    # --- ML Model Prediction Logic ---
    try:
        input_scaled = scaler_X.transform(input_features)
    except ValueError as e:
        print(f"Error during scaling: {e}")
        return None, None, "Error", None

    X_seq = input_scaled.reshape(1, SEQUENCE_LENGTH, -1)
    y_pred_scaled = model.predict(X_seq, verbose=0)
    y_pred = scaler_y.inverse_transform(y_pred_scaled)
    
    # 1. Get the two numerical predictions (Total Amount and Duration)
    predicted_amount_mm = max(0, float(y_pred[0][0]))
    predicted_duration_minutes = max(0, float(y_pred[0][1]))
    
    # 2. Calculate the Rainfall Rate (mm/h)
    rainfall_rate_mm_h = 0.0
    if predicted_duration_minutes > 0.01: # Check > 0.01 to avoid division by near-zero duration
        # Rate (mm/minute) * 60 minutes/hour = Rate (mm/h)
        rainfall_rate_mm_h = (predicted_amount_mm / predicted_duration_minutes) * 60
    
    # 3. Classify Intensity based on the calculated RATE (mm/h)
    intensity_label = get_rain_intensity(rainfall_rate_mm_h)
    
    # Return all four values for use in the main loop
    return predicted_amount_mm, predicted_duration_minutes, intensity_label, rainfall_rate_mm_h


def assess_flood_risk_by_barangay(rain_rate_mm_h, duration, intensity_label):
    # This function uses the RATE (rain_rate_mm_h) for accurate risk assessment
    warnings = []
    
    for barangay, data in BARANGAY_RISK_DATA.items():
        land_type = data["land_type"]
        risk_multiplier = data["risk_multiplier"]
        land_description = data["description"]
        
        # Risk assessment now correctly compares the rate_mm_h against adjusted rate thresholds
        # Standard moderate rain starts at 2.5 mm/h
        adjusted_rain_threshold = 2.5 / risk_multiplier 
        adjusted_duration_threshold = 60 / risk_multiplier 
        
        # Check against rate and duration
        if rain_rate_mm_h >= adjusted_rain_threshold or (rain_rate_mm_h > 1.0 and duration > adjusted_duration_threshold):
            # Use the rate to check for severe intensity
            if intensity_label in ["Heavy", "Intense", "Torrential"] or rain_rate_mm_h >= 7.6:
                risk_level = "High"
                message = f"High flood risk in {barangay} due to predicted {intensity_label} rain ({rain_rate_mm_h:.1f}mm/h) over {duration:.0f} minutes. {land_description}."
            else:
                risk_level = "Moderate"
                message = f"Moderate flood risk in {barangay} due to predicted {intensity_label} rain ({rain_rate_mm_h:.1f}mm/h). {land_description}."
                
            warning = {
                "barangay": barangay, "land_type": land_type,
                "area": f"{barangay} ({land_type.replace('_', ' ').title()})",
                "risk_level": risk_level, "message": message,
                "rain_rate": rain_rate_mm_h, "duration": duration, "intensity": intensity_label
            }
            warnings.append(warning)
            
        elif rain_rate_mm_h > 1.0 and risk_multiplier > 1.0: 
            warning = {
                "barangay": barangay, "land_type": land_type,
                "area": f"{barangay} ({land_type.replace('_', ' ').title()})",
                "risk_level": "Low",
                "message": f"Low flood risk in {barangay}. Monitor conditions as {land_description}.",
                "rain_rate": rain_rate_mm_h, "duration": duration, "intensity": intensity_label
            }
            warnings.append(warning)
    
    risk_priority = {"High": 3, "Moderate": 2, "Low": 1}
    warnings.sort(key=lambda x: risk_priority.get(x["risk_level"], 0), reverse=True)
    
    return warnings

# =======================================================
# 4. Main Execution Block
# =======================================================
def main():
    print("\n--- Live Rainfall Prediction Service Started ---")
    
    try:
        # Initial Django setup
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        sys.path.append(project_root)
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weatheralert.settings')
        django.setup()
        
        get_all_barangay_risk_data_from_db()
        if not BARANGAY_RISK_DATA: return

    except Exception as e:
        print(f"Initial setup error: {e}")
        return

    # --- Start the Continuous Loop ---
    while True:
        try:
            now_pst = datetime.now(PHILIPPINE_TZ)
            
            print("\n==================================================")
            print(f"--- Running Prediction Cycle at {now_pst.strftime('%Y-%m-%d %H:%M:%S PST')} ---")
            print("==================================================")
            
            sequence_data_list = get_sequence_data_from_db()
            
            if sequence_data_list is None:
                print("Prediction cycle failed due to insufficient or missing weather data.")
            else:
                input_features_array = np.array(sequence_data_list, dtype=np.float32)

                latest_temp, latest_humidity, wind_speed, barometric_pressure, current_hour = input_features_array[-1]
                
                print("\nData collected from the database (latest entry):")
                print(f"Temperature: {latest_temp:.2f}°C, Humidity: {latest_humidity:.2f}%")
                print(f"Wind Speed: {wind_speed:.2f} m/s, Barometric Pressure: {barometric_pressure:.2f} hPa")
                print(f"Hour of Day: {int(current_hour)}")
                
                # 🚨 UPDATED: predict_rain now returns 4 values
                predicted_amount_mm, predicted_duration_minutes, intensity_label, rainfall_rate_mm_h = predict_rain(input_features_array)
                
                if predicted_amount_mm is None:
                    print("Prediction failed during ML model execution.")
                else:
                    print("\n--- Prediction Results ---")
                    # 🚨 UPDATED: Print both the predicted total accumulation and the calculated hourly rate
                    print(f"Predicted Total Rainfall: {predicted_amount_mm:.2f} mm")
                    print(f"Estimated Duration: {predicted_duration_minutes:.2f} minutes")
                    print(f"Calculated Rainfall Rate: {rainfall_rate_mm_h:.2f} mm/h")
                    print(f"Rainfall Intensity: {intensity_label}")

                    # ------------------------------------------------------------------
                    # --- Step 3: Insert Rain Prediction results in LOCAL TIME (PST) ---
                    # ------------------------------------------------------------------
                    try:
                        with connection.cursor() as cursor:
                            # Insert the calculated rate (mm/h) into the predicted_rain column
                            cursor.execute("""
                                INSERT INTO ai_predictions (predicted_rain, duration, intensity, created_at)
                                VALUES (%s, %s, %s, DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL 8 HOUR)) 
                            """, [rainfall_rate_mm_h, predicted_duration_minutes, intensity_label])
                        print("✅ Rain prediction results successfully inserted into the database.")
                        
                        with connection.cursor() as cursor:
                            cursor.execute("SELECT created_at FROM ai_predictions ORDER BY created_at DESC LIMIT 1")
                            db_timestamp_pst = cursor.fetchone()[0]
                            
                            print(f"🕒 Prediction Timestamp (PST): {db_timestamp_pst.strftime('%Y-%m-%d %H:%M:%S PST')}")
                            
                    except Exception as e:
                        print(f"❌ Error inserting or fetching prediction results: {e}")
                        
                    # ------------------------------------------------------------------
                    # --- Step 4 & 5: Assess Flood Risk, Insert Warnings, and Send SMS ---
                    # ------------------------------------------------------------------
                    # 🚨 UPDATED: Pass the calculated mm/h rate to the flood risk function
                    flood_warnings = assess_flood_risk_by_barangay(rainfall_rate_mm_h, predicted_duration_minutes, intensity_label)
                    
                    if flood_warnings:
                        print(f"\n--- FLOOD WARNINGS ISSUED FOR {len(flood_warnings)} BARANGAYS ---")
                        try:
                            with connection.cursor() as cursor:
                                cursor.execute("DELETE FROM flood_warnings WHERE prediction_date >= DATE_SUB(DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL 8 HOUR), INTERVAL 1 HOUR)")
                                
                                for warning in flood_warnings:
                                    print(f"🚨 {warning['risk_level']} Risk for {warning['barangay']} ({warning['land_type']}): {warning['message']}")
                                    
                                    cursor.execute("""
                                        INSERT INTO flood_warnings (area, risk_level, message, prediction_date)
                                        VALUES (%s, %s, %s, DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL 8 HOUR))
                                    """, [warning['area'], warning['risk_level'], warning['message']])
                                    
                                print(f"✅ {len(flood_warnings)} flood warnings successfully inserted into the database.")
                                
                        except Exception as e:
                            print(f"❌ Error processing or inserting flood warnings: {e}")
                    else:
                        print("\n✅ No flood warnings issued - all barangays are safe from flooding.")

            # --- PAUSE BEFORE THE NEXT RUN ---
            # 💡 FIX: Added 'flush=True' to prevent the repeating output issue you encountered.
            print(f"\nCycle complete. Waiting for {PREDICTION_INTERVAL_SECONDS/60:.0f} minutes...", flush=True) 
            time.sleep(PREDICTION_INTERVAL_SECONDS)

        except KeyboardInterrupt:
            print("\nPrediction loop stopped by user (Ctrl+C). Exiting.")
            break
        except Exception as e:
            print(f"An unexpected error occurred in the loop: {e}. Retrying in 60 seconds.")
            time.sleep(60)

if __name__ == "__main__":
    main()