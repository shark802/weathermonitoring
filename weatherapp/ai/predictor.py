import os
import logging
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0' 
import tensorflow as tf
import time
import sys
import django
from django.conf import settings
from django.db import connection # Import the connection object
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
logger = logging.getLogger(__name__)

# =======================================================
# Database Function to fetch ALL Barangay Risk Data
# NOTE: This only runs once during startup, so a single open/close is fine.
# =======================================================
def get_all_barangay_risk_data_from_db():
    global BARANGAY_RISK_DATA
    logger.info("Fetching barangay risk data from bago_city_barangay_risk table")
    try:
        # Use connection.cursor() for a fresh cursor inside a block
        with connection.cursor() as cursor:
            query = """
            SELECT barangay_name, land_description, flood_risk_multiplier, flood_risk_summary
            FROM bago_city_barangay_risk
            """
            cursor.execute(query)
            data = cursor.fetchall()
            
            if not data:
                logger.warning("No risk data found in the database. Using fallback values.")
                return {}

            for name, land_type, multiplier, description in data:
                BARANGAY_RISK_DATA[name] = {
                    "land_type": land_type,
                    "risk_multiplier": float(multiplier),
                    "description": description
                }
            logger.info("Loaded risk data for %s barangays", len(BARANGAY_RISK_DATA))
            return BARANGAY_RISK_DATA

    except Exception as e:
        logger.exception("Error reading database for barangay risk data")
        return {}


# =======================================================
# 1. Database Function (Sequence Data)
# =======================================================
def get_sequence_data_from_db():
    logger.info("Fetching last %s time steps of data from database", SEQUENCE_LENGTH)
    try:
        # Use connection.cursor() ensures the block is atomic/safe
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
                logger.error(
                    "Insufficient sequence data returned (%s of %s required)",
                    0 if not data else len(data),
                    SEQUENCE_LENGTH,
                )
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
        logger.exception("Error reading database for sequence data")
        # When an error occurs, it's safer to discard the connection
        if hasattr(connection, 'close'): connection.close()
        return None

# =======================================================
# 2. Model and Scalers Loading (REMAINS THE SAME)
# =======================================================
model = None
scaler_X = None
scaler_y = None
FEATURE_COUNT = 5

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
    logger.info("Rain model loaded successfully")
    
    scaler_X = joblib.load(SCALER_X_FILE)
    scaler_y = joblib.load(SCALER_Y_FILE)
    logger.info("Scalers loaded successfully")

except FileNotFoundError as e:
    logger.warning("One of the required files was not found: %s", e.filename)
except Exception as e:
    logger.exception("Unexpected error during model/scaler loading")

# =======================================================
# 3. Helper and Prediction Functions (REMAINS THE SAME)
# =======================================================

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

def predict_rain(input_features):
    latest_data = input_features[-1]
    latest_temp, latest_humidity, _, _, _ = latest_data

    # --- Fallback Logic ---
    if model is None or scaler_X is None or scaler_y is None:
        if latest_humidity > 80 and latest_temp < 30:
            predicted_amount_mm, duration_min = 5.0, 30.0
        elif latest_humidity > 70:
            predicted_amount_mm, duration_min = 2.0, 15.0
        else:
            predicted_amount_mm, duration_min = 0.5, 5.0
        
        rate_mm_h = (predicted_amount_mm / duration_min) * 60 if duration_min > 0 else 0.0
        intensity = get_rain_intensity(rate_mm_h)
        
        return predicted_amount_mm, duration_min, intensity, rate_mm_h
    
    # --- ML Model Prediction Logic ---
    try:
        input_scaled = scaler_X.transform(input_features)
    except ValueError as e:
        logger.exception("Error during feature scaling")
        return None, None, "Error", None

    X_seq = input_scaled.reshape(1, SEQUENCE_LENGTH, -1)
    y_pred_scaled = model.predict(X_seq, verbose=0)
    y_pred = scaler_y.inverse_transform(y_pred_scaled)
    
    predicted_amount_mm = max(0, float(y_pred[0][0]))
    predicted_duration_minutes = max(0, float(y_pred[0][1]))
    
    rainfall_rate_mm_h = 0.0
    if predicted_duration_minutes > 0.01: 
        rainfall_rate_mm_h = (predicted_amount_mm / predicted_duration_minutes) * 60
    
    intensity_label = get_rain_intensity(rainfall_rate_mm_h)
    
    return predicted_amount_mm, predicted_duration_minutes, intensity_label, rainfall_rate_mm_h


def assess_flood_risk_by_barangay(rain_rate_mm_h, duration, intensity_label):
    warnings = []
    
    for barangay, data in BARANGAY_RISK_DATA.items():
        land_type = data["land_type"]
        risk_multiplier = data["risk_multiplier"]
        land_description = data["description"]
        
        adjusted_rain_threshold = 2.5 / risk_multiplier 
        adjusted_duration_threshold = 60 / risk_multiplier 
        
        if rain_rate_mm_h >= adjusted_rain_threshold or (rain_rate_mm_h > 1.0 and duration > adjusted_duration_threshold):
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

