#!/bin/bash

# Rocky Linux 웹서버 성능 튜닝 자동화 스크립트
# 작성자: System Administrator
# 용도: Apache, Nginx, Tomcat 성능 최적화
# 작성일시 : 2025.09.13
# 작성자 : claude3.5-sonnet
# prompt : 아래참고

#Rocky Linux 웹서버 성능 튜닝을 위한 자동화 스크립트를 작성했습니다.
#주요 기능
#1. 중복 방지 기능

#각 설정 파일에서 기존 설정 존재 여부 확인
#동일한 키가 이미 있으면 추가하지 않음
#안전한 설정 업데이트

#2. 백업 및 안전성

#모든 설정 파일 자동 백업 (타임스탬프 포함)
#Root 권한 확인
#에러 발생 시 스크립트 중단

#3. 포괄적인 튜닝

#/etc/security/limits.conf: 파일 디스크립터, 프로세스 수 제한
#/etc/sysctl.conf: 네트워크 버퍼, TCP 설정
#systemd 서비스: Apache, Nginx, Tomcat limits

#4. 설치된 서비스만 처리

#시스템에 설치된 웹서버만 자동 감지
#사용자 계정 존재 여부 확인
#불필요한 설정 방지

#사용 방법
#bash# 1. 스크립트 저장 및 실행 권한 부여
#sudo chmod +x webserver_tuning.sh

# 2. 실행 (root 권한 필요)
#sudo ./webserver_tuning.sh
#스크립트 실행 후 확인
#bash# 설정 적용 확인
#ulimit -n
#sysctl net.core.somaxconn
#systemctl show httpd | grep Limit

# 실행 중인 Apache 프로세스 limits 확인
#cat /proc/$(pidof httpd)/limits | grep "Max open files"
#이 스크립트는 기존 설정을 보존하면서 필요한 튜닝만 안전하게 추가합니다. 모든 변경사항은 백업되므로 문제 발생 시 롤백이 가능합니다.


# 디버그 모드 체크
if [[ "${1:-}" == "--debug" ]]; then
    set -ex  # 디버그 모드: 에러 시 종료 + 명령어 출력
    shift    # --debug 인수 제거
else
    set -e   # 일반 모드: 에러 시만 종료
fi

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다."
        exit 1
    fi
}

# 백업 함수
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_info "백업 생성: $backup"
    fi
}

# 설정이 이미 존재하는지 확인하고 추가하는 함수
add_config_if_not_exists() {
    local file="$1"
    local config="$2"
    local comment="$3"
    
    # 파일이 존재하지 않으면 생성
    if [[ ! -f "$file" ]]; then
        touch "$file"
    fi
    
    # 완전히 동일한 라인이 이미 있으면 추가하지 않음
    if grep -Fxq "$config" "$file"; then
        log_warning "이미 존재함(완전일치): $config → $file"
        return
    fi
    
    # limits.conf의 경우: 같은 키로 시작하는 라인이 있으면 기존 라인 주석 처리 후 새 값 추가
    # 키 추출 (공백으로 구분된 앞 3개 필드: 예) '* soft nofile')
    local key=$(echo "$config" | awk '{print $1,$2,$3}')
    if grep -Eq "^[[:space:]]*${key}[[:space:]]" "$file"; then
        # 기존 라인 주석 처리
        sed -i.bak "/^[[:space:]]*${key}[[:space:]]/ s/^/#(old)# /" "$file"
        log_info "기존 ${key} 라인 주석 처리: $file"
    fi
    
    # 새 값 추가 (빈 줄 없이)
    if [[ -n "$comment" ]]; then
        echo "# $comment" >> "$file"
    fi
    echo "$config" >> "$file"
    log_success "추가됨: $config → $file"
}

