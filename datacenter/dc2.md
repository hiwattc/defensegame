 데이터센터 시뮬레이션 게임 개발 명세서1. 프로젝트 개요프로젝트명: 배턴루지 데이터 퓨즈 (Baton Rouge Data Fuse)목표: 루이지애나 배턴루지의 지형과 기후를 극복하며 수익성을 극대화하는 데이터센터 경영 시뮬레이터 개발.기술 스택: HTML5, CSS3, JavaScript (ES6+), Leaflet.js (지도), Canvas API (내부 그리드).2. 시스템 아키텍처게임은 크게 세 가지 레이어로 구성됩니다.World Layer (Macro): OSM 지도 기반 입지 선정 및 외부 날씨/전력망 관리.Facility Layer (Micro): 건물 내부 2D 격자(Grid) 기반 설비 배치 및 온도 시뮬레이션.Logic Layer (Engine): 경제 모델(수익/지출), 물리 엔진(열 확산), 이벤트 엔진(허리케인).3. 상세 모듈 명세3.1 지도 및 입지 시스템 (Leaflet.js 연동)좌표: 배턴루지 중심부 ($30.4515, -91.1871$).구현 기능:Map Container: OSM 타일을 로드하고 특정 구역을 '매입 가능 부지'로 표시.Site Attributes: 부지별 특성 정의 (강 인근: 수랭 효율 +20% / 시내: 전력 인입비 -30%).Building Overlay: 매입한 부지에 데이터센터 외형 렌더링.3.2 그리드 기반 내부 건설 시스템데이터 구조: $20 \times 20$ 2차원 배열.설비 객체 정보:Server Rack: 전력 소모(kW), 발열량, 월 임대 수익, 내구도.UPS/Generator: 최대 공급 전력, 연료 소모율(발전기).Cooling Unit (CRAC): 냉각 용량, 도달 거리, 전력 소모 효율.배치 로직: 격자 충돌 검사 및 'Aisle(복도)' 방향 설정 ($N, S, E, W$).3.3 가상 날씨 및 환경 엔진주기: 게임 시간 1분마다 상태 업데이트.날씨 상태 머신:NORMAL: 기본 PUE 1.2 유지.HEATWAVE: 외부 온도 $40^\circ\text{C}$ 육박, 공조기 부하 150% 증가.HURRICANE: 풍속 게이지 상승 → 전력망 차단 이벤트 → 비상 발전기 가동 강제.3.4 열 시뮬레이션 및 경제 로직온도 확산: 각 타일은 인접 타일과 온도를 평균화하며, 서버랙 타일은 지속적으로 온도를 가산.경제 공식:$Monthly\_Net = \sum(Rack\_Income) - (Energy\_Usage \times Rate) - Maintenance$$Energy\_Usage = (IT\_Load + Cooling\_Load) \times PUE\_Factor$4. 데이터 규격 (JSON 데이터 예시)JSON{
  "buildings": [
    {
      "id": "DC_01",
      "location": [30.4515, -91.1871],
      "grid": [], // 20x20 설비 데이터
      "stats": {
        "currentPUE": 1.25,
        "totalPower": 500, // kW
        "tempAlert": false
      }
    }
  ],
  "player": {
    "cash": 1000000,
    "reputation": 50,
    "unlockedTech": ["air_cooling", "diesel_gen"]
  }
}
5. UI/UX 와이어프레임 구성상단 바: 날짜/시간, 현재 날씨 아이콘, 예산, 전체 가동률(Uptime).중앙 화면: (기본) 배턴루지 지도 / (진입 시) 데이터센터 내부 그리드 뷰.우측 패널: 건설 메뉴 (랙, 공조기, 발전기 등 선택창).하단 대시보드: 실시간 전력량 그래프 및 온도 히트맵 토글 버튼.6. 개발 로드맵1주차: Leaflet.js 기반 지도 연동 및 부지 선택 기능 구현.2주차: Canvas API를 이용한 격자 배치 시스템 및 설비 라이브러리 제작.3주차: 가상 날씨 엔진 및 열 확산 알고리즘 최적화.4주차: 경제 시스템(수익/지출) 및 허리케인 비상 이벤트 연동.