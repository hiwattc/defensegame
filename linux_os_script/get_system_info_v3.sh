#!/bin/bash

# Rocky Linux 시스템 관리자를 위한 종합 시스템 정보 스크립트 v2.0
# 작성자: System Administrator Helper
# 용도: 시스템 상태 점검 및 관리 정보 수집

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 구분선 함수
print_separator() {
    echo -e "${BLUE}=================================================${NC}"
}

print_header() {
    echo -e "${WHITE}$1${NC}"
    print_separator
}

# 시스템 기본 정보
system_basic_info() {
    print_header "시스템 기본 정보"
    
    echo -e "${CYAN}호스트명:${NC} $(hostname)"
    echo -e "${CYAN}운영체제:${NC} $(cat /etc/redhat-release)"
    echo -e "${CYAN}커널 버전:${NC} $(uname -r)"
    echo -e "${CYAN}아키텍처:${NC} $(uname -m)"
    echo -e "${CYAN}시스템 가동 시간:${NC} $(uptime -p)"
    echo -e "${CYAN}현재 시간:${NC} $(date)"
    echo -e "${CYAN}타임존:${NC} $(timedatectl | grep "Time zone" | awk '{print $3}')"
    echo -e "${CYAN}시스템 로드:${NC} $(uptime | awk -F'load average:' '{print $2}')"
    echo -e "${CYAN}호스트 네임 해석 설정:${NC}"
    if [ -f /etc/host.conf ]; then
        echo "/etc/host.conf 설정:"
        cat /etc/host.conf
    else
        echo "/etc/host.conf 파일이 없습니다"
    fi
    
    if [ -f /etc/nsswitch.conf ]; then
        echo ""
        echo "nsswitch.conf hosts 설정:"
        grep "^hosts:" /etc/nsswitch.conf
    fi
    echo ""
}

# CPU 정보
cpu_info() {
    print_header "CPU 정보"
    
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
    cpu_cores=$(nproc)
    cpu_threads=$(grep -c processor /proc/cpuinfo)
    
    echo -e "${CYAN}CPU 모델:${NC} $cpu_model"
    echo -e "${CYAN}물리 코어:${NC} $cpu_cores"
    echo -e "${CYAN}논리 프로세서:${NC} $cpu_threads"
    echo -e "${CYAN}CPU 사용률:${NC}"
    top -bn1 | grep "Cpu(s)" | awk '{print $2 $3 $4 $5}'
    echo ""
}

# 메모리 정보
memory_info() {
    print_header "메모리 정보"
    
    echo -e "${CYAN}메모리 상세:${NC}"
    free -h
    echo ""
    echo -e "${CYAN}메모리 사용률:${NC}"
    free | awk 'NR==2{printf "사용중: %.2f%% (%s/%s)\n", $3*100/($3+$7), $3, $2}'
    echo ""
}

