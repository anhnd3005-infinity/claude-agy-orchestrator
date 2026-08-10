# Original request

**Từ user (2026-08-10):** Muốn Claude Code quản lý/điều phối các agent của
`agy` (Antigravity CLI), theo pattern `.agents/` orchestration đã dùng ở
project `senior_product_designer_agent` — orchestrator điều phối bằng file,
không qua API ẩn.

**Phân vai đã chốt:**
- `agy` (headless, `--print`) = worker thực thi.
- Claude Code = orchestrator.
- Claude subagent (Agent tool) = reviewer độc lập.

**Scope vòng đầu:** chỉ dựng khung + chạy smoke test bằng task giả
("hello world"), chưa có sản phẩm thật. Task thật sẽ giao sau khi khung chạy
thông.
