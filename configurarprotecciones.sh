#!/bin/bash

# Configuración
ORG="ENOToken"
declare -A COLLABORATORS
COLLABORATORS=(
    ["brauliostefano"]="Stefano"
    ["CallejaJ"]="Jorge"
    ["dercdevil"]="Darwin"
)
DEFAULT_BRANCH="main"

# Funciones de utilidad
log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# Función para verificar si un usuario ya tiene acceso
check_user_access() {
    local repo=$1
    local branch=$2
    local user=$3
    
    protection_data=$(gh api "repos/$ORG/$repo/branches/$branch/protection" 2>/dev/null)
    if [ $? -eq 0 ]; then
        users_list=$(echo "$protection_data" | jq -r '.restrictions.users[].login' 2>/dev/null)
        if echo "$users_list" | grep -q "^$user$"; then
            return 0
        fi
    fi
    return 1
}

# Función para verificar las protecciones
verify_branch_protection() {
    local repo=$1
    local branch=$2
    local user=$3
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if check_user_access "$repo" "$branch" "$user"; then
            return 0
        fi
        attempt=$((attempt + 1))
        [ $attempt -le $max_attempts ] && sleep 1
    done
    return 1
}

# Función para verificar y crear rama si es necesario
create_branch_if_needed() {
    local repo=$1
    local branch=$2
    local github_user=$3
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if ! gh api "repos/$ORG/$repo/branches/$branch" &> /dev/null; then
            log_info "Creando rama $branch ($github_user)..."
            
            local main_sha
            main_sha=$(gh api "repos/$ORG/$repo/git/refs/heads/$DEFAULT_BRANCH" --jq '.object.sha' 2>/dev/null)
            
            if [ -n "$main_sha" ]; then
                if gh api -X POST "repos/$ORG/$repo/git/refs" \
                    -f ref="refs/heads/$branch" \
                    -f sha="$main_sha" &>/dev/null; then
                    log_success "Rama $branch creada para $github_user"
                    return 0
                fi
            fi
        else
            return 0
        fi
        
        attempt=$((attempt + 1))
        [ $attempt -le $max_attempts ] && sleep 1
    done
    return 1
}

# Función para configurar protecciones
configure_branch_protection() {
    local repo=$1
    local branch=$2
    local github_user=$3
    local max_attempts=3
    local attempt=1

    # JSON de configuración compactado
    protection_json="{
        \"required_status_checks\": null,
        \"enforce_admins\": false,
        \"required_pull_request_reviews\": null,
        \"restrictions\": {
            \"users\": [\"$github_user\"],
            \"teams\": [],
            \"apps\": []
        },
        \"allow_force_pushes\": true,
        \"allow_deletions\": false,
        \"required_linear_history\": false,
        \"allow_merge_commit\": true,
        \"allow_squash_merge\": true,
        \"allow_rebase_merge\": true
    }"

    while [ $attempt -le $max_attempts ]; do
        if echo "$protection_json" | gh api -X PUT "repos/$ORG/$repo/branches/$branch/protection" \
            --input - \
            -H "Accept: application/vnd.github.v3+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" &>/dev/null; then
            
            if verify_branch_protection "$repo" "$branch" "$github_user"; then
                log_success "Protecciones configuradas para $branch ($github_user)"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        [ $attempt -le $max_attempts ] && sleep 2
    done
    log_error "No se pudieron configurar las protecciones para $branch ($github_user)"
    return 1
}

# Verificar autenticación con GitHub
if ! gh auth status &> /dev/null; then
    echo "[ERROR] No autenticado. Ejecuta 'gh auth login'"
    exit 1
fi

# Obtener repositorios
log_info "Obteniendo repositorios de $ORG..."
repos=$(gh repo list "$ORG" --limit 100 --json name --jq '.[].name') || exit 1

# Procesar cada repositorio
for repo in $repos; do
    log_info "Procesando repositorio: $repo"
    
    # Verificar rama principal
    if ! gh api "repos/$ORG/$repo/branches/$DEFAULT_BRANCH" &> /dev/null; then
        log_error "No existe rama $DEFAULT_BRANCH en $repo, saltando..."
        continue
    fi

    # Procesar colaboradores
    for github_user in "${!COLLABORATORS[@]}"; do
        branch_name="${COLLABORATORS[$github_user]}"
        
        log_info "Configurando protecciones para $branch_name ($github_user)..."
        
        # Crear rama si no existe
        if ! create_branch_if_needed "$repo" "$branch_name" "$github_user"; then
            log_error "No se pudo crear la rama $branch_name para $github_user"
            continue
        fi

        # Configurar/actualizar protecciones
        configure_branch_protection "$repo" "$branch_name" "$github_user"
    done
done

log_success "Proceso completado"