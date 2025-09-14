#!/bin/bash

echo "=============================="
echo "  httpd 성능 튜닝 리포트"
echo "  생성일: $(date)"
echo "=============================="

# 1. httpd 프로세스 정보
echo -e "\n[1] httpd 프로세스 현황"
ps -C httpd -o pid,ppid,cmd,%mem,%cpu --sort=-%cpu

# 2. httpd 프로세스 개수
echo -e "\n[2] httpd 프로세스 개수"
ps -C httpd --no-headers | wc -l

# 3. httpd 주요 설정값 (httpd.conf)
HTTPD_CONF=$(httpd -V 2>/dev/null | grep SERVER_CONFIG_FILE | awk -F'"' '{print $2}')
if [ -z "$HTTPD_CONF" ]; then
    HTTPD_CONF="/etc/httpd/conf/httpd.conf"
fi
echo -e "\n[3] httpd 주요 설정값 ($HTTPD_CONF)"
grep -E "^(ServerLimit|MaxRequestWorkers|StartServers|MinSpareServers|MaxSpareServers|KeepAlive|KeepAliveTimeout|Timeout|Listen)" $HTTPD_CONF | grep -v "^#"

# 4. Listen 포트 및 바인딩 정보
echo -e "\n[4] httpd Listen 포트 및 바인딩"
ss -ltnp | grep httpd

# 5. 현재 열려있는 연결 수
echo -e "\n[5] 현재 열려있는 httpd 연결 수"
ss -ant | grep ':80 ' | wc -l

# 6. 커널 파라미터 (httpd 성능 관련)
echo -e "\n[6] 커널 파라미터 (httpd 성능 관련)"
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_max_syn_backlog
sysctl fs.file-max
sysctl net.ipv4.ip_local_port_range
sysctl net.ipv4.tcp_tw_reuse
sysctl net.ipv4.tcp_fin_timeout
sysctl net.ipv4.tcp_keepalive_time
sysctl net.ipv4.tcp_keepalive_intvl
sysctl net.ipv4.tcp_keepalive_probes
ulimit -n

# 7. httpd 프로세스별 /proc/pid/limits 정보 (ppid=1)
echo -e "\n[7] httpd 프로세스별 /proc/pid/limits 정보 (ppid=1)"
for pid in $(ps -C httpd -o pid=,ppid= | awk '$2==1{print $1}'); do
    echo -e "\n--- PID: $pid ---"
    if [ -f "/proc/$pid/limits" ]; then
        cat /proc/$pid/limits
    else
        echo "/proc/$pid/limits 파일이 존재하지 않습니다."
    fi
done

# 8. 성능 진단 및 권장사항
echo -e "\n[8] 성능 진단 및 권장사항"

# 프로세스 개수 진단
proc_count=$(ps -C httpd --no-headers | wc -l)
if [ "$proc_count" -lt 5 ]; then
  echo "- httpd 프로세스 개수가 너무 적습니다. (현재: $proc_count, 권장: 5개 이상, 실제 서비스 상황에 따라 조정 필요)"
elif [ "$proc_count" -gt 256 ]; then
  echo "- httpd 프로세스 개수가 너무 많습니다. (현재: $proc_count, 권장: 256개 이하, 서버 자원 확인 필요)"
else
  echo "- httpd 프로세스 개수가 적절합니다. (현재: $proc_count)"
fi

# MaxRequestWorkers 권장
max_workers=$(grep -i '^MaxRequestWorkers' $HTTPD_CONF | grep -v '^#' | awk '{print $2}')
if [ -n "$max_workers" ]; then
  if [ "$max_workers" -lt 150 ]; then
    echo "- MaxRequestWorkers 값이 낮게 설정되어 있습니다. (현재: $max_workers, 권장: 150 이상)"
  else
    echo "- MaxRequestWorkers 값이 적절하게 설정되어 있습니다. (현재: $max_workers)"
  fi
else
  echo "- MaxRequestWorkers 값이 설정되어 있지 않습니다. 기본값(256)이 사용될 수 있습니다."
fi

# 파일 디스크립터 권장
open_files=$(ulimit -n)
if [ "$open_files" -lt 4096 ]; then
  echo "- 파일 디스크립터(ulimit -n) 값이 낮습니다. (현재: $open_files, 권장: 4096 이상)"
else
  echo "- 파일 디스크립터(ulimit -n) 값이 적절합니다. (현재: $open_files)"
fi

# somaxconn 권장
somaxconn=$(sysctl -n net.core.somaxconn)
if [ "$somaxconn" -lt 1024 ]; then
  echo "- net.core.somaxconn 값이 낮습니다. (현재: $somaxconn, 권장: 1024 이상)"
else
  echo "- net.core.somaxconn 값이 적절합니다. (현재: $somaxconn)"
fi

