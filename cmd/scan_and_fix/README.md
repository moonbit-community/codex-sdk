# scan_and_fix - MoonBit Project Scanner and Fixer

这个工具可以扫描指定目录中的所有 MoonBit 项目（仅检查深度为1的子目录），并使用 AI 自动修复编译警告和错误。

## 功能特性

- 自动扫描目录中的 MoonBit 项目
- 识别编译警告和错误
- 使用 AI 智能修复问题
- 每次修复后自动运行测试验证
- 自动提交修复到 git 仓库
- 支持多个项目批量处理

## 使用方法

```bash
# 扫描当前目录下的所有 MoonBit 项目
moon run scan_and_fix

# 扫描指定目录
moon run scan_and_fix -- /path/to/projects

# 设置最大迭代次数
moon run scan_and_fix -- --max-iterations 10

# 干运行模式（不实际执行修复）
moon run scan_and_fix -- --dry-run

# 显示帮助信息
moon run scan_and_fix -- --help
```

## 参数说明

- `DIRECTORY`: 要扫描的目录路径（默认为当前目录）
- `--target-dir <path>`: 指定要扫描的目录
- `--max-iterations <num>`: 每个项目的最大修复迭代次数（默认：5）
- `--dry-run`: 仅显示将要执行的操作，不实际修复
- `-h, --help`: 显示帮助信息

## 工作流程

1. **扫描项目**: 在指定目录中查找所有包含 `moon.mod.json` 的子目录
2. **检查问题**: 对每个项目运行 `moon check` 识别警告和错误
3. **AI 修复**: 使用 Codex AI 智能修复问题
4. **验证修复**: 运行 `moon check` 和 `moon test` 验证修复效果
5. **格式化代码**: 运行 `moon info` 和 `moon fmt` 更新接口并格式化代码
6. **提交变更**: 如果是 git 仓库，自动提交修复的变更
7. **重复处理**: 继续处理下一个项目

## 示例

```bash
# 处理 workspace 目录下的所有项目
moon run scan_and_fix -- /workspace/moonbit-projects

# 快速预览会处理哪些项目
moon run scan_and_fix -- /workspace/moonbit-projects --dry-run
```

## 注意事项

- 工具只扫描深度为1的子目录，不会递归搜索
- 只有包含 `moon.mod.json` 的目录才被认为是 MoonBit 项目
- 如果项目是 git 仓库，修复后会自动提交变更
- 建议在运行前先备份重要代码
- AI 修复可能需要多次迭代才能完全解决所有问题