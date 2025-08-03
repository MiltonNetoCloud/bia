#!/bin/bash

# Script de Deploy para ECS - Projeto BIA
# Autor: Amazon Q
# Versão: 1.0

set -e

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_ECR_REPO="395380602542.dkr.ecr.us-east-1.amazonaws.com/bia"
DEFAULT_CLUSTER="cluster--bia-alb"
DEFAULT_SERVICE="service-bia-alb"
DEFAULT_TASK_FAMILY="task-def-bia-alb"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir help
show_help() {
    cat << EOF
${BLUE}=== Script de Deploy ECS - Projeto BIA ===${NC}

${YELLOW}DESCRIÇÃO:${NC}
    Script para build e deploy da aplicação BIA no Amazon ECS.
    Cada deploy cria uma nova task definition com tag baseada no commit hash,
    permitindo rollbacks para versões anteriores.

${YELLOW}USO:${NC}
    $0 [OPÇÕES] COMANDO

${YELLOW}COMANDOS:${NC}
    build       Faz build da imagem Docker e push para ECR
    deploy      Faz deploy da aplicação no ECS
    rollback    Faz rollback para uma versão anterior
    list        Lista as últimas 10 task definitions
    help        Exibe esta ajuda

${YELLOW}OPÇÕES:${NC}
    -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
    -e, --ecr-repo REPO         Repositório ECR (padrão: $DEFAULT_ECR_REPO)
    -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
    -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
    -f, --family FAMILY         Família da task definition (padrão: $DEFAULT_TASK_FAMILY)
    -t, --tag TAG               Tag específica para rollback
