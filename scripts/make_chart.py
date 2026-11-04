"""从 results/*.csv 生成简单的 SVG 折线图（不依赖第三方库）。

用法：python scripts/make_chart.py
"""
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def line_chart(rows, x_key, series, out_path, title, x_label, y_label,
               width=720, height=420, pad=70):
    xs = [float(r[x_key]) for r in rows]
    xmin, xmax = min(xs), max(xs)
    ymax = max(float(r[k]) for r in rows for k, _ in series) * 1.15

    def px(x):
        return pad + (x - xmin) / (xmax - xmin or 1) * (width - 2 * pad)

    def py(y):
        return height - pad - (y / ymax) * (height - 2 * pad)

    colors = ["#2563eb", "#dc2626", "#16a34a"]
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'font-family="Segoe UI, sans-serif" font-size="13">',
        f'<rect width="{width}" height="{height}" fill="#ffffff"/>',
        f'<text x="{width/2}" y="28" text-anchor="middle" font-size="17" '
        f'font-weight="600" fill="#111827">{title}</text>',
    ]

    # 坐标轴
    parts.append(f'<line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" stroke="#9ca3af"/>')
    parts.append(f'<line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" stroke="#9ca3af"/>')

    # 网格 + y 轴刻度
    for i in range(6):
        y = ymax * i / 5
        yy = py(y)
        parts.append(f'<line x1="{pad}" y1="{yy:.1f}" x2="{width-pad}" y2="{yy:.1f}" stroke="#e5e7eb"/>')
        parts.append(f'<text x="{pad-8}" y="{yy+4:.1f}" text-anchor="end" fill="#6b7280">{y:.0f}</text>')

    # x 轴刻度
    for x in xs:
        parts.append(f'<text x="{px(x):.1f}" y="{height-pad+22}" text-anchor="middle" '
                     f'fill="#6b7280">{x:.0f}</text>')

    # 折线
    for idx, (key, label) in enumerate(series):
        pts = " ".join(f"{px(float(r[x_key])):.1f},{py(float(r[key])):.1f}" for r in rows)
        color = colors[idx % len(colors)]
        parts.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="2.5"/>')
        for r in rows:
            parts.append(f'<circle cx="{px(float(r[x_key])):.1f}" cy="{py(float(r[key])):.1f}" '
                         f'r="3.5" fill="{color}"/>')
        # 图例
        ly = pad + 18 * idx
        parts.append(f'<rect x="{width-pad-150}" y="{ly-10}" width="14" height="10" fill="{color}"/>')
        parts.append(f'<text x="{width-pad-130}" y="{ly}" fill="#374151">{label}</text>')

    parts.append(f'<text x="{width/2}" y="{height-18}" text-anchor="middle" fill="#6b7280">{x_label}</text>')
    parts.append(f'<text x="20" y="{height/2}" text-anchor="middle" fill="#6b7280" '
                 f'transform="rotate(-90 20 {height/2})">{y_label}</text>')
    parts.append("</svg>")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print("wrote", out_path)


def main():
    ngl = read_csv(os.path.join(ROOT, "results", "ngl-sweep.csv"))
    line_chart(
        ngl, "ngl",
        [("pp512_ts", "pp512 (prompt 处理)"), ("tg128_ts", "tg128 (文本生成)")],
        os.path.join(ROOT, "docs", "ngl-sweep.svg"),
        "GPU 层卸载数量 (-ngl) 对推理速度的影响",
        "-ngl（卸载到 GPU 的层数，模型共 28 层）", "tokens/s",
    )


if __name__ == "__main__":
    main()
