#!/bin/sh

# Start the NUT driver(s) in the background, retry until successful
echo "Attempting to start UPS driver..."
while ! /opt/nut/sbin/upsdrvctl -u root start; do
  echo "UPS driver failed to start. Retrying in 5 seconds..."
  sleep 5
done
echo "UPS driver started successfully."

# Start the NUT server
/opt/nut/sbin/upsd -u root

# Start the NUT monitor in the foreground
# The -D flag is important to keep the container running
# and to see log messages.
exec /opt/nut/sbin/upsmon -D