# 디스크 정보
disk_info() {
    print_header "디스크 정보"
    
    echo -e "${CYAN}블록 디바이스 구조 (lsblk):${NC}"
    lsblk -f
    echo ""
    
    echo -e "${CYAN}디스크 파티션 정보 (fdisk):${NC}"
    if command -v fdisk >/dev/null 2>&1; then
        fdisk -l 2>/dev/null | grep -E "^Disk|^Device|^/dev/" | head -20
    else
        echo "fdisk 명령어를 사용할 수 없습니다"
    fi
    echo ""
    
    echo -e "${CYAN}파일시스템 사용량:${NC}"
    df -h | grep -E '^/dev/'
    echo ""
    
    echo -e "${CYAN}디스크 I/O 통계:${NC}"
    if command -v iostat >/dev/null 2>&1; then
        iostat -x 1 1 | grep -A 20 "Device"
    else
        echo "iostat 명령어가 설치되어 있지 않습니다. (sysstat 패키지 필요)"
    fi
    echo ""
    
    echo -e "${CYAN}마운트된 파일시스템:${NC}"
    mount | column -t
    echo ""
    
    echo -e "${CYAN}fstab 설정:${NC}"
    if [ -f /etc/fstab ]; then
        echo "/etc/fstab 내용:"
        grep -v "^#" /etc/fstab | grep -v "^$" | column -t
        echo ""
        echo "fstab 주석 포함 전체:"
        cat /etc/fstab | head -20
    else
        echo "/etc/fstab 파일을 찾을 수 없습니다"
    fi
    echo ""
    
    echo -e "${CYAN}스토리지 장치 정보:${NC}"
    if [ -d /sys/block ]; then
        for device in $(ls /sys/block/ | grep -E '^(sd|nvme|vd)'); do
            size=$(cat /sys/block/$device/size 2>/dev/null)
            if [ -n "$size" ] && [ "$size" -gt 0 ]; then
                size_gb=$(echo "scale=1; $size * 512 / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
                echo "  /dev/$device: ${size_gb} GB"
            fi
        done
    fi
    echo ""
}

# 네트워크 정보
network_info() {
    print_header "네트워크 정보"
    
    echo -e "${CYAN}네트워크 인터페이스:${NC}"
    ip addr show | grep -E '^[0-9]+:|inet '
    echo ""
    
    echo -e "${CYAN}라우팅 테이블:${NC}"
    ip route show
    echo ""
    
    echo -e "${CYAN}DNS 설정:${NC}"
    cat /etc/resolv.conf | grep nameserver
    echo ""
    
    echo -e "${CYAN}열린 포트:${NC}"
    ss -tuln | head -20
    echo ""
}

# 프로세스 정보
process_info() {
    print_header "프로세스 정보"
    
    echo -e "${CYAN}실행 중인 프로세스 수:${NC} $(ps aux | wc -l)"
    echo -e "${CYAN}좀비 프로세스:${NC} $(ps aux | awk '$8 ~ /^Z/ {count++} END {print count+0}')"
    echo ""
    
    echo -e "${CYAN}CPU 사용량 상위 10개 프로세스:${NC}"
    ps aux --sort=-%cpu | head -11
    echo ""
    
    echo -e "${CYAN}메모리 사용량 상위 10개 프로세스:${NC}"
    ps aux --sort=-%mem | head -11
    echo ""
}

# 서비스 정보
service_info() {
    print_header "시스템 서비스 정보"
    
    echo -e "${CYAN}활성 서비스:${NC}"
    systemctl list-units --type=service --state=active | head -20
    echo ""
    
    echo -e "${CYAN}실패한 서비스:${NC}"
    failed_services=$(systemctl list-units --type=service --state=failed --no-legend | wc -l)
    if [ $failed_services -gt 0 ]; then
        echo -e "${RED}실패한 서비스 $failed_services개:${NC}"
        systemctl list-units --type=service --state=failed --no-legend
    else
        echo -e "${GREEN}실패한 서비스 없음${NC}"
    fi
    echo ""
}

# 로그 정보
log_info() {
    print_header "시스템 로그 정보"
    
    echo -e "${CYAN}최근 시스템 로그 (마지막 10줄):${NC}"
    journalctl -n 10 --no-pager
    echo ""
    
    echo -e "${CYAN}부팅 시간:${NC}"
    systemd-analyze | head -1
    echo ""
    
    echo -e "${CYAN}느린 서비스 (부팅 시간):${NC}"
    systemd-analyze blame | head -10
    echo ""
}

# 보안 정보 (강화됨)
security_info() {
    print_header "보안 관련 정보"
    
    echo -e "${CYAN}방화벽 상태:${NC}"
    if systemctl is-active firewalld >/dev/null 2>&1; then
        echo -e "${GREEN}firewalld 활성화${NC}"
        firewall-cmd --list-all-zones | head -20
    else
        echo -e "${YELLOW}firewalld 비활성화${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}SELinux 상태:${NC}"
    if command -v getenforce >/dev/null 2>&1; then
        selinux_status=$(getenforce)
        case $selinux_status in
            "Enforcing") echo -e "${GREEN}SELinux: $selinux_status${NC}" ;;
            "Permissive") echo -e "${YELLOW}SELinux: $selinux_status${NC}" ;;
            "Disabled") echo -e "${RED}SELinux: $selinux_status${NC}" ;;
        esac
    else
        echo "SELinux 정보를 가져올 수 없습니다"
    fi
    echo ""
    
    echo -e "${CYAN}SSH 보안 설정:${NC}"
    if [ -f /etc/ssh/sshd_config ]; then
        echo -n "Root 로그인: "
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
        if [ "$root_login" = "no" ]; then
            echo -e "${GREEN}비허용${NC}"
        elif [ "$root_login" = "yes" ]; then
            echo -e "${RED}허용${NC}"
        else
            echo -e "${YELLOW}${root_login:-기본값(허용)}${NC}"
        fi
        
        echo -n "패스워드 인증: "
        password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
        if [ "$password_auth" = "no" ]; then
            echo -e "${GREEN}비허용${NC}"
        else
            echo -e "${YELLOW}${password_auth:-기본값(허용)}${NC}"
        fi
        
        echo -n "빈 패스워드: "
        empty_password=$(grep "^PermitEmptyPasswords" /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
        if [ "$empty_password" = "no" ]; then
            echo -e "${GREEN}비허용${NC}"
        else
            echo -e "${RED}${empty_password:-기본값(허용)}${NC}"
        fi
        
        echo -n "SSH 포트: "
        ssh_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
        echo "${ssh_port:-22}"
    else
        echo "SSH 설정 파일을 찾을 수 없습니다"
    fi
    echo ""
    
    echo -e "${CYAN}사용자 계정 정보:${NC}"
    echo "전체 사용자 수: $(getent passwd | wc -l)"
    echo "일반 사용자 (UID >= 1000): $(getent passwd | awk -F: '$3 >= 1000 {print $1}' | wc -l)"
    echo ""
    
    echo -e "${CYAN}sudo 권한 사용자:${NC}"
    if [ -f /etc/group ]; then
        wheel_users=$(getent group wheel | cut -d: -f4)
        if [ -n "$wheel_users" ]; then
            echo "wheel 그룹: $wheel_users"
        else
            echo "wheel 그룹에 사용자 없음"
        fi
    fi
    
    if [ -d /etc/sudoers.d ]; then
        sudo_files=$(ls /etc/sudoers.d/ 2>/dev/null | wc -l)
        echo "추가 sudoers 파일: $sudo_files개"
        if [ $sudo_files -gt 0 ]; then
            ls /etc/sudoers.d/
        fi
    fi
    echo ""
    
    echo -e "${CYAN}패스워드 정책:${NC}"
    if [ -f /etc/login.defs ]; then
        echo -n "패스워드 최대 사용일: "
        grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}' || echo "설정 없음"
        echo -n "패스워드 최소 사용일: "
        grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}' || echo "설정 없음"
        echo -n "패스워드 최소 길이: "
        grep "^PASS_MIN_LEN" /etc/login.defs | awk '{print $2}' || echo "설정 없음"
        echo -n "패스워드 경고일: "
        grep "^PASS_WARN_AGE" /etc/login.defs | awk '{print $2}' || echo "설정 없음"
    fi
    
    if [ -f /etc/security/pwquality.conf ]; then
        echo ""
        echo "패스워드 복잡도 정책:"
        grep -v "^#" /etc/security/pwquality.conf | grep -v "^$" | head -10
    fi
    echo ""
    
    echo -e "${CYAN}계정 잠금 정책:${NC}"
    if [ -f /etc/security/faillock.conf ]; then
        echo "faillock 설정:"
        grep -v "^#" /etc/security/faillock.conf | grep -v "^$" | head -10
    elif [ -f /etc/pam.d/password-auth ]; then
        echo "PAM faillock 설정:"
        grep "pam_faillock" /etc/pam.d/password-auth | head -3
    else
        echo "계정 잠금 정책 설정 없음"
    fi
    echo ""
    
    echo -e "${CYAN}로그인한 사용자:${NC}"
    who
    echo ""
    
    echo -e "${CYAN}최근 로그인 기록:${NC}"
    last | head -10
    echo ""
    
    echo -e "${CYAN}실패한 로그인 시도:${NC}"
    if command -v lastb >/dev/null 2>&1; then
        lastb | head -5
    else
        echo "lastb 명령어 사용 불가"
    fi
    echo ""
}

