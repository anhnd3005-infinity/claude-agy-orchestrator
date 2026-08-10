# Plan — smoke test vòng 1

**Mục tiêu:** kiểm chứng luồng orchestrator (Claude Code) → worker_agy (agy
headless) → reviewer (Claude subagent) chạy được end-to-end bằng file, theo
đúng pattern `.agents/` đã dùng ở `senior_product_designer_agent`.

**Các bước đã chạy:**
1. Dựng khung `.agents/` (README quy ước, ORIGINAL_REQUEST).
2. Dispatch `worker_agy_1`: giao task "tạo hello.py + chạy" cho `agy --print`.
   - Attempt 1 thất bại vị trí file (agy dùng scratch dir riêng, không dùng
     cwd) → phát hiện cần `--add-dir`.
   - Attempt 2 thành công sau khi thêm `--add-dir <workspace tuyệt đối>`.
3. Dispatch `reviewer_1` (Claude subagent, Agent tool): verify độc lập.
   → **VERDICT: PASS**, có 1 ghi chú nhỏ về log file gây hiểu lầm (đã sửa).

**Kết luận vòng 1:** Khung orchestration hoạt động đúng như thiết kế. Bài
học quan trọng nhất cần mang sang các dispatch thật sau này: **luôn dùng
`agy --add-dir <path-tuyệt-đối-của-workspace>`** khi giao việc cho agy
worker, nếu không sản phẩm có thể lạc vào
`~/.gemini/antigravity-cli/scratch/` mà `status` vẫn báo `SUCCESS`.

**Việc chưa làm (để ngoài scope vòng 1, chờ user xác nhận task thật):**
- Chưa có `challenger_*` (phản biện) — chỉ cần khi task thật phức tạp hơn.
- Chưa thử dispatch nhiều worker_agy song song.
- Chưa thử `--json-schema` để ép output có cấu trúc.
