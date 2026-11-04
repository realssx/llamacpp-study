# llama.cpp 推理性能研究

[![CI](https://github.com/realssx/llamacpp-study/actions/workflows/ci.yml/badge.svg)](https://github.com/realssx/llamacpp-study/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 计算机开源实践与创新 · 课程项目

📄 [阶段性进度报告](docs/03-进度报告.md) · 🔧 [环境搭建记录](docs/01-环境搭建.md) · 📖 [源码阅读笔记](docs/02-源码阅读笔记.md)

## 一、项目背景

llama.cpp 是用 C/C++ 实现的 LLM 推理引擎，支持在本地 CPU/GPU 上运行量化后的 GGUF 模型。
它在 GitHub 上有 6 万+ star，被大量桌面端、嵌入式、边缘设备项目用作推理后端。

本项目以 **llama.cpp 的推理性能**为研究对象，围绕三个问题展开：

1. 不同量化等级（Q4_K_M / Q5_K_M / Q8_0）对推理速度和显存占用的影响
2. CPU 后端与 CUDA 后端在同一模型上的性能差异
3. 上下文长度、批大小等参数对 tokens/s 的影响

项目目标：产出一份可复现的 benchmark 报告 + 一篇技术白皮书，并向上游提交至少 1 个 PR。

## 二、实验环境

| 项 | 配置 |
|---|---|
| CPU | Intel Core i7-14650HX |
| GPU | NVIDIA GeForce RTX 4060 Laptop (8 GB) |
| 内存 | 16 GB |
| 系统 | Windows 11 |
| llama.cpp | b11960（预编译 CUDA 版），后续自编译 |
| 模型 | Qwen2.5-1.5B-Instruct GGUF（Q4_K_M / Q5_K_M / Q8_0） |

## 三、目录结构

```
llamacpp-study/
├── README.md              # 本文件：项目说明与计划
├── docs/
│   ├── 01-环境搭建.md      # 环境步骤与踩坑记录
│   └── 02-源码阅读笔记.md   # ggml / llama.cpp 架构阅读
├── scripts/
│   └── bench.ps1          # 一键跑 benchmark 并记录
└── results/
    ├── benchmark.csv      # 汇总数据
    └── raw/               # 每次运行的原始输出
```

## 四、阶段计划

| 周次 | 目标 | 产出 |
|---|---|---|
| 1–2 | 环境搭建，跑通 qwen2.5-1.5b（Q4_K_M） | 环境文档、首跑截图 |
| 3–4 | 三个量化等级 × CPU/CUDA 对比 benchmark | benchmark.csv |
| 5–6 | 读 ggml 张量结构与 llama.cpp 推理主流程 | 架构图、阅读笔记 |
| 7–8 | 提交第一个 PR（文档 / 模型支持 / 小 bug） | PR 链接 |
| 9–12 | 做一个具体改进，写设计文档 | 代码 + 设计文档 |
| 13–16 | 整理结题材料 | 报告 + 答辩 PPT |

## 四半、阶段性结果（2026-11-03）

模型：Qwen2.5-1.5B-Instruct；参数：`-p 512 -n 128 -r 3`
硬件：RTX 4060 Laptop 8GB / i7-14650HX / 16GB

| 量化 | 后端 | pp512 (t/s) | tg128 (t/s) | 相对 CPU 加速 |
|---|---:|---:|---:|---:|
| Q4_K_M | CUDA | 9068.4 | **185.7** | 5.3× |
| Q4_K_M | CPU (16 线程) | 2882.4 | 35.3 | 1× |
| Q5_K_M | CUDA | 9395.4 | 162.7 | 5.4× |
| Q5_K_M | CPU (16 线程) | 2612.9 | 30.1 | 1× |
| Q8_0 | CUDA | 10608.7 | 128.2 | 6.0× |
| Q8_0 | CPU (16 线程) | 2072.6 | 21.4 | 1× |

初步结论：

1. **GPU 生成速度约为 CPU 的 5–6 倍**，prompt 处理差距更大（3–5 倍）。
2. **量化越低，GPU 生成越快**（Q4 185.7 > Q5 162.7 > Q8 128.2），符合显存带宽瓶颈的预期；
   但 prompt 处理（计算密集）反而 Q8 最高，说明两者瓶颈不同：
   生成受内存带宽限制，prompt 处理受算力限制。
3. CPU 端量化同样呈现 "低比特更快" 的趋势。

待复查：早期用 MinGW 编译的 CPU 版 tg128 只有 10.4 t/s，MSVC 版是 35.3 t/s，
差 3.4 倍；需要确认是编译器代码生成差异，还是当时机器的功耗/负载状态影响。

## 五、数据记录约定

每次 benchmark 都通过 `scripts/bench.ps1` 执行，原始输出存 `results/raw/`，
汇总行追加到 `results/benchmark.csv`。

字段说明：

| 字段 | 含义 |
|---|---|
| date | 运行时间 |
| model | 模型文件（含量化等级） |
| backend | cpu / cuda |
| ngl | 卸载到 GPU 的层数（0=纯 CPU，99=全部） |
| pp | prompt 处理 token 数 |
| tg | 生成 token 数 |
| pp_ts | prompt 处理速度 tokens/s |
| tg_ts | 生成速度 tokens/s |
| notes | 备注（温度、线程数、显存等） |
