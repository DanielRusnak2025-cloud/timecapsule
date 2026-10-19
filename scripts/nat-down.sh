#!/bin/bash
# nat-down.sh — удаляет временный NAT Gateway, маршрут и освобождает Elastic IP.
# Запускать в AWS CloudShell или Git Bash после установки пакетов.
set -euo pipefail

AWS_REGION=eu-central-1
STATE_FILE="$HOME/.nat-state"
export AWS_DEFAULT_REGION="$AWS_REGION"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Не найден $STATE_FILE — nat-up.sh не запускался или файл удалён." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$STATE_FILE"

echo "==> Удаляем маршрут 0.0.0.0/0 из private-rt"
aws ec2 delete-route \
  --route-table-id "$PRIVATE_RT_ID" \
  --destination-cidr-block 0.0.0.0/0 || true

echo "==> Удаляем NAT Gateway $NAT_ID"
aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" >/dev/null

echo "==> Ждём удаления NAT Gateway (несколько минут)"
aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"

# После удаления шлюза адрес отпускается не сразу — повторяем освобождение.
echo "==> Освобождаем Elastic IP $EIP_ALLOC_ID"
for i in 1 2 3 4 5 6; do
  if aws ec2 release-address --allocation-id "$EIP_ALLOC_ID" 2>/dev/null; then
    echo "    Elastic IP освобождён."
    break
  fi
  echo "    Адрес ещё привязан, попытка $i, ждём 15 с..."
  sleep 15
done

rm -f "$STATE_FILE"
echo "Готово. NAT удалён, маршрут удалён, Elastic IP освобождён."
