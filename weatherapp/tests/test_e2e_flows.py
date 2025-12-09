"""
End-to-end tests for critical user flows.
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
class E2EUserFlowTests(TestCase):
    """End-to-end tests for critical user flows."""

    def setUp(self):
        """Set up test data."""
        self.client = Client()
        cache.clear()

    def tearDown(self):
        """Clean up test data."""
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM user WHERE username LIKE 'e2e_%'")
            cursor.execute("DELETE FROM admin WHERE username LIKE 'e2e_%'")

    def test_complete_registration_and_login_flow(self):
        """Test complete flow: registration -> login -> dashboard access."""
        # Step 1: Register a new user
        response = self.client.post('/register/', {
            'firstName': 'E2E',
            'lastName': 'Test',
            'regEmail': 'e2e@test.com',
            'regPhone': '09123456789',
            'regUsername': 'e2e_user',
            'regPassword': 'E2ETest123!',
            'confirm_Password': 'E2ETest123!',
            'province': 'NEGROS OCCIDENTAL',
            'city': 'BAGO',
            'barangay': 'TEST',
        })
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['success'])
        
        # Step 2: Login with the new user
        response = self.client.post('/login/', {
            'username': 'e2e_user',
            'password': 'E2ETest123!',
        })
        
        self.assertEqual(response.status_code, 302)  # Redirect to dashboard
        self.assertIn('user_id', self.client.session)
        
        # Step 3: Access user dashboard
        response = self.client.get('/user-dashboard/')
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'E2E Test')  # User name should appear

    def test_password_reset_flow(self):
        """Test complete password reset flow."""
        # Create a user first
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Reset Test',
                'Address',
                'reset@test.com',
                '09123456789',
                'e2e_reset',
                make_password('OldPass123!')
            ])
        
        # Step 1: Request password reset
        response = self.client.post('/forgot-password/', {
            'email': 'reset@test.com'
        })
        
        # Should redirect to OTP verification
        self.assertEqual(response.status_code, 302)
        self.assertIn('otp', self.client.session)
        
        # Step 2: Verify OTP (using session OTP)
        otp = self.client.session.get('otp')
        response = self.client.post('/verify-otp/', {
            'otp': str(otp)
        })
        
        self.assertEqual(response.status_code, 302)  # Redirect to reset password
        
        # Step 3: Reset password
        response = self.client.post('/reset-password/', {
            'new_password': 'NewPass123!',
            'confirm_password': 'NewPass123!'
        })
        
        self.assertEqual(response.status_code, 302)  # Redirect to home
        
        # Step 4: Login with new password
        response = self.client.post('/login/', {
            'username': 'e2e_reset',
            'password': 'NewPass123!',
        })
        
        self.assertEqual(response.status_code, 302)
        self.assertIn('user_id', self.client.session)

    def test_admin_management_flow(self):
        """Test admin creating and managing another admin."""
        # Create admin and login
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO admin (name, email, phone_num, username, password, status)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'E2E Admin',
                'admin@test.com',
                '09123456789',
                'e2e_admin',
                make_password('AdminPass123!'),
                'Active'
            ])
        
        # Login as admin
        self.client.post('/login/', {
            'username': 'e2e_admin',
            'password': 'AdminPass123!',
        })
        
        # Access admin dashboard
        response = self.client.get('/admin-dashboard/')
        self.assertEqual(response.status_code, 200)
        
        # Create a new admin
        response = self.client.post('/add-admin/', {
            'name': 'New Admin',
            'email': 'newadmin@test.com',
            'phone_num': '09123456788',
            'username': 'e2e_newadmin',
            'password': 'NewAdmin123!',
            'confirm_password': 'NewAdmin123!'
        })
        
        self.assertEqual(response.status_code, 302)  # Redirect
        
        # Verify new admin was created
        with connection.cursor() as cursor:
            cursor.execute("SELECT username FROM admin WHERE username = %s", ['e2e_newadmin'])
            self.assertIsNotNone(cursor.fetchone())

    def test_sensor_data_collection_flow(self):
        """Test complete flow: sensor sends data -> data appears in dashboard."""
        # Create sensor
        sensor_id = None
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO sensor (name, latitude, longitude, radius)
                VALUES (%s, %s, %s, %s)
            """, ['E2E Sensor', 10.0, 122.0, 5.0])
            
            cursor.execute("SELECT sensor_id FROM sensor WHERE name = %s", ['E2E Sensor'])
            sensor_id = cursor.fetchone()[0]
        
        # Sensor sends data
        response = self.client.post(
            '/api/data/',
            data=json.dumps({
                'sensor_id': sensor_id,
                'temperature': 28.5,
                'humidity': 75.0,
                'wind_speed': 8.0,
                'barometric_pressure': 1015.0,
                'altitude_m': 15.0,
                'rainfall_mm': 2.5,
                'rain_tip_count': 5
            }),
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 201)
        
        # Create user and login
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Sensor User',
                'Address',
                'sensor@test.com',
                '09123456789',
                'e2e_sensor',
                make_password('Pass123!')
            ])
        
        self.client.post('/login/', {
            'username': 'e2e_sensor',
            'password': 'Pass123!',
        })
        
        # Check dashboard shows the data
        response = self.client.get('/api/dashboard-data/')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertIn('weather', data)
        
        # Cleanup
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM weather_reports WHERE sensor_id = %s", [sensor_id])
            cursor.execute("DELETE FROM sensor WHERE sensor_id = %s", [sensor_id])

    def test_logout_flow(self):
        """Test complete logout flow."""
        # Create and login user
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Logout Test',
                'Address',
                'logout@test.com',
                '09123456789',
                'e2e_logout',
                make_password('Pass123!')
            ])
        
        self.client.post('/login/', {
            'username': 'e2e_logout',
            'password': 'Pass123!',
        })
        
        # Verify logged in
        self.assertIn('user_id', self.client.session)
        
        # Logout
        response = self.client.post('/logout/')
        self.assertEqual(response.status_code, 302)  # Redirect to home
        
        # Verify logged out
        self.assertNotIn('user_id', self.client.session)
        self.assertIn('form_logoutSuccess', self.client.session)
        
        # Try to access protected page
        response = self.client.get('/user-dashboard/')
        self.assertEqual(response.status_code, 302)  # Should redirect to login

