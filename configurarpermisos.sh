#!/bin/bash

# Configuración
ORG="ENOToken"
COLLABORATORS=("brauliostefano" "CallejaJ" "dercdevil")

# Funciones de utilidad
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_success() {
    echo "[SUCCESS] $1"
}

# Función para esperar entre llamadas a la API
rate_limit_wait() {
    sleep 2  # Esperar 2 segundos entre llamadas a la API
}

# Función para verificar los permisos existentes
check_collaborator_permission() {
    local repo=$1
    local user=$2
    local response

    response=$(gh api -X GET "repos/$ORG/$repo/collaborators/$user/permission" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$response" | jq -r '.permission'
        return 0
    else
        echo "none"
        return 1
    fi
}

# Función para configurar permisos con reintentos
configure_permissions() {
    local repo=$1
    local user=$2
    local max_attempts=3
    local attempt=1
    local wait_time=5

    while [ $attempt -le $max_attempts ]; do
        log_info "Intento $attempt de $max_attempts para configurar permisos de $user en $repo..."
        
        if gh api -X PUT "repos/$ORG/$repo/collaborators/$user" \
            -H "Accept: application/vnd.github.v3+json" \
            -f permission="write" &> /dev/null; then
            
            # Verificar que los permisos se aplicaron correctamente
            rate_limit_wait
            current_permission=$(check_collaborator_permission "$repo" "$user")
            if [ "$current_permission" = "write" ] || [ "$current_permission" = "admin" ]; then
                log_success "Permisos configurados correctamente para $user en $repo"
                return 0
            fi
        fi

        log_error "Intento $attempt fallido para $user en $repo"
        attempt=$((attempt + 1))
        
        if [ $attempt -le $max_attempts ]; then
            log_info "Reintentando en $wait_time segundos..."
            sleep $wait_time
            wait_time=$((wait_time * 2))  # Incrementar tiempo de espera exponencialmente
        fi
    done

    return 1
}

# Verificar autenticación con GitHub
if ! gh auth status &> /dev/null; then
    log_error "No estás autenticado en GitHub CLI. Ejecuta 'gh auth login' primero."
    exit 1
fi

# Obtener repositorios
log_info "Obteniendo repositorios de la organización $ORG..."
repos=$(gh repo list "$ORG" --limit 100 --json name --jq '.[].name') || {
    log_error "Error al obtener la lista de repositorios"
    exit 1
}

# Procesar cada repositorio
for repo in $repos; do
    log_info "Procesando repositorio: $repo"
    
    for collaborator in "${COLLABORATORS[@]}"; do
        # Verificar permisos actuales
        current_permission=$(check_collaborator_permission "$repo" "$collaborator")
        
        if [ "$current_permission" = "write" ] || [ "$current_permission" = "admin" ]; then
            log_info "El usuario $collaborator ya tiene permisos suficientes en $repo (${current_permission})"
            continue
        fi

        log_info "Configurando permisos de escritura para $collaborator en $repo..."
        
        if ! configure_permissions "$repo" "$collaborator"; then
            log_error "No se pudieron configurar los permisos para $collaborator en $repo después de varios intentos"
        fi

        rate_limit_wait
    done
done

log_info "Script completado exitosamente."