# 패키지 관리 정보
package_info() {
    print_header "패키지 관리 정보"
    
    echo -e "${CYAN}설치된 패키지 수:${NC}"
    rpm -qa | wc -l
    echo ""
    
    echo -e "${CYAN}업데이트 가능한 패키지:${NC}"
    updates=$(dnf check-update --quiet 2>/dev/null | wc -l)
    if [ $updates -gt 0 ]; then
        echo -e "${YELLOW}$updates개의 업데이트 가능한 패키지${NC}"
        echo "업데이트 확인: dnf check-update"
    else
        echo -e "${GREEN}모든 패키지가 최신 버전입니다${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}최근 설치된 패키지 (10개):${NC}"
    rpm -qa --last | head -10
    echo ""
}

# 하드웨어 정보
hardware_info() {
    print_header "하드웨어 정보"
    
    echo -e "${CYAN}PCI 장치:${NC}"
    lspci | head -10
    echo "..."
    echo ""
    
    if command -v lshw >/dev/null 2>&1; then
        echo -e "${CYAN}시스템 요약:${NC}"
        lshw -short | head -15
        echo "..."
    else
        echo -e "${YELLOW}lshw 명령어가 설치되어 있지 않습니다${NC}"
    fi
    echo ""
}

# 시스템 튜닝 정보 (새로 추가)
tuning_info() {
    print_header "시스템 튜닝 및 설정 정보"
    
    echo -e "${CYAN}커널 매개변수 (sysctl):${NC}"
    echo "주요 네트워크 설정:"
    echo "  net.ipv4.ip_forward = $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'N/A')"
    echo "  net.ipv4.tcp_syncookies = $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo 'N/A')"
    echo "  net.ipv4.tcp_max_syn_backlog = $(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo 'N/A')"
    echo "  net.core.somaxconn = $(sysctl -n net.core.somaxconn 2>/dev/null || echo 'N/A')"
    echo "  net.core.netdev_max_backlog = $(sysctl -n net.core.netdev_max_backlog 2>/dev/null || echo 'N/A')"
    echo ""
    
    echo "메모리 관리 설정:"
    echo "  vm.swappiness = $(sysctl -n vm.swappiness 2>/dev/null || echo 'N/A')"
    echo "  vm.dirty_ratio = $(sysctl -n vm.dirty_ratio 2>/dev/null || echo 'N/A')"
    echo "  vm.dirty_background_ratio = $(sysctl -n vm.dirty_background_ratio 2>/dev/null || echo 'N/A')"
    echo "  vm.overcommit_memory = $(sysctl -n vm.overcommit_memory 2>/dev/null || echo 'N/A')"
    echo "  vm.max_map_count = $(sysctl -n vm.max_map_count 2>/dev/null || echo 'N/A')"
    echo ""
    
    echo "파일 시스템 설정:"
    echo "  fs.file-max = $(sysctl -n fs.file-max 2>/dev/null || echo 'N/A')"
    echo "  fs.nr_open = $(sysctl -n fs.nr_open 2>/dev/null || echo 'N/A')"
    echo "  fs.inotify.max_user_watches = $(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 'N/A')"
    echo ""
    
    echo "커널 보안 설정:"
    echo "  kernel.randomize_va_space = $(sysctl -n kernel.randomize_va_space 2>/dev/null || echo 'N/A')"
    echo "  kernel.exec-shield = $(sysctl -n kernel.exec-shield 2>/dev/null || echo 'N/A')"
    echo "  kernel.dmesg_restrict = $(sysctl -n kernel.dmesg_restrict 2>/dev/null || echo 'N/A')"
    echo ""
    
    echo -e "${CYAN}사용자 제한 설정 (limits):${NC}"
    if [ -f /etc/security/limits.conf ]; then
        echo "limits.conf 주요 설정:"
        grep -v "^#" /etc/security/limits.conf | grep -v "^$" | head -10
        if [ $(grep -v "^#" /etc/security/limits.conf | grep -v "^$" | wc -l) -eq 0 ]; then
            echo "  사용자 정의 제한 없음"
        fi
    else
        echo "limits.conf 파일을 찾을 수 없습니다"
    fi
    echo ""
    
    if [ -d /etc/security/limits.d ]; then
        limit_files=$(ls /etc/security/limits.d/*.conf 2>/dev/null | wc -l)
        echo "추가 limits 설정 파일: $limit_files개"
        if [ $limit_files -gt 0 ]; then
            for file in /etc/security/limits.d/*.conf; do
                if [ -f "$file" ]; then
                    echo "  $(basename $file):"
                    grep -v "^#" "$file" | grep -v "^$" | head -5 | sed 's/^/    /'
                fi
            done
        fi
    fi
    echo ""
    
    echo -e "${CYAN}현재 시스템 제한값:${NC}"
    echo "프로세스별 제한:"
    echo "  최대 열린 파일: $(ulimit -n)"
    echo "  최대 프로세스: $(ulimit -u)"
    echo "  최대 스택 크기: $(ulimit -s) KB"
    echo "  최대 메모리 크기: $(ulimit -v) KB"
    echo "  최대 코어 덤프: $(ulimit -c)"
    echo ""
    
    echo -e "${CYAN}부팅 매개변수:${NC}"
    if [ -f /proc/cmdline ]; then
        echo "커널 부팅 매개변수:"
        cat /proc/cmdline
    fi
    echo ""
    
    echo -e "${CYAN}성능 튜닝 권장사항:${NC}"
    # 스왑 사용량 체크
    swap_usage=$(free | awk '/^Swap:/ {if ($2 > 0) printf "%.0f", $3*100/$2; else print "0"}')
    if [ "$swap_usage" -gt 10 ]; then
        echo -e "${YELLOW}  - 스왑 사용량이 ${swap_usage}%입니다. vm.swappiness 조정을 고려하세요${NC}"
    fi
    
    # 파일 디스크립터 사용량 체크
    max_files=$(sysctl -n fs.file-max 2>/dev/null || echo "0")
    used_files=$(cat /proc/sys/fs/file-nr | awk '{print $1}')
    if [ "$max_files" -gt 0 ] && [ "$used_files" -gt 0 ]; then
        file_usage=$(echo "scale=0; $used_files*100/$max_files" | bc 2>/dev/null || echo "0")
        if [ "$file_usage" -gt 80 ]; then
            echo -e "${YELLOW}  - 파일 디스크립터 사용량이 ${file_usage}%입니다. fs.file-max 증가를 고려하세요${NC}"
        fi
    fi
    
    echo ""
}

# 시스템 리소스 경고
check_warnings() {
    print_header "시스템 상태 경고"
    
    # 디스크 사용량 체크
    df -h | awk '
    NR>1 {
        usage = substr($5, 1, length($5)-1)
        if (usage > 90) {
            print "\033[0;31m경고: " $6 " 파티션 사용량 " $5 "\033[0m"
        }
        else if (usage > 80) {
            print "\033[1;33m주의: " $6 " 파티션 사용량 " $5 "\033[0m"
        }
    }'
    
    # 메모리 사용량 체크
    memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/($3+$7)}')
    if [ $memory_usage -gt 90 ]; then
        echo -e "${RED}경고: 메모리 사용량 ${memory_usage}%${NC}"
    elif [ $memory_usage -gt 80 ]; then
        echo -e "${YELLOW}주의: 메모리 사용량 ${memory_usage}%${NC}"
    fi
    
    # 로드 평균 체크
    load_avg=$(uptime | awk '{print $10}' | cut -d',' -f1)
    cpu_count=$(nproc)
    if (( $(echo "$load_avg > $cpu_count" | bc -l) )); then
        echo -e "${RED}경고: 높은 시스템 로드 (${load_avg})${NC}"
    fi
    
    echo ""
}

# 메인 실행
main() {
    clear
    echo -e "${WHITE}Rocky Linux 시스템 정보 리포트 v2.0${NC}"
    echo -e "${WHITE}생성 시간: $(date)${NC}"
    print_separator
    echo ""
    
    system_basic_info
    cpu_info
    memory_info
    disk_info
    network_info
    process_info
    service_info
    log_info
    security_info
    package_info
    hardware_info
    tuning_info
    check_warnings
    
    echo -e "${GREEN}시스템 정보 수집 완료!${NC}"
    echo -e "${CYAN}이 스크립트를 정기적으로 실행하여 시스템 상태를 모니터링하세요.${NC}"
}

# 옵션 처리
case "${1:-}" in
    --basic|-b)
        system_basic_info
        ;;
    --cpu|-c)
        cpu_info
        ;;
    --memory|-m)
        memory_info
        ;;
    --disk|-d)
        disk_info
        ;;
    --network|-n)
        network_info
        ;;
    --process|-p)
        process_info
        ;;
    --service|-s)
        service_info
        ;;
    --security|-sec)
        security_info
        ;;
    --log|-l)
        log_info
        ;;
    --package|-pkg)
        package_info
        ;;
    --hardware|-hw)
        hardware_info
        ;;
    --tuning|-t)
        tuning_info
        ;;
    --warnings|-w)
        check_warnings
        ;;
    --help|-h)
        echo "Rocky Linux 시스템 정보 스크립트 v2.0"
        echo "사용법: $0 [옵션]"
        echo ""
        echo "옵션:"
        echo "  --basic, -b     기본 시스템 정보"
        echo "  --cpu, -c       CPU 정보"
        echo "  --memory, -m    메모리 정보"
        echo "  --disk, -d      디스크 정보"
        echo "  --network, -n   네트워크 정보"
        echo "  --process, -p   프로세스 정보"
        echo "  --service, -s   서비스 정보"
        echo "  --security, -sec 보안 정보"
        echo "  --log, -l       로그 정보"
        echo "  --package, -pkg 패키지 정보"
        echo "  --hardware, -hw 하드웨어 정보"
        echo "  --tuning, -t    시스템 튜닝 정보"
        echo "  --warnings, -w  시스템 경고"
        echo "  --help, -h      도움말"
        echo ""
        echo "옵션 없이 실행하면 모든 정보를 표시합니다."
        ;;
    *)
        main
        ;;
esac