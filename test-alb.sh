#!/bin/bash

# Script de Teste - Verificar se aplicação está usando ALB
# Autor: Amazon Q

ALB_URL="http://bia-alb-207197743.us-east-1.elb.amazonaws.com"

echo "🔍 Testando se a aplicação BIA está usando o Application Load Balancer..."
echo ""

# Teste 1: Health Check da API
echo "1️⃣ Testando health check da API..."
API_RESPONSE=$(curl -s "$ALB_URL/api/versao")
if [[ "$API_RESPONSE" == *"Bia"* ]]; then
    echo "✅ API respondendo: $API_RESPONSE"
else
    echo "❌ API não está respondendo corretamente"
    exit 1
fi

# Teste 2: Verificar se o frontend carrega
echo ""
echo "2️⃣ Testando se o frontend carrega..."
FRONTEND_RESPONSE=$(curl -s "$ALB_URL" | head -10)
if [[ "$FRONTEND_RESPONSE" == *"<html"* ]]; then
    echo "✅ Frontend carregando corretamente"
else
    echo "❌ Frontend não está carregando"
    exit 1
fi

# Teste 3: Verificar se o JavaScript compilado contém a URL do ALB
echo ""
echo "3️⃣ Verificando se o frontend está configurado para usar o ALB..."
JS_FILE=$(curl -s "$ALB_URL" | grep -o 'assets/index-[^"]*\.js' | head -1)
if [[ -n "$JS_FILE" ]]; then
    ALB_COUNT=$(curl -s "$ALB_URL/$JS_FILE" | grep -c "bia-alb.*amazonaws.com")
    if [[ $ALB_COUNT -gt 0 ]]; then
        echo "✅ Frontend configurado para usar ALB ($ALB_COUNT referências encontradas)"
    else
        echo "❌ Frontend NÃO está configurado para usar ALB"
        exit 1
    fi
else
    echo "❌ Não foi possível encontrar arquivo JavaScript"
    exit 1
fi

# Teste 4: Testar endpoint de tarefas
echo ""
echo "4️⃣ Testando endpoint de tarefas..."
TASKS_RESPONSE=$(curl -s "$ALB_URL/api/tarefas")
if [[ "$TASKS_RESPONSE" == "["* ]]; then
    TASK_COUNT=$(echo "$TASKS_RESPONSE" | jq '. | length' 2>/dev/null || echo "N/A")
    echo "✅ Endpoint de tarefas funcionando ($TASK_COUNT tarefas encontradas)"
else
    echo "❌ Endpoint de tarefas não está funcionando"
    exit 1
fi

# Teste 5: Verificar targets do load balancer
echo ""
echo "5️⃣ Verificando status dos targets no load balancer..."
HEALTHY_TARGETS=$(aws elbv2 describe-target-health \
    --region us-east-1 \
    --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:395380602542:targetgroup/tg-bia/e9631e999d61e51e" \
    --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
    --output text 2>/dev/null || echo "0")

if [[ $HEALTHY_TARGETS -gt 0 ]]; then
    echo "✅ $HEALTHY_TARGETS targets healthy no load balancer"
else
    echo "❌ Nenhum target healthy no load balancer"
    exit 1
fi

echo ""
echo "🎉 Todos os testes passaram! A aplicação BIA está funcionando corretamente com o Application Load Balancer."
echo ""
echo "📋 Resumo:"
echo "   • API: $ALB_URL/api/versao"
echo "   • Frontend: $ALB_URL"
echo "   • Tarefas: $ALB_URL/api/tarefas"
echo "   • Targets healthy: $HEALTHY_TARGETS"
echo ""
echo "🌐 Acesse a aplicação em: $ALB_URL"
