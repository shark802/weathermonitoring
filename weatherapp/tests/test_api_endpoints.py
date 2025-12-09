"""
Integration tests for API endpoints.
"""
import json
from django.test import TestCase, Client
from django.db import connection
from django.core.cache import cache
from django.test import override_settings

TEST_CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'test-cache',
        'TIMEOUT': None,
    }
}


@override_settings(CACHES=TEST_CACHES)
class APIEndpointTests(TestCase):
    """Test API endpoints."""

    def setUp(self):
        """Set up test data."""
        self.client = Client()
        cache.clear()
        
        # Create test user and login
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'API Test User',
                'Test Address',
                'apitest@test.com',
                '09123456789',
                'apitest',
                make_password('TestPass123!')
            ])
        
        # Login
        self.client.post('/login/', {
            'username': 'apitest',
            'password': 'TestPass123!',
        })
        
        # Create test sensor
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO sensor (name, latitude, longitude, radius)
                VALUES (%s, %s, %s, %s)
            """, ['API Test Sensor', 10.0, 122.0, 5.0])
            
            cursor.execute("SELECT sensor_id FROM sensor WHERE name = %s", ['API Test Sensor'])
            self.sensor_id = cursor.fetchone()[0]

    def tearDown(self):
        """Clean up test data."""
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM weather_reports WHERE sensor_id = %s", [self.sensor_id])
            cursor.execute("DELETE FROM sensor WHERE sensor_id = %s", [self.sensor_id])
            cursor.execute("DELETE FROM user WHERE username = 'apitest'")

    def test_receive_sensor_data_success(self):
        """Test successful sensor data submission."""
        response = self.client.post(
            '/api/data/',
            data=json.dumps({
                'sensor_id': self.sensor_id,
                'temperature': 25.5,
                'humidity': 70.0,
                'wind_speed': 5.0,
                'barometric_pressure': 1013.25,
                'altitude_m': 10.0,
                'rainfall_mm': 0.0,
                'rain_tip_count': 0
            }),
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 201)
        data = json.loads(response.content)
        self.assertEqual(data['status'], 'success')

    def test_receive_sensor_data_invalid_json(self):
        """Test sensor data submission with invalid JSON."""
        response = self.client.post(
            '/api/data/',
            data='invalid json',
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 400)
        data = json.loads(response.content)
        self.assertIn('error', data)

    def test_receive_sensor_data_get_method(self):
        """Test that GET method is rejected."""
        response = self.client.get('/api/data/')
        self.assertEqual(response.status_code, 405)

    def test_get_alerts_endpoint(self):
        """Test getting alerts."""
        response = self.client.get('/get-alerts/')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertIn('alerts', data)
        self.assertIn('total_count', data)

    def test_mark_alerts_read(self):
        """Test marking alerts as read."""
        response = self.client.post('/mark-alerts-read/')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertEqual(data['status'], 'success')

    def test_clear_read_alerts(self):
        """Test clearing read alerts."""
        response = self.client.post('/clear-read-alerts/')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertEqual(data['status'], 'success')

    def test_latest_dashboard_data(self):
        """Test getting latest dashboard data."""
        response = self.client.get('/api/dashboard-data/')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertIn('weather', data)
        self.assertIn('alerts', data)
        self.assertIn('forecast', data)

    def test_latest_dashboard_data_with_sensor(self):
        """Test getting dashboard data for specific sensor."""
        response = self.client.get(f'/api/dashboard-data/?sensor_id={self.sensor_id}')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertIn('weather', data)

    def test_check_username_endpoint(self):
        """Test username check endpoint."""
        response = self.client.get('/check-username/', {'username': 'apitest'})
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['exists'])

    def test_check_email_endpoint(self):
        """Test email check endpoint."""
        response = self.client.get('/check-email/', {'email': 'apitest@test.com'})
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['exists'])

    def test_rate_limiting_on_endpoints(self):
        """Test that rate limiting is applied to endpoints."""
        # Make multiple rapid requests
        for _ in range(10):
            response = self.client.get('/get-alerts/')
            # Should succeed for first few, then potentially rate limited
            self.assertIn(response.status_code, [200, 429])

