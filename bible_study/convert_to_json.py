import re
import json

input_path = "웨스턴민스터_소요리문답_분다우리교회pdf.json"
output_path = "웨스턴민스터_소요리문답_bunda.json"

res = []
with open(input_path, encoding="utf-8") as f:
    lines = f.readlines()

q, a = None, []
for line in lines:
    line = line.strip()
    if re.match(r"^문 ?\d+\.", line):
        if q is not None and a:
            res.append({"question": q, "answer": " ".join(a).strip()})
        q = line
        a = []
    elif line.startswith("답,"):
        a = [line]
    elif q is not None:
        a.append(line)
if q and a:
    res.append({"question": q, "answer": " ".join(a).strip()})

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)

print(f"저장 완료: {output_path}")
