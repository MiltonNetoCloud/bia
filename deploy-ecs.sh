#!/bin/bash

# Script de Deploy para ECS - Projeto BIA (Versão Melhorada)
# Autor: Amazon Q
# Versão: 2.0

set -e

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_ECR_REPO="395380602542.dkr.ecr.us-east-1.amazonaws.com/bia"
DEFAULT_CLUSTER="cluster--bia-alb"
DEFAULT_SERVICE="service-bia-alb"
DEFAULT_TASK_FAMILY="task-def-bia-alb"
DEFAULT_ALB_DNS="bia-alb-207197743.us-east-1.elb.amazonaws.com"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir help
show_help() {
    cat << EOF
${BLUE}=== Script de Deploy ECS - Projeto BIA (Melhorado) ===${NC}

${YELLOW}DESCRIÇÃO:${NC}
    Script melhorado para build e deploy da aplicação BIA no Amazon ECS.
    Inclui verificações de health check e validação de deploy.

${YELLOW}USO:${NC}
    $0 [OPÇÕES] COMANDO

${YELLOW}COMANDOS:${NC}
    build       Faz build da imagem Docker e push para ECR
    deploy      Faz deploy da aplicação no ECS
    rollback    Faz rollback para uma versão anterior
    list        Lista as últimas 10 task definitions
    status      Verifica status do serviço e health checks
    help        Exibe esta ajuda

${YELLOW}OPÇÕES:${NC}
    -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
    -e, --ecr-repo REPO         Repositório ECR (padrão: $DEFAULT_ECR_REPO)
    -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
    -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
    -f, --family FAMILY         Família da task definition (padrão: $DEFAULT_TASK_FAMILY)
    -t, --tag TAG               Tag específica para rollback
    -h, --help                  Exibe esta ajuda

${YELLOW}EXEMPLOS:${NC}
    # Build e deploy completo
    $0 build && $0 deploy

    # Verificar status do serviço
    $0 status

    # Rollback para versão específica
    $0 rollback --tag a1b2c3d

EOF
}

# Função para log colorido
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $*" ;;
    esac
}

# Função para verificar pré-requisitos
check_prerequisites() {
    log "INFO" "Verificando pré-requisitos..."
    
    # Verificar se está no diretório correto
    if [[ ! -f "package.json" ]] || [[ ! -f "Dockerfile" ]]; then
        log "ERROR" "Execute o script no diretório raiz do projeto BIA"
        exit 1
    fi
    
    # Verificar AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI não encontrado. Instale o AWS CLI primeiro."
        exit 1
    fi
    
    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker não encontrado. Instale o Docker primeiro."
        exit 1
    fi
    
    # Verificar credenciais AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "Credenciais AWS não configuradas ou inválidas"
        exit 1
    fi
    
    log "INFO" "Pré-requisitos verificados com sucesso"
}

# Função para obter commit hash
get_commit_hash() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        COMMIT_HASH=$(git rev-parse --short=7 HEAD)
    else
        log "WARN" "Não é um repositório Git. Usando timestamp como tag."
        COMMIT_HASH=$(date +%Y%m%d-%H%M%S)
    fi
    echo $COMMIT_HASH
}

# Função para fazer build da imagem
build_image() {
    log "INFO" "Iniciando build da imagem..."
    
    local commit_hash=$(get_commit_hash)
    local image_tag="$ECR_REPO:$commit_hash"
    local latest_tag="$ECR_REPO:latest"
    
    log "INFO" "Commit hash: $commit_hash"
    log "INFO" "Image tag: $image_tag"
    
    # Login no ECR
    log "INFO" "Fazendo login no ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO
    
    # Build da imagem
    log "INFO" "Construindo imagem Docker..."
    docker build -t $latest_tag .
    docker tag $latest_tag $image_tag
    
    # Push para ECR
    log "INFO" "Fazendo push da imagem para ECR..."
    docker push $latest_tag
    docker push $image_tag
    
    log "INFO" "Build concluído com sucesso!"
    log "INFO" "Imagem disponível em: $image_tag"
    
    # Salvar tag para uso posterior
    echo $commit_hash > .last_build_tag
}

# Função para verificar health check
check_health() {
    local max_attempts=30
    local attempt=1
    
    log "INFO" "Verificando health check da aplicação..."
    
    while [ $attempt -le $max_attempts ]; do
        log "DEBUG" "Tentativa $attempt/$max_attempts - Verificando $DEFAULT_ALB_DNS/api/versao"
        
        if curl -s -f "http://$DEFAULT_ALB_DNS/api/versao" > /dev/null; then
            log "INFO" "Health check passou! Aplicação está respondendo."
            return 0
        fi
        
        log "WARN" "Health check falhou. Aguardando 10 segundos..."
        sleep 10
        ((attempt++))
    done
    
    log "ERROR" "Health check falhou após $max_attempts tentativas"
    return 1
}

