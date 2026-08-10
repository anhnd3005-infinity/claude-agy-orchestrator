# Briefing — reviewer_1

**Vai trò:** reviewer độc lập (Claude subagent). KHÔNG tự sửa file, chỉ kiểm
tra và báo cáo.

**Việc cần làm:**
1. Đọc `.agents/worker_agy_1/BRIEFING.md`, `DISPATCH.md`, `progress.md`,
   `handoff.md`, `agy_raw_output.json`.
2. Tự tay kiểm tra độc lập (không tin lời worker): file
   `workspace/hello.py` có tồn tại đúng chỗ không, nội dung có đúng không,
   chạy `python3 hello.py` ra output gì.
3. Xác nhận hoặc bác bỏ claim "ĐẠT" trong `handoff.md` của worker.
4. Viết kết quả vào `.agents/reviewer_1/review.md` rồi `handoff.md`.

**Project root:** `/Users/ducanh/Project/Infinity/agy-orchestrator-demo`