# tcp_max_syn_backlog 권장
tcp_max_syn_backlog=$(sysctl -n net.ipv4.tcp_max_syn_backlog)
if [ "$tcp_max_syn_backlog" -lt 1024 ]; then
  echo "- net.ipv4.tcp_max_syn_backlog 값이 낮습니다. (현재: $tcp_max_syn_backlog, 권장: 1024 이상)"
else
  echo "- net.ipv4.tcp_max_syn_backlog 값이 적절합니다. (현재: $tcp_max_syn_backlog)"
fi

# ip_local_port_range 권장
port_range=$(sysctl -n net.ipv4.ip_local_port_range)
start_port=$(echo $port_range | awk '{print $1}')
end_port=$(echo $port_range | awk '{print $2}')
if [ "$start_port" -gt 1024 ] || [ "$end_port" -lt 65000 ]; then
  echo "- net.ipv4.ip_local_port_range 값이 좁게 설정되어 있습니다. (현재: $port_range, 권장: 1024 65535)"
else
  echo "- net.ipv4.ip_local_port_range 값이 적절합니다. (현재: $port_range)"
fi

# tcp_tw_reuse 권장
tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse)
if [ "$tw_reuse" -eq 1 ]; then
  echo "- net.ipv4.tcp_tw_reuse 값이 활성화되어 있습니다. (TIME_WAIT 재사용 가능)"
else
  echo "- net.ipv4.tcp_tw_reuse 값이 비활성화되어 있습니다. 대량 접속 환경에서는 1 권장"
fi

# tcp_fin_timeout 권장
fin_timeout=$(sysctl -n net.ipv4.tcp_fin_timeout)
if [ "$fin_timeout" -gt 60 ]; then
  echo "- net.ipv4.tcp_fin_timeout 값이 높습니다. (현재: $fin_timeout, 권장: 30~60)"
else
  echo "- net.ipv4.tcp_fin_timeout 값이 적절합니다. (현재: $fin_timeout)"
fi

# KeepAlive 권장
keepalive=$(grep -i '^KeepAlive' $HTTPD_CONF | grep -v '^#' | awk '{print $2}' | head -1)
if [ "$keepalive" = "On" ] || [ "$keepalive" = "on" ]; then
  echo "- KeepAlive가 활성화되어 있습니다. 대량 접속 시 KeepAliveTimeout 값을 조정하세요."
else
  echo "- KeepAlive가 비활성화되어 있습니다. 짧은 요청 위주라면 적절할 수 있습니다."
fi

echo -e "\n=============================="
echo "  리포트 종료"
echo "=============================="

# 9. limits.conf 및 서비스 limits 분석
LIMITS_CONF="/etc/security/limits.conf"
HTTPD_LIMITS_CONF="/etc/systemd/system/httpd.service.d/limits.conf"
echo -e "\n[9] limits.conf 및 httpd 서비스 limits 분석"
if [ -f "$LIMITS_CONF" ]; then
  echo "- $LIMITS_CONF 내용 요약:"
  grep -E -v '^#|^$' $LIMITS_CONF | grep -E 'httpd|soft|hard|nofile|nproc' || echo "  (관련 설정 없음)"
else
  echo "- $LIMITS_CONF 파일이 존재하지 않습니다."
fi
if [ -f "$HTTPD_LIMITS_CONF" ]; then
  echo "- $HTTPD_LIMITS_CONF 내용 요약:"
  grep -E -v '^#|^$' $HTTPD_LIMITS_CONF || echo "  (관련 설정 없음)"
else
  echo "- $HTTPD_LIMITS_CONF 파일이 존재하지 않습니다."
fi

# limits.conf 및 서비스 limits 상세 진단
# nofile(파일디스크립터) 진단
nofile_soft=$(grep -E 'httpd.*soft.*nofile' $LIMITS_CONF | awk '{print $4}' | sort -n | tail -1)
nofile_hard=$(grep -E 'httpd.*hard.*nofile' $LIMITS_CONF | awk '{print $4}' | sort -n | tail -1)
if [ -z "$nofile_soft" ]; then nofile_soft=1024; fi
if [ -z "$nofile_hard" ]; then nofile_hard=4096; fi
if [ "$nofile_soft" -lt 4096 ] || [ "$nofile_hard" -lt 4096 ]; then
  echo "- limits.conf의 nofile(파일디스크립터) soft/hard 값이 낮습니다. (soft: $nofile_soft, hard: $nofile_hard, 권장: 4096 이상)"
else
  echo "- limits.conf의 nofile(파일디스크립터) soft/hard 값이 적절합니다. (soft: $nofile_soft, hard: $nofile_hard)"
fi
# nproc(프로세스 수) 진단
nproc_soft=$(grep -E 'httpd.*soft.*nproc' $LIMITS_CONF | awk '{print $4}' | sort -n | tail -1)
nproc_hard=$(grep -E 'httpd.*hard.*nproc' $LIMITS_CONF | awk '{print $4}' | sort -n | tail -1)
if [ -z "$nproc_soft" ]; then nproc_soft=4096; fi
if [ -z "$nproc_hard" ]; then nproc_hard=4096; fi
if [ "$nproc_soft" -lt 4096 ] || [ "$nproc_hard" -lt 4096 ]; then
  echo "- limits.conf의 nproc(프로세스 수) soft/hard 값이 낮습니다. (soft: $nproc_soft, hard: $nproc_hard, 권장: 4096 이상)"