# --- NEW FUNCTION: The core logic that runs per cycle and manages the connection ---
def run_prediction_cycle():
    now_pst = datetime.now(PHILIPPINE_TZ)
    
    logger.info("Running prediction cycle at %s PST", now_pst.strftime('%Y-%m-%d %H:%M:%S'))
    
    try:
        # Step 1: Fetch Data (uses connection.cursor() internally)
        sequence_data_list = get_sequence_data_from_db()
        
        if sequence_data_list is None:
            logger.warning("Prediction cycle aborted due to insufficient weather data")
            return

        input_features_array = np.array(sequence_data_list, dtype=np.float32)

        latest_temp, latest_humidity, wind_speed, barometric_pressure, current_hour = input_features_array[-1]
        
        logger.debug(
            "Latest weather entry temp=%.2f°C humidity=%.2f%% wind=%.2f m/s pressure=%.2f hPa hour=%s",
            latest_temp,
            latest_humidity,
            wind_speed,
            barometric_pressure,
            int(current_hour),
        )
        
        # Step 2: Run Prediction
        predicted_amount_mm, predicted_duration_minutes, intensity_label, rainfall_rate_mm_h = predict_rain(input_features_array)
        
        if predicted_amount_mm is None:
            logger.error("Prediction failed during ML model execution")
            return

        logger.info(
            "Prediction results rainfall=%.2f mm duration=%.2f min rate=%.2f mm/h intensity=%s",
            predicted_amount_mm,
            predicted_duration_minutes,
            rainfall_rate_mm_h,
            intensity_label,
        )

        # Step 3: Insert Rain Prediction results
        try:
            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO ai_predictions (predicted_rain, duration, intensity, created_at)
                    VALUES (%s, %s, %s, DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL 8 HOUR)) 
                """, [rainfall_rate_mm_h, predicted_duration_minutes, intensity_label])
            logger.info("Rain prediction results inserted into the database")
            
            with connection.cursor() as cursor:
                cursor.execute("SELECT created_at FROM ai_predictions ORDER BY created_at DESC LIMIT 1")
                db_timestamp_pst = cursor.fetchone()[0]
                
                logger.debug("Prediction timestamp (PST): %s", db_timestamp_pst.strftime('%Y-%m-%d %H:%M:%S PST'))
                
        except Exception as e:
            logger.exception("Error inserting or fetching prediction results")
            if hasattr(connection, 'close'): connection.close()
            return
            
        # Step 4: Assess Flood Risk
        flood_warnings = assess_flood_risk_by_barangay(rainfall_rate_mm_h, predicted_duration_minutes, intensity_label)
        
        # Step 5: Insert Flood Warnings
        if flood_warnings:
            logger.warning("Flood warnings issued for %s barangays", len(flood_warnings))
            try:
                with connection.cursor() as cursor:
                    # Clear old warnings (optional, but good practice if not done elsewhere)
                    cursor.execute("DELETE FROM flood_warnings WHERE prediction_date >= DATE_SUB(DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL 8 HOUR), INTERVAL 1 HOUR)")
                    
                    for warning in flood_warnings:
                        logger.warning(
                            "Flood warning %s risk for %s (%s): %s",
                            warning['risk_level'],
                            warning['barangay'],
                            warning['land_type'],
                            warning['message'],
                        )
                        
                        cursor.execute("""
                            INSERT INTO flood_warnings (area, risk_level, message, prediction_date)
                            VALUES (%s, %s, %s, DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL 8 HOUR))
                        """, [warning['area'], warning['risk_level'], warning['message']])
                        
                    logger.info("%s flood warnings inserted into the database", len(flood_warnings))
                    
            except Exception as e:
                logger.exception("Error processing or inserting flood warnings")
                if hasattr(connection, 'close'): connection.close()
                return
        else:
            logger.info("No flood warnings issued for this cycle")

    except Exception as e:
        # Catch any unexpected errors during the cycle
        logger.exception("Unexpected error during prediction cycle")
        if hasattr(connection, 'close'): connection.close()
    finally:
        # CRITICAL FIX: Explicitly close the persistent Django connection
        # This forces a fresh connection on the next cycle, preventing 'Server has gone away'
        if hasattr(connection, 'close'):
            connection.close()


def main():
    logger.info("Live Rainfall Prediction Service started")
    
    try:
        # Initial Django setup
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        sys.path.append(project_root)
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weatheralert.settings')
        django.setup()
        
        # Load risk data once at startup
        get_all_barangay_risk_data_from_db()
        if not BARANGAY_RISK_DATA: return

    except Exception as e:
        logger.exception("Initial setup error for prediction service")
        return

    # --- Start the Continuous Loop ---
    while True:
        try:
            # The function now contains the logic and the critical connection management
            run_prediction_cycle()

            # --- PAUSE BEFORE THE NEXT RUN ---
            logger.info("Cycle complete. Waiting for %s minutes", PREDICTION_INTERVAL_SECONDS/60)
            time.sleep(PREDICTION_INTERVAL_SECONDS)

        except KeyboardInterrupt:
            logger.info("Prediction loop stopped by user")
            break
        except Exception as e:
            logger.exception("Unexpected error in prediction loop. Retrying in 60 seconds")
            time.sleep(60)

if __name__ == "__main__":
    main()