#!/bin/bash
# Fix MariaDB strict mode warning

print_status() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_status "Fixing MariaDB strict mode..."

# Create MariaDB configuration to enable strict mode
sudo tee /etc/mysql/mariadb.conf.d/99-strict-mode.cnf > /dev/null << 'EOF'
[mysqld]
sql_mode = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
EOF

# Restart MariaDB to apply changes
print_status "Restarting MariaDB..."
sudo systemctl restart mysql

# Verify the change
print_status "Verifying MariaDB strict mode..."
mysql -u root -p -e "SELECT @@sql_mode;" 2>/dev/null | grep -q "STRICT_TRANS_TABLES" && echo "Strict mode enabled successfully!" || echo "Warning: Strict mode may not be enabled"

print_status "MariaDB strict mode fix completed!"