else
  echo "- limits.conf의 nproc(프로세스 수) soft/hard 값이 적절합니다. (soft: $nproc_soft, hard: $nproc_hard)"
fi

# 서비스 단위 limits.conf 진단 (systemd)
if [ -f "$HTTPD_LIMITS_CONF" ]; then
  svc_nofile=$(grep -i 'LimitNOFILE' $HTTPD_LIMITS_CONF | awk -F= '{print $2}' | tr -d ' ' | sort -n | tail -1)
  svc_nproc=$(grep -i 'LimitNPROC' $HTTPD_LIMITS_CONF | awk -F= '{print $2}' | tr -d ' ' | sort -n | tail -1)
  if [ -n "$svc_nofile" ] && [ "$svc_nofile" -lt 4096 ]; then
    echo "- httpd 서비스의 LimitNOFILE 값이 낮습니다. (현재: $svc_nofile, 권장: 4096 이상)"
  elif [ -n "$svc_nofile" ]; then
    echo "- httpd 서비스의 LimitNOFILE 값이 적절합니다. (현재: $svc_nofile)"
  fi
  if [ -n "$svc_nproc" ] && [ "$svc_nproc" -lt 4096 ]; then
    echo "- httpd 서비스의 LimitNPROC 값이 낮습니다. (현재: $svc_nproc, 권장: 4096 이상)"
  elif [ -n "$svc_nproc" ]; then
    echo "- httpd 서비스의 LimitNPROC 값이 적절합니다. (현재: $svc_nproc)"
  fi
fi

# 2배 더 세밀한 진단: 위험구간, 상세설명, 개선방안 등
# 예시: 위험구간, 상세설명, 개선방안 안내
if [ "$open_files" -lt 1024 ]; then
  echo "[위험] ulimit -n 값이 1024 미만입니다. 대량 접속 시 파일디스크립터 부족으로 서비스 장애가 발생할 수 있습니다. limits.conf, systemd 서비스 파일, ulimit 설정을 모두 점검하세요."
fi
if [ "$max_workers" -lt 50 ]; then
  echo "[위험] MaxRequestWorkers 값이 50 미만입니다. 동시접속이 많은 환경에서는 심각한 성능 저하가 발생할 수 있습니다."
fi
if [ "$somaxconn" -lt 128 ]; then
  echo "[위험] net.core.somaxconn 값이 128 미만입니다. SYN flood 등 대량 연결 요청에 취약할 수 있습니다."
fi
if [ "$tcp_max_syn_backlog" -lt 128 ]; then
  echo "[위험] net.ipv4.tcp_max_syn_backlog 값이 128 미만입니다. 대량 접속 시 SYN backlog overflow로 연결이 거부될 수 있습니다."
fi
if [ "$fin_timeout" -gt 120 ]; then
  echo "[위험] net.ipv4.tcp_fin_timeout 값이 120초를 초과합니다. TIME_WAIT 소켓이 과도하게 쌓여 리소스 고갈 위험이 있습니다."
fi
if [ "$proc_count" -gt 512 ]; then
  echo "[위험] httpd 프로세스 개수가 512개를 초과합니다. 서버 자원 한계 초과로 장애 위험이 있습니다."
fi
# 상세설명 및 개선방안 예시
if [ "$open_files" -lt 4096 ]; then
  echo "[개선방안] /etc/security/limits.conf, systemd 서비스 파일, ulimit 명령어를 통해 nofile 값을 4096 이상으로 상향 조정하세요."
fi
if [ "$max_workers" -lt 150 ]; then
  echo "[개선방안] httpd.conf에서 MaxRequestWorkers 값을 150 이상으로 조정하세요. 서버 메모리 상황에 따라 적정값을 산정하세요."
fi
if [ "$somaxconn" -lt 1024 ]; then
  echo "[개선방안] sysctl로 net.core.somaxconn 값을 1024 이상으로 조정하세요. (/etc/sysctl.conf 반영 권장)"
fi
if [ "$tcp_max_syn_backlog" -lt 1024 ]; then
  echo "[개선방안] sysctl로 net.ipv4.tcp_max_syn_backlog 값을 1024 이상으로 조정하세요."
fi
if [ "$fin_timeout" -gt 60 ]; then
  echo "[개선방안] sysctl로 net.ipv4.tcp_fin_timeout 값을 60 이하로 조정하세요."
fi
if [ "$proc_count" -gt 256 ]; then
  echo "[개선방안] httpd.conf의 MaxRequestWorkers, ServerLimit 값을 서버 자원에 맞게 조정하고, 불필요한 프로세스가 생성되지 않도록 설정을 최적화하세요."
fi
