import network
import urequests
import time
import dht
from machine import Pin

# WiFi credentials
ssid = "SIASICO"
password = "Waykokabalo0831"

# Onboard LED (usually GPIO 2 for ESP8266/ESP32)
led = Pin(2, Pin.OUT)

# Log to file + console
def log(message):
    print(message)
    try:
        with open('log.txt', 'a') as f:
            f.write(f"{time.localtime()} - {message}\n")
    except:
        pass

# Blink LED for status
def blink(times):
    for _ in range(times):
        led.off()
        time.sleep(0.2)
        led.on()
        time.sleep(0.2)

# Connect to WiFi
def connect_wifi():
    sta = network.WLAN(network.STA_IF)
    if not sta.active():
        sta.active(True)
    
    if not sta.isconnected():
        log("Connecting to WiFi...")
        sta.connect(ssid, password)
        
        max_wait = 10
        while max_wait > 0:
            if sta.isconnected():
                break
            max_wait -= 1
            log('Waiting for connection...')
            time.sleep(1)
    
    if not sta.isconnected():
        blink(5)  # Error signal
        raise OSError("Failed to connect to WiFi")
    
    log("WiFi connected. IP: " + sta.ifconfig()[0])
    blink(3)  # Connected signal
    return sta

# Main loop
try:
    sta = connect_wifi()
    
    sensor = dht.DHT11(Pin(4))
    url = "https://bccweather-629d88a334c9.herokuapp.com/api/data/"

    while True:
        try:
            sensor.measure()
            temp = sensor.temperature()
            hum = sensor.humidity()

            payload = {
                "temperature": temp,
                "humidity": hum,
                "sensor_id": "1"
            }

            log(f"Sending data: {payload}")
            response = urequests.post(url, json=payload)
            log("Server response: " + response.text)
            response.close()

            blink(1)  # short blink for each successful send

        except Exception as e:
            log("Error: " + str(e))
            blink(5)  # error blink
            if not sta.isconnected():
                log("WiFi disconnected, reconnecting...")
                sta = connect_wifi()

        time.sleep(600)  # wait 10 minutes

except OSError as e:
    log("Fatal error: " + str(e))
    blink(5)
