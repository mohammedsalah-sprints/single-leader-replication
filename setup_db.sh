#!/bin/bash

# Define variables
MASTER_CONTAINER="database_master"
SLAVE_CONTAINER="database_slave"
MYSQL_ROOT_PASSWORD="S3cret"
REPL_USER="mydb_slave_user"
REPL_PASSWORD="mydb_slave_pwd"

# Function to execute MySQL commands
execute_mysql() {
  local container=$1
  local query=$2
  docker exec "$container" sh -c "mysql -u root -p$MYSQL_ROOT_PASSWORD -e \"$query\""
}

# Create replication user on the master
create_replication_user() {
  # Drop the user if it already exists (ignore error if it doesn't)
  execute_mysql "$MASTER_CONTAINER" "DROP USER IF EXISTS '$REPL_USER'@'%';"

  # Create the replication user with mysql_native_password
  local query="CREATE USER '$REPL_USER'@'%' IDENTIFIED WITH mysql_native_password BY '$REPL_PASSWORD'; GRANT REPLICATION SLAVE ON *.* TO '$REPL_USER'@'%'; FLUSH PRIVILEGES;"
  execute_mysql "$MASTER_CONTAINER" "$query"
}

# Get master status
get_master_status() {
  local status
  status=$(execute_mysql "$MASTER_CONTAINER" "FLUSH TABLES WITH READ LOCK; SHOW MASTER STATUS;")
  echo "$status"
}

# Change master on the slave
change_master_on_slave() {
  local log_file=$1
  local log_pos=$2
  local query="CHANGE MASTER TO MASTER_HOST='$MASTER_CONTAINER', MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWORD', MASTER_LOG_FILE='$log_file', MASTER_LOG_POS=$log_pos;"
  execute_mysql "$SLAVE_CONTAINER" "$query"
}

# Main script execution
main() {
  # Create replication user on the master
  create_replication_user

  # Get master status
  MASTER_STATUS=$(get_master_status)
  echo "$MASTER_STATUS"

  # Extract log file and position
  CURRENT_LOG=$(echo "$MASTER_STATUS" | awk 'NR==2 {print $1}')
  CURRENT_POS=$(echo "$MASTER_STATUS" | awk 'NR==2 {print $2}')

  # Unlock tables
  execute_mysql "$MASTER_CONTAINER" "UNLOCK TABLES;"

  # Stop the slave before making changes
  execute_mysql "$SLAVE_CONTAINER" "STOP SLAVE;"

  # Change master on the slave
  change_master_on_slave "$CURRENT_LOG" "$CURRENT_POS"

  # Start the slave after setting the master
  execute_mysql "$SLAVE_CONTAINER" "START SLAVE;"

  # Show slave status
  execute_mysql "$SLAVE_CONTAINER" "SHOW SLAVE STATUS \G"
}

# Run the main function
main
