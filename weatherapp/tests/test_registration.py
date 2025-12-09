"""
Unit tests for user registration functionality.
"""
import json
from django.test import TestCase, Client
from django.db import connection
from django.core.cache import cache
from django.test import override_settings
from unittest.mock import patch, MagicMock

from weatherapp.views import register_user, check_username, check_email, check_phone

TEST_CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'test-cache',
        'TIMEOUT': None,
    }
}


@override_settings(CACHES=TEST_CACHES)
class RegistrationTests(TestCase):
    """Test user registration views."""

    def setUp(self):
        """Set up test data."""
        self.client = Client()
        cache.clear()

    def tearDown(self):
        """Clean up test data."""
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM user WHERE username LIKE 'test_%'")

    def test_registration_success(self):
        """Test successful user registration."""
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'john.doe@test.com',
            'regPhone': '09123456789',
            'regUsername': 'test_john',
            'regPassword': 'TestPass123!',
            'confirm_Password': 'TestPass123!',
            'province': 'NEGROS OCCIDENTAL',
            'city': 'BAGO',
            'barangay': 'TEST',
        })
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['success'])
        
        # Verify user was created
        with connection.cursor() as cursor:
            cursor.execute("SELECT username FROM user WHERE username = 'test_john'")
            self.assertIsNotNone(cursor.fetchone())

    def test_registration_duplicate_username(self):
        """Test registration with duplicate username."""
        # Create first user
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, ['Existing User', 'Address', 'existing@test.com', '09123456788', 'test_existing', make_password('Pass123!')])
        
        # Try to register with same username
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'john.doe@test.com',
            'regPhone': '09123456789',
            'regUsername': 'test_existing',
            'regPassword': 'TestPass123!',
            'confirm_Password': 'TestPass123!',
        })
        
        data = json.loads(response.content)
        self.assertFalse(data['success'])
        self.assertIn('regUsername', data['errors'])

    def test_registration_duplicate_email(self):
        """Test registration with duplicate email."""
        # Create first user
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, ['Existing User', 'Address', 'existing@test.com', '09123456788', 'test_existing2', make_password('Pass123!')])
        
        # Try to register with same email
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'existing@test.com',
            'regPhone': '09123456789',
            'regUsername': 'test_john2',
            'regPassword': 'TestPass123!',
            'confirm_Password': 'TestPass123!',
        })
        
        data = json.loads(response.content)
        self.assertFalse(data['success'])
        self.assertIn('regEmail', data['errors'])

    def test_registration_weak_password(self):
        """Test registration with weak password."""
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'john.doe@test.com',
            'regPhone': '09123456789',
            'regUsername': 'test_john3',
            'regPassword': 'weak',
            'confirm_Password': 'weak',
        })
        
        data = json.loads(response.content)
        self.assertFalse(data['success'])
        self.assertIn('regPassword', data['errors'])

    def test_registration_password_mismatch(self):
        """Test registration with mismatched passwords."""
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'john.doe@test.com',
            'regPhone': '09123456789',
            'regUsername': 'test_john4',
            'regPassword': 'TestPass123!',
            'confirm_Password': 'DifferentPass123!',
        })
        
        data = json.loads(response.content)
        self.assertFalse(data['success'])
        self.assertIn('confirm_Password', data['errors'])

    def test_registration_invalid_email(self):
        """Test registration with invalid email format."""
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'invalid-email',
            'regPhone': '09123456789',
            'regUsername': 'test_john5',
            'regPassword': 'TestPass123!',
            'confirm_Password': 'TestPass123!',
        })
        
        data = json.loads(response.content)
        self.assertFalse(data['success'])
        self.assertIn('regEmail', data['errors'])

    def test_registration_invalid_phone(self):
        """Test registration with invalid phone number."""
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'john.doe@test.com',
            'regPhone': '123',  # Too short
            'regUsername': 'test_john6',
            'regPassword': 'TestPass123!',
            'confirm_Password': 'TestPass123!',
        })
        
        data = json.loads(response.content)
        self.assertFalse(data['success'])
        self.assertIn('regPhone', data['errors'])

    def test_check_username_exists(self):
        """Test checking if username exists."""
        # Create a user
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, ['Test User', 'Address', 'test@test.com', '09123456789', 'test_check', make_password('Pass123!')])
        
        response = self.client.get('/check-username/', {'username': 'test_check'})
        data = json.loads(response.content)
        self.assertTrue(data['exists'])

    def test_check_username_not_exists(self):
        """Test checking if username doesn't exist."""
        response = self.client.get('/check-username/', {'username': 'nonexistent_user'})
        data = json.loads(response.content)
        self.assertFalse(data['exists'])

    def test_check_email_exists(self):
        """Test checking if email exists."""
        # Create a user
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, ['Test User', 'Address', 'testemail@test.com', '09123456789', 'test_check2', make_password('Pass123!')])
        
        response = self.client.get('/check-email/', {'email': 'testemail@test.com'})
        data = json.loads(response.content)
        self.assertTrue(data['exists'])

    def test_check_phone_exists(self):
        """Test checking if phone exists."""
        # Create a user
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, ['Test User', 'Address', 'test@test.com', '09123456790', 'test_check3', make_password('Pass123!')])
        
        response = self.client.get('/check-phone/', {'phone_num': '09123456790'})
        data = json.loads(response.content)
        self.assertTrue(data['exists'])

    @patch('weatherapp.views.settings.PSA_ED25519_PUBLIC_KEY', None)
    def test_registration_without_qr_data(self):
        """Test registration without QR code data."""
        response = self.client.post('/register/', {
            'firstName': 'John',
            'lastName': 'Doe',
            'regEmail': 'john.doe@test.com',
            'regPhone': '09123456789',
            'regUsername': 'test_john_noqr',
            'regPassword': 'TestPass123!',
            'confirm_Password': 'TestPass123!',
        })
        
        data = json.loads(response.content)
        self.assertFalse(data['success'])
        self.assertIn('qr_data', data['errors'])

