#!/bin/sh

# Start the NUT driver(s) in the background, retry until successful
echo "Attempting to start UPS driver..."
while ! /opt/nut/sbin/upsdrvctl -u root start; do
  echo "UPS driver failed to start. Retrying in 5 seconds..."
  sleep 5
done
echo "UPS driver started successfully."

# Start the NUT server in foreground mode for debugging
echo "Starting NUT server..."
exec /opt/nut/sbin/upsd -D -F