# limits.conf 설정 함수
configure_limits_conf() {
    log_info "=== /etc/security/limits.conf 설정 시작 ==="
    
    local limits_file="/etc/security/limits.conf"
    backup_file "$limits_file"
    
    # 일반 사용자 설정
    add_config_if_not_exists "$limits_file" "* soft nofile 65536" "파일 디스크립터 한계 설정"
    add_config_if_not_exists "$limits_file" "* hard nofile 65536"
    add_config_if_not_exists "$limits_file" "* soft nproc 32768" "프로세스 수 한계 설정"
    add_config_if_not_exists "$limits_file" "* hard nproc 32768"
    
    # 웹서버 사용자별 설정
    local users=("apache" "nginx" "tomcat")
    for user in "${users[@]}"; do
        if id "$user" &>/dev/null; then
            add_config_if_not_exists "$limits_file" "$user soft nofile 65536" "$user 사용자 설정"
            add_config_if_not_exists "$limits_file" "$user hard nofile 65536"
            add_config_if_not_exists "$limits_file" "$user soft nproc 32768"
            add_config_if_not_exists "$limits_file" "$user hard nproc 32768"
        fi
    done
    
    log_success "limits.conf 설정 완료"
}

# sysctl.conf 설정 함수
configure_sysctl() {
    log_info "=== /etc/sysctl.conf 네트워크 튜닝 시작 ==="
    
    local sysctl_file="/etc/sysctl.conf"
    backup_file "$sysctl_file"
    
    # TCP 연결 관련 설정
    add_config_if_not_exists "$sysctl_file" "net.core.somaxconn = 65535" "TCP 연결 관련 설정"
    add_config_if_not_exists "$sysctl_file" "net.core.netdev_max_backlog = 5000"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_max_syn_backlog = 65535"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_syncookies = 1"
    
    # TCP 버퍼 크기 설정
    add_config_if_not_exists "$sysctl_file" "net.core.rmem_default = 262144" "TCP 버퍼 크기 설정"
    add_config_if_not_exists "$sysctl_file" "net.core.rmem_max = 16777216"
    add_config_if_not_exists "$sysctl_file" "net.core.wmem_default = 262144"
    add_config_if_not_exists "$sysctl_file" "net.core.wmem_max = 16777216"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_rmem = 4096 262144 16777216"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_wmem = 4096 65536 16777216"
    
    # TCP 연결 재사용 및 타임아웃 설정
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_tw_reuse = 1" "TCP 연결 재사용 및 타임아웃 설정"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_fin_timeout = 30"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_keepalive_time = 1200"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_keepalive_probes = 3"
    add_config_if_not_exists "$sysctl_file" "net.ipv4.tcp_keepalive_intvl = 15"
    
    # 파일 시스템 관련 설정
    add_config_if_not_exists "$sysctl_file" "fs.file-max = 2097152" "파일 시스템 관련 설정"
    add_config_if_not_exists "$sysctl_file" "vm.swappiness = 10"
    
    # sysctl 설정 적용
    log_info "sysctl 설정 적용 중..."
    sysctl -p
    
    log_success "sysctl.conf 설정 완료"
}

# systemd 서비스 limits 설정 함수
configure_systemd_limits() {
    log_info "=== systemd 서비스 파일 limits 설정 시작 ==="
    
    local services=("httpd" "nginx" "tomcat")
    
    for service in "${services[@]}"; do
        # 서비스가 설치되어 있는지 확인
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            log_info "설정 중: $service.service"
            
            # override 디렉토리 생성
            local override_dir="/etc/systemd/system/${service}.service.d"
            mkdir -p "$override_dir"
            
            # limits.conf 파일 생성
            local limits_conf="$override_dir/limits.conf"
            
            if [[ ! -f "$limits_conf" ]]; then
                cat > "$limits_conf" << EOF
[Service]
LimitNOFILE=65536
LimitNPROC=32768
EOF
                log_success "생성됨: $limits_conf"
            else
                # 기존 파일이 있으면 설정 확인 후 추가
                if ! grep -q "LimitNOFILE" "$limits_conf"; then
                    echo "LimitNOFILE=65536" >> "$limits_conf"
                    log_success "추가됨: LimitNOFILE → $limits_conf"
                else
                    log_warning "이미 존재함: LimitNOFILE → $limits_conf"
                fi
                
                if ! grep -q "LimitNPROC" "$limits_conf"; then
                    echo "LimitNPROC=32768" >> "$limits_conf"
                    log_success "추가됨: LimitNPROC → $limits_conf"
                else
                    log_warning "이미 존재함: LimitNPROC → $limits_conf"
                fi
            fi
        else
            log_warning "$service.service가 설치되어 있지 않습니다."
        fi
    done
    
    # systemd 데몬 재로드
    log_info "systemd 데몬 재로드 중..."
    systemctl daemon-reload
    
    log_success "systemd 서비스 파일 설정 완료"
}

