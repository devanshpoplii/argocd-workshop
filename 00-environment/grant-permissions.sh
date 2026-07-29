#!/bin/bash

echo ""
echo "======================================"
echo "  Grant Permissions to IDE Role"
echo "======================================"
echo ""

# Get the IDE role name from STS
IDE_ROLE=$(aws sts get-caller-identity --query "Arn" --output text | grep -oP '(?<=role/).*(?=/)')

if [ -z "$IDE_ROLE" ]; then
  echo "✗ Could not determine IDE role."
  exit 1
fi

echo "✔ Detected IDE Role: $IDE_ROLE"
echo ""
echo "  ┌──────────────────────────────────────────────────────────────────┐"
echo "  │ Run the following commands in CloudShell (not here):             │"
echo "  ├──────────────────────────────────────────────────────────────────┤"
echo "  │                                                                  │"
cat <<EOF
  aws iam detach-role-policy \\
    --role-name $IDE_ROLE \\
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

  aws iam put-role-policy \\
    --role-name $IDE_ROLE \\
    --policy-name ArgoCD-Workshop-Policy \\
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "eks:*",
            "ec2:*",
            "elasticloadbalancing:*",
            "iam:*",
            "codecommit:*",
            "sts:*",
            "cloudformation:*"
          ],
          "Resource": "*"
        }
      ]
    }'
EOF
echo ""
echo "  └──────────────────────────────────────────────────────────────────┘"
echo ""
echo "  After running in CloudShell, come back here and continue."
echo ""
