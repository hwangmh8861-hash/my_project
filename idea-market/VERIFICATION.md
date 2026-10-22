# 검증 기록 — 2026-10-22

## 통과

- 프로덕션 빌드 및 도메인 테스트 3개.
- 실제 Supabase API의 강사 로그인, 학생/강사/현황판 데이터 접근 분리.
- 같은 회사를 두 기기가 동시에 선택할 때 한 기기만 성공.
- 같은 기기 재접속과 회사 변경 차단.
- 서버의 자기 회사 투자·이유 길이·투자 단위·전액 배분·조원 확인 검증.
- 독립된 학생 세션 3개의 동시 제출 및 총액 1억 5,000만 원 집계.
- 독립된 Realtime 클라이언트 4개가 각각 갱신 알림 5개 수신.
- 중복 제출 차단, 투자 중 회사명 변경.
- 제출 취소에 따른 총액 차감 및 재제출.
- 기기 연결 해제에 따른 기존 토큰 차단 및 새 기기 접속.
- 마감 후 제출 차단 및 강사 원격 회고 화면 전환.

## 검증 제한

- 전체 초기화의 실제 API 실행은 데이터 삭제 위험으로 자동 승인 검토가 차단함. 데이터를 커밋하지 않는 롤백 트랜잭션으로 설정 유지/기본값 초기화와 서버 마감 검증 통과.
- Vercel 프로젝트 생성은 팀 권한 403으로 차단됨. 프런트엔드 배포와 배포 후 검증은 미완료.
- 아이폰 Safari·갤럭시 Chrome 실기기와 학교 Wi-Fi/LTE에서의 검증은 미완료.
- Realtime 테스트는 실제 Supabase에 연결한 독립된 소프트웨어 세션으로 진행했으며 실물 스마트폰 테스트는 아님.

## 회사 코드 입장 변경 — 2026-10-23

- 모의 서버 UI 테스트 4개와 기존 테스트 3개 통과. 학생 코드 입력·대기 잠금·입장 후 회사명·강사 코드 카드·7개 회사의 A4 2페이지(첫 페이지 6장) 배치를 확인.
- 운영 데이터와 분리된 `idea_codes_test` 스키마를 트랜잭션 내부에서 생성하고 롤백하는 서버 테스트 통과. 회사별 유일한 4자리 코드, 5회 실패 후 60초 대기, 대기 만료, 코드로 기기 교체와 기존 토큰 차단, 재발급 후 이전 코드 거부, 제출 완료 유지, 전역 실패 대기와 만료, 코드 비노출, 초기화 코드 회전, 조 추가 코드 발급을 확인.
- 동일하게 분리된 `idea_codes_upgrade_test`에서 기존 연결과 투자 내역을 가진 구 스키마에 추가 변경을 적용하여 데이터 보존과 코드 발급 확인 후 롤백.
- 자기 회사 투자 금지·100만 원 단위·전액 배분·투자 이유·조원 확인·중복 제출 차단 검증 유지.
- 운영 수업에 잘못된 코드나 기기 교체 입력을 보내는 테스트는 수행하지 않음.

## Instructor stage layout
- Only the instructor frontend and CSS changed; no database, RPC or student/board protocol changes.
- Fixed status strip: status, timer, submitted count, one stage action.
- Four accessible tabs; automatic selection only on status/epoch change; manual selection and unsaved settings survive polling.
- Company actions in a more dialog. Closing removes open dialogs and the cancellation control; click guard also rejects stale cancellation controls.
- Reopening retained in reflection. Admin QR/address preview removed.
- `npm test`: 10 tests pass, including state transitions, tab persistence, dirty settings and stale cancellation protection. `npm run build`: pass.
