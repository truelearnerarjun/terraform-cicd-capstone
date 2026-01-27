#!/bin/bash
set -e

# Update packages
yum update -y

# Install CodeDeploy Agent
yum install -y ruby wget
cd /home/ec2-user
wget https://aws-codedeploy-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/install
chmod +x ./install
./install auto
systemctl start codedeploy-agent
systemctl enable codedeploy-agent

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