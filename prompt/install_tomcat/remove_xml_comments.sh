#!/bin/bash

# XML 파일의 주석을 제거하는 스크립트
# 사용법: ./remove_xml_comments.sh <xml_file_path>

# 인수 확인
if [ $# -eq 0 ]; then
    echo "사용법: $0 <xml_file_path>"
    echo "예시: $0 /path/to/your/file.xml"
    exit 1
fi

XML_FILE="$1"

# 파일 존재 여부 확인
if [ ! -f "$XML_FILE" ]; then
    echo "오류: 파일 '$XML_FILE'을 찾을 수 없습니다."
    exit 1
fi

# 백업 파일 생성
BACKUP_FILE="${XML_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$XML_FILE" "$BACKUP_FILE"
echo "백업 파일 생성: $BACKUP_FILE"

# 임시 파일 생성
TEMP_FILE=$(mktemp)

# XML 주석 제거 (<!-- ... --> 형태의 주석, 멀티라인 포함)
# sed를 사용하여 XML 주석을 제거 (정확한 주석만 제거, 정상 XML 태그 보존)
sed 's/<!--.*-->//g' "$XML_FILE" > "$TEMP_FILE"

# 원본 파일을 임시 파일로 교체
mv "$TEMP_FILE" "$XML_FILE"

echo "XML 주석이 성공적으로 제거되었습니다: $XML_FILE"
echo "원본 파일은 백업되어 있습니다: $BACKUP_FILE"
