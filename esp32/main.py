import network
import urequests
import time
import dht
import ujson
from machine import Pin

ssid = "Genesis"
password = "@bccbsis2024"

# Setup rain gauge input pin and counter with debounce
RAIN_PIN_NUM = 5
rain_tip_count = 0
last_tip_time = 0

def rain_tip_handler(pin):
    global rain_tip_count, last_tip_time
    current_time = time.ticks_ms()
    if time.ticks_diff(current_time, last_tip_time) > 200:  # debounce 200 ms
        rain_tip_count += 1
        last_tip_time = current_time

def connect_wifi():
    sta = network.WLAN(network.STA_IF)
    if not sta.active():
        sta.active(True)
    
    if not sta.isconnected():
        print("Connecting to WiFi...")
        sta.connect(ssid, password)
        
        max_wait = 10
        while max_wait > 0:
            if sta.isconnected():
                break
            max_wait -= 1
            print('waiting...')
            time.sleep(1)
    
    if not sta.isconnected():
        raise OSError("Failed to connect to WiFi")
    
    print("WiFi connected. IP:", sta.ifconfig()[0])
    return sta

# Main loop with persistent WiFi retry
while True:
    try:
        sta = connect_wifi()
        
        sensor = dht.DHT11(Pin(4))  # D4 pin
        rain_pin = Pin(RAIN_PIN_NUM, Pin.IN, Pin.PULL_UP)
        rain_pin.irq(trigger=Pin.IRQ_FALLING, handler=rain_tip_handler)
        
        url = "https://bccweather-629d88a334c9.herokuapp.com/api/data/"

        while True:
            try:
                # Try to measure temperature and humidity twice if needed
                for attempt in range(2):
                    try:
                        sensor.measure()
                        temp = sensor.temperature()
                        hum = sensor.humidity()
                        break
                    except Exception as e:
                        print(f"Sensor read attempt {attempt + 1} failed:", e)
                        time.sleep(1)
                else:
                    # If both attempts fail, skip this cycle
                    print("Failed to read sensor after 2 attempts, skipping this cycle")
                    time.sleep(600)
                    continue

                # Safely read and reset rain tip count
                tips = rain_tip_count
                rain_tip_count = 0

                rainfall_mm = tips * 0.3

                payload = {
                    "temperature": temp,
                    "humidity": hum,
                    "rainfall_mm": rainfall_mm,
                    "rain_tip_count": tips,
                    "sensor_id": 1
                }

                headers = {"Content-Type": "application/json"}
                response = urequests.post(url, data=ujson.dumps(payload), headers=headers)
                print("Server response:", response.text)
                response.close()

            except Exception as e:
                print("Error during sensor reading or HTTP request:", e)
                if not sta.isconnected():
                    print("WiFi disconnected, attempting to reconnect...")
                    break  # break inner loop to reconnect WiFi

            time.sleep(600)  # 10 minutes

    except OSError as e:
        print("Fatal error:", e)
        print("Retrying WiFi connection in 5 seconds...")
        time.sleep(5)