# 설정 확인 함수
verify_configuration() {
    log_info "=== 설정 확인 중 ==="
    
    echo
    echo "1. 현재 세션 limits:"
    echo "   - Open files: $(ulimit -n)"
    echo "   - Max processes: $(ulimit -u)"
    
    echo
    echo "2. sysctl 주요 설정:"
    echo "   - net.core.somaxconn: $(sysctl -n net.core.somaxconn 2>/dev/null || echo 'N/A')"
    echo "   - fs.file-max: $(sysctl -n fs.file-max 2>/dev/null || echo 'N/A')"
    
    echo
    echo "3. systemd 서비스 limits:"
    local services=("httpd" "nginx" "tomcat")
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            local limit_nofile=$(systemctl show "$service" 2>/dev/null | grep "LimitNOFILE=" | cut -d'=' -f2)
            echo "   - $service LimitNOFILE: ${limit_nofile:-N/A}"
        fi
    done
}

# 재시작 안내 함수
restart_services() {
    log_info "=== 서비스 재시작 안내 ==="
    
    echo
    log_warning "설정을 적용하려면 다음 중 하나를 선택하세요:"
    echo "1. 시스템 재부팅 (권장)"
    echo "2. 웹서버 서비스만 재시작"
    echo
    
    read -p "웹서버 서비스를 지금 재시작하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local services=("httpd" "nginx" "tomcat")
        for service in "${services[@]}"; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                log_info "$service 재시작 중..."
                systemctl restart "$service"
                if systemctl is-active --quiet "$service"; then
                    log_success "$service 재시작 성공"
                else
                    log_error "$service 재시작 실패"
                fi
            fi
        done
    else
        log_info "수동으로 서비스를 재시작하거나 시스템을 재부팅하세요."
    fi
}

# 메인 함수
main() {
    echo "======================================================"
    echo "Rocky Linux 웹서버 성능 튜닝 자동화 스크립트"
    echo "======================================================"
    echo
    
    check_root
    
    log_info "튜닝 작업을 시작합니다..."
    echo
    
    # 1. limits.conf 설정
    configure_limits_conf
    echo
    
    # 2. sysctl.conf 설정
    configure_sysctl
    echo
    
    # 3. systemd 서비스 설정
    configure_systemd_limits
    echo
    
    # 4. 설정 확인
    verify_configuration
    echo
    
    # 5. 재시작 안내
    restart_services
    
    echo
    log_success "모든 튜닝 작업이 완료되었습니다!"
    echo
    echo "추가 확인 명령어:"
    echo "  - ulimit -a                    # 현재 세션 limits"
    echo "  - sysctl net.core.somaxconn    # 네트워크 설정"
    echo "  - systemctl show httpd | grep Limit  # 서비스 limits"
    echo "  - cat /proc/\$(pidof httpd)/limits   # 실행 중인 프로세스 limits"
    echo "  - cat /etc/systemd/system/nginx.service.d"
    echo "  - cat /etc/systemd/system/tomcat.service.d"
    echo "  - cat /etc/systemd/system/httpd.service.d"
    echo "  - cat /etc/security/limits.conf"
    echo "  - cat /etc/sysctl.conf"
}

# 스크립트 실행
main "$@"