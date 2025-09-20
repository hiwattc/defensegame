#!/bin/bash

# Script: clean_tomcat_license.sh
# Tomcat web.xml Apache 라이선스 주석 제거

WEBXML="${1:-/usr/local/tomcat/conf/web.xml}"

# 파일 확인
[[ ! -f "$WEBXML" ]] && { 
    echo "❌ 파일 없음: $WEBXML" 
    echo "일반적인 경로: /opt/tomcat/conf/web.xml, /var/lib/tomcat9/conf/web.xml"
    exit 1 
}

# 백업
cp "$WEBXML" "$WEBXML.bak"
ORIG_COMMENTS=$(grep -c '<!--' "$WEBXML.bak")
ORIG_SIZE=$(stat -c%s "$WEBXML.bak")

echo "📁 백업 생성: $WEBXML.bak"
echo "📝 원본: ${ORIG_COMMENTS}개 주석, ${ORIG_SIZE}B"

# 🔧 Apache 라이선스 주석 완벽 제거
TEMP="${WEBXML}.tmp"

# 1. 주석 범위 전체 삭제
sed -n '
/<!--/ {
    :comment_start
    /-->/ b comment_end
    n
    b comment_start
}
# 주석이 아닌 라인만 출력
p
:comment_end
' "$WEBXML" > "$TEMP"

# 2. 인라인 주석 제거
sed -i 's/<!--[^-]*-->//g' "$TEMP"

# 3. 빈 줄 정리
sed -i '/^[[:space:]]*$/d' "$TEMP"

# 4. 적용
mv "$TEMP" "$WEBXML"

# 결과
NEW_COMMENTS=$(grep -c '<!--' "$WEBXML")
NEW_SIZE=$(stat -c%s "$WEBXML")
REMOVED=$((ORIG_COMMENTS - NEW_COMMENTS))

echo -e "\n✅ 완료!"
echo "📊 제거: ${REMOVED}개 주석"
echo "📏 크기: ${ORIG_SIZE}B → ${NEW_SIZE}B (-$((ORIG_SIZE-NEW_SIZE))B)"
echo "🔍 잔존: ${NEW_COMMENTS}개 주석"

# 검증
if [[ $NEW_COMMENTS -eq 0 ]]; then
    echo "🎉 모든 주석 완벽 제거!"
else
    echo "❌ ${NEW_COMMENTS}개 주석이 남음:"
    grep -n '<!--' "$WEBXML"
fi

echo -e "\n🔄 복원: cp $WEBXML.bak $WEBXML"
echo "🔄 Tomcat 재시작: sudo systemctl restart tomcat"