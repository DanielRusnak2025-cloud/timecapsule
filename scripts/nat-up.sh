#!/bin/bash
# nat-up.sh — поднимает временный NAT Gateway для доступа приватных серверов в интернет.
# Запускать в AWS CloudShell или Git Bash. Требует AWS CLI с правами на EC2/VPC.
set -euo pipefail

# --- Настройки: подставьте свои идентификаторы (видны в консоли VPC) ---
AWS_REGION=eu-central-1
PUBLIC_SUBNET_ID=subnet-XXXXXXXXXXXX     # timecapsule-dev-public-a
PRIVATE_RT_ID=rtb-XXXXXXXXXXXX           # timecapsule-dev-private-rt
OWNER=danielrusnak                        # ваш nickname (тег Owner)
STATE_FILE="$HOME/.nat-state"             # сюда сохраняются ID для nat-down.sh

export AWS_DEFAULT_REGION="$AWS_REGION"

TAGS='ResourceType=natgateway,Tags=[{Key=Name,Value=timecapsule-dev-nat-a},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value='"$OWNER"'},{Key=Lab,Value=lab3}]'
EIP_TAGS='ResourceType=elastic-ip,Tags=[{Key=Name,Value=timecapsule-dev-nat-a-eip},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value='"$OWNER"'},{Key=Lab,Value=lab3}]'

echo "==> Выделяем Elastic IP для NAT"
EIP_ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications "$EIP_TAGS" \
  --query AllocationId --output text)
echo "    EIP AllocationId: $EIP_ALLOC_ID"

echo "==> Создаём NAT Gateway в public-a"
NAT_ID=$(aws ec2 create-nat-gateway \
  --subnet-id "$PUBLIC_SUBNET_ID" \
  --allocation-id "$EIP_ALLOC_ID" \
  --tag-specifications "$TAGS" \
  --query NatGateway.NatGatewayId --output text)
echo "    NatGatewayId: $NAT_ID"

echo "==> Ждём, пока NAT Gateway станет Available (несколько минут)"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

echo "==> Добавляем маршрут 0.0.0.0/0 -> NAT в private-rt"
aws ec2 create-route \
  --route-table-id "$PRIVATE_RT_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT_ID" >/dev/null

# Сохраняем ID для nat-down.sh
printf 'NAT_ID=%s\nEIP_ALLOC_ID=%s\nPRIVATE_RT_ID=%s\n' \
  "$NAT_ID" "$EIP_ALLOC_ID" "$PRIVATE_RT_ID" > "$STATE_FILE"

echo "Готово. NAT поднят. Установите пакеты на db-server, затем запустите nat-down.sh."