# Função para criar nova task definition
create_task_definition() {
    local image_tag=$1
    local full_image_uri="$ECR_REPO:$image_tag"
    
    log "INFO" "Criando nova task definition..." >&2
    log "DEBUG" "Imagem: $full_image_uri" >&2
    
    # Obter task definition atual
    local current_task_def=$(aws ecs describe-task-definition \
        --task-definition $TASK_FAMILY \
        --region $REGION \
        --query 'taskDefinition' \
        --output json 2>/dev/null || echo "{}")
    
    if [[ "$current_task_def" == "{}" ]]; then
        log "ERROR" "Task definition '$TASK_FAMILY' não encontrada" >&2
        log "INFO" "Certifique-se de que a task definition base existe no ECS" >&2
        exit 1
    fi
    
    # Atualizar imagem na task definition
    local new_task_def=$(echo $current_task_def | jq --arg image "$full_image_uri" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ')
    
    # Registrar nova task definition
    local new_revision=$(aws ecs register-task-definition \
        --region $REGION \
        --cli-input-json "$new_task_def" \
        --query 'taskDefinition.revision' \
        --output text)
    
    log "INFO" "Nova task definition criada: $TASK_FAMILY:$new_revision" >&2
    echo "$TASK_FAMILY:$new_revision"
}

# Função para fazer deploy
deploy_service() {
    local tag=${1:-$(cat .last_build_tag 2>/dev/null || echo "latest")}
    
    log "INFO" "Iniciando deploy para ECS..."
    log "INFO" "Tag: $tag"
    
    # Criar nova task definition
    local new_task_def=$(create_task_definition $tag)
    
    # Atualizar serviço
    log "INFO" "Atualizando serviço ECS..."
    aws ecs update-service \
        --region $REGION \
        --cluster $CLUSTER \
        --service $SERVICE \
        --task-definition $new_task_def \
        --output table
    
    log "INFO" "Aguardando estabilização do serviço..."
    aws ecs wait services-stable \
        --region $REGION \
        --cluster $CLUSTER \
        --services $SERVICE
    
    log "INFO" "Serviço estabilizado. Verificando health check..."
    
    # Verificar health check
    if check_health; then
        log "INFO" "Deploy concluído com sucesso!"
        log "INFO" "Serviço atualizado para: $new_task_def"
        log "INFO" "Aplicação disponível em: http://$DEFAULT_ALB_DNS"
    else
        log "ERROR" "Deploy falhou no health check"
        log "WARN" "Considere fazer rollback para versão anterior"
        exit 1
    fi
}

# Função para verificar status
check_status() {
    log "INFO" "Verificando status do serviço..."
    
    # Status do serviço ECS
    aws ecs describe-services \
        --region $REGION \
        --cluster $CLUSTER \
        --services $SERVICE \
        --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,TaskDefinition:taskDefinition}' \
        --output table
    
    # Health check
    log "INFO" "Verificando health check..."
    if curl -s -f "http://$DEFAULT_ALB_DNS/api/versao"; then
        echo ""
        log "INFO" "Health check: OK"
    else
        echo ""
        log "ERROR" "Health check: FALHOU"
    fi
    
    # Status do target group
    log "INFO" "Status dos targets no load balancer..."
    aws elbv2 describe-target-health \
        --region $REGION \
        --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:395380602542:targetgroup/tg-bia/e9631e999d61e51e" \
        --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
        --output table
}

# Função para rollback
rollback_service() {
    if [[ -z "$ROLLBACK_TAG" ]]; then
        log "ERROR" "Tag para rollback não especificada. Use --tag TAG"
        exit 1
    fi
    
    log "WARN" "Iniciando rollback para tag: $ROLLBACK_TAG"
    deploy_service $ROLLBACK_TAG
}

# Função para listar task definitions
list_versions() {
    log "INFO" "Listando últimas 10 versões da task definition..."
    
    aws ecs list-task-definitions \
        --region $REGION \
        --family-prefix $TASK_FAMILY \
        --status ACTIVE \
        --sort DESC \
        --max-items 10 \
        --query 'taskDefinitionArns[]' \
        --output table
}

# Parse dos argumentos
REGION=$DEFAULT_REGION
ECR_REPO=$DEFAULT_ECR_REPO
CLUSTER=$DEFAULT_CLUSTER
SERVICE=$DEFAULT_SERVICE
TASK_FAMILY=$DEFAULT_TASK_FAMILY
ROLLBACK_TAG=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -e|--ecr-repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -f|--family)
            TASK_FAMILY="$2"
            shift 2
            ;;
        -t|--tag)
            ROLLBACK_TAG="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        build|deploy|rollback|list|status|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log "ERROR" "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verificar se comando foi especificado
if [[ -z "$COMMAND" ]]; then
    log "ERROR" "Comando não especificado"
    show_help
    exit 1
fi

# Executar comando
case $COMMAND in
    "build")
        check_prerequisites
        build_image
        ;;
    "deploy")
        check_prerequisites
        deploy_service
        ;;
    "rollback")
        check_prerequisites
        rollback_service
        ;;
    "list")
        check_prerequisites
        list_versions
        ;;
    "status")
        check_prerequisites
        check_status
        ;;
    "help")
        show_help
        ;;
    *)
        log "ERROR" "Comando inválido: $COMMAND"
        show_help
        exit 1
        ;;
esac
