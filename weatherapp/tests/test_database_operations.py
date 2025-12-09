"""
Integration tests for database operations.
"""
from django.test import TestCase, override_settings
from django.db import connection, IntegrityError
from django.contrib.auth.hashers import make_password, check_password

TEST_CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'test-cache',
        'TIMEOUT': None,
    }
}


@override_settings(CACHES=TEST_CACHES)
class DatabaseOperationsTests(TestCase):
    """Test database operations and integrity."""

    def setUp(self):
        """Set up test data."""
        pass

    def tearDown(self):
        """Clean up test data."""
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM user WHERE username LIKE 'test_%'")
            cursor.execute("DELETE FROM admin WHERE username LIKE 'test_%'")
            cursor.execute("DELETE FROM sensor WHERE name LIKE 'Test%'")

    def test_user_insert_and_retrieve(self):
        """Test inserting and retrieving a user."""
        with connection.cursor() as cursor:
            # Insert user
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Test User',
                'Test Address',
                'test@test.com',
                '09123456789',
                'test_db_user',
                make_password('TestPass123!')
            ])
            
            # Retrieve user
            cursor.execute("SELECT name, email, username FROM user WHERE username = %s", ['test_db_user'])
            row = cursor.fetchone()
            
            self.assertIsNotNone(row)
            self.assertEqual(row[0], 'Test User')
            self.assertEqual(row[1], 'test@test.com')
            self.assertEqual(row[2], 'test_db_user')

    def test_user_password_hashing(self):
        """Test that passwords are properly hashed."""
        password = 'TestPass123!'
        hashed = make_password(password)
        
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Test User',
                'Test Address',
                'test2@test.com',
                '09123456788',
                'test_db_user2',
                hashed
            ])
            
            cursor.execute("SELECT password FROM user WHERE username = %s", ['test_db_user2'])
            stored_hash = cursor.fetchone()[0]
            
            self.assertTrue(check_password(password, stored_hash))
            self.assertNotEqual(password, stored_hash)

    def test_unique_username_constraint(self):
        """Test that username uniqueness is enforced."""
        with connection.cursor() as cursor:
            # Insert first user
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Test User 1',
                'Address 1',
                'test1@test.com',
                '09123456789',
                'test_unique',
                make_password('Pass123!')
            ])
            
            # Try to insert duplicate username
            with self.assertRaises(Exception):  # IntegrityError or similar
                cursor.execute("""
                    INSERT INTO user (name, address, email, phone_num, username, password)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, [
                    'Test User 2',
                    'Address 2',
                    'test2@test.com',
                    '09123456788',
                    'test_unique',  # Duplicate username
                    make_password('Pass123!')
                ])

    def test_unique_email_constraint(self):
        """Test that email uniqueness is enforced."""
        with connection.cursor() as cursor:
            # Insert first user
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Test User 1',
                'Address 1',
                'duplicate@test.com',
                '09123456789',
                'test_unique1',
                make_password('Pass123!')
            ])
            
            # Try to insert duplicate email
            with self.assertRaises(Exception):
                cursor.execute("""
                    INSERT INTO user (name, address, email, phone_num, username, password)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, [
                    'Test User 2',
                    'Address 2',
                    'duplicate@test.com',  # Duplicate email
                    '09123456788',
                    'test_unique2',
                    make_password('Pass123!')
                ])

    def test_sensor_insert_and_retrieve(self):
        """Test inserting and retrieving a sensor."""
        with connection.cursor() as cursor:
            # Insert sensor
            cursor.execute("""
                INSERT INTO sensor (name, latitude, longitude, radius)
                VALUES (%s, %s, %s, %s)
            """, [
                'Test Sensor',
                10.1234,
                122.5678,
                5.0
            ])
            
            # Retrieve sensor
            cursor.execute("SELECT name, latitude, longitude, radius FROM sensor WHERE name = %s", ['Test Sensor'])
            row = cursor.fetchone()
            
            self.assertIsNotNone(row)
            self.assertEqual(row[0], 'Test Sensor')
            self.assertEqual(float(row[1]), 10.1234)
            self.assertEqual(float(row[2]), 122.5678)
            self.assertEqual(float(row[3]), 5.0)

    def test_weather_report_insert(self):
        """Test inserting a weather report."""
        # First create a sensor
        sensor_id = None
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO sensor (name, latitude, longitude, radius)
                VALUES (%s, %s, %s, %s)
            """, ['Test Sensor Report', 10.0, 122.0, 5.0])
            
            cursor.execute("SELECT sensor_id FROM sensor WHERE name = %s", ['Test Sensor Report'])
            sensor_id = cursor.fetchone()[0]
        
        # Get intensity_id
        intensity_id = None
        with connection.cursor() as cursor:
            cursor.execute("SELECT intensity_id FROM intensity WHERE intensity = %s", ['Light'])
            result = cursor.fetchone()
            if result:
                intensity_id = result[0]
            else:
                # Create one if it doesn't exist
                cursor.execute("INSERT INTO intensity (intensity) VALUES (%s)", ['Light'])
                intensity_id = cursor.lastrowid
        
        # Insert weather report
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO weather_reports (
                    sensor_id, intensity_id, temperature, humidity,
                    wind_speed, barometric_pressure, altitude,
                    dew_point, date_time, rain_rate, rain_accumulated
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s)
            """, [
                sensor_id,
                intensity_id,
                25.5,
                70.0,
                5.0,
                1013.25,
                10.0,
                20.0,
                0.0,
                0.0
            ])
            
            # Verify insertion
            cursor.execute("""
                SELECT temperature, humidity FROM weather_reports
                WHERE sensor_id = %s ORDER BY date_time DESC LIMIT 1
            """, [sensor_id])
            
            row = cursor.fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(float(row[0]), 25.5)
            self.assertEqual(float(row[1]), 70.0)

    def test_transaction_rollback(self):
        """Test that transactions can be rolled back."""
        with connection.cursor() as cursor:
            # Start transaction
            cursor.execute("START TRANSACTION")
            
            try:
                cursor.execute("""
                    INSERT INTO user (name, address, email, phone_num, username, password)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, [
                    'Rollback Test',
                    'Address',
                    'rollback@test.com',
                    '09123456789',
                    'test_rollback',
                    make_password('Pass123!')
                ])
                
                # Rollback
                cursor.execute("ROLLBACK")
                
                # Verify user was not inserted
                cursor.execute("SELECT username FROM user WHERE username = %s", ['test_rollback'])
                self.assertIsNone(cursor.fetchone())
            except Exception:
                cursor.execute("ROLLBACK")
                raise

