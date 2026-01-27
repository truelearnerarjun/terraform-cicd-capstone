#!/bin/bash
set -e

# Update packages
yum update -y

# Install Apache
yum install -y httpd

# Simple web page
cat <<EOF >/var/www/html/index.html
<h1>Server Details</h1>
<p><strong>Hostname is :</strong> $(hostname)</p>
<p><strong>IP Address is :</strong> $(hostname -I | awk '{print $1}')</p>
EOF

# Enable + start Apache
systemctl enable httpd
systemctl restart httpd