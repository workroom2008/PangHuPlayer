# [功能名] 实施计划

> **执行者须知**：按任务逐条执行，步骤用 `- [ ]` 勾选跟踪。
> 每个任务独立完成自己的测试循环；不要跳步骤、不要「顺手优化」。

**Goal：** [一句话说明要构建什么]

**Architecture：** [2-3 句说明方案与技术路线]

**Tech Stack：** [关键技术/库，如 flutter_riverpod、drift、shared_preferences]

**Spec：** [设计文档路径；本计划从 spec 推导，执行者需同时阅读]

## Global Constraints

- [spec 中的项目级硬约束，每行一条，值照抄：版本下限、依赖限制、命名/文案规则、平台要求]

---

## Task 1: [组件名]

**Files：**
- Create: `lib/.../xxx.dart`
- Modify: `lib/.../yyy.dart:120-135`（给出行号）
- Test: `test/xxx_test.dart`

**Interfaces：**
- Consumes：[本任务使用的前置任务接口——精确签名]
- Produces：[后续任务依赖的接口——精确函数名、参数、返回类型]

- [ ] **Step 1: 写失败测试**
  ```dart
  // 完整测试代码
  ```
- [ ] **Step 2: 跑测试确认失败**
  命令：`HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test test/xxx_test.dart`
  期望：FAIL，报 `xxx 未定义`（功能缺失，非笔误）
- [ ] **Step 3: 写最小实现**
  ```dart
  // 完整实现代码
  ```
- [ ] **Step 4: 跑测试确认通过**
  同上命令。期望：PASS
- [ ] **Step 5: 提交**
  ```bash
  git add test/xxx_test.dart lib/...
  git commit -m "feat: ..."
  ```

---

## Task N: [下一个组件]

（结构同上。注意：**不要写** "Similar to Task 1"——执行者可能乱序读任务，代码必须完整重复。）

---

## 计划自查（写完计划后执行）

- [ ] spec 每条需求都能指向一个任务？
- [ ] 全文无占位符（TBD / TODO / "handle edge cases" / "类似 Task N"）？
- [ ] 后置任务引用的函数名/签名与前置任务定义一致？
