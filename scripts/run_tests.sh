#!/bin/bash
# Run all tests with coverage
# Usage: ./scripts/run_tests.sh

set -e

echo "🧪 Running test suite with coverage..."

# Run tests with coverage
coverage run --source='weatherapp' manage.py test weatherapp

# Generate coverage report
coverage report

# Generate HTML coverage report
coverage html

echo ""
echo "✅ Tests completed!"
echo "📊 Coverage report generated in htmlcov/index.html"
echo ""
echo "Coverage summary:"
coverage report --format=total

