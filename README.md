# tapm

[tap](https://github.com/) 的依赖管理器，用 tap 自己写。

## 它做什么

读项目根目录的 `package.toml`，把依赖接进 `packages/`，并写一份 `package.lock.toml`。

项目布局约定：

```text
myapp/
├─ package.toml          name / version / entry
├─ src/                  本包源码
└─ packages/             依赖（tapm install 生成，不进版本控制）
```

`package.toml`：

```toml
[package]
name = "myapp"
version = "0.1.0"
entry = "src/main.tp"

[dependencies]
bar = { path = "../bar" }
```

`tapm install` 会把 `packages/bar` 做成指向 `../bar` 的**符号链接**（相对链接，
本地改动实时生效），之后 `tap build` 就能通过 `import bar.lib` 找到它。

## 怎么用

需要 tap 编译器在 `PATH` 里（或用完整路径）。**在目标项目的包根目录**下执行：

```bash
tap run <tapm 仓库路径>/src/main.tp -- install   # 装依赖
tap run <tapm 仓库路径>/src/main.tp -- list      # 列出已接上的依赖
tap run <tapm 仓库路径>/src/main.tp -- help
```

发布后会编译成 `tapm` 二进制，装到 `PATH` 里直接 `tapm install` 即可。

## tapm 自己也是一个 tap 包

它遵守自己推行的那套约定：

```text
tapm/
├─ package.toml          name = "tapm", entry = "src/main.tp"
├─ src/                  main.tp / toml.tp / package.tp / install.tp
└─ packages/             依赖（tapm 没有依赖，所以为空，不进版本控制）
```

所以在 tapm 自己的目录里可以直接用**包模式**（不带文件参数）：

```bash
cd <tapm 仓库路径>
tap run -- help          # 等价于 tap run src/main.tp -- help
tap build                # 产物在 build/tapm
```

因为它是个包，别人也能 `import tapm.toml` 这样按包边界导入它的模块。

## 源码

| 文件 | 内容 |
|---|---|
| `src/main.tp` | 命令分派 |
| `src/toml.tp` | TOML 子集解析（扁平点分键表示，绕开 tap 没有 map） |
| `src/package.tp` | 清单加载、路径拼接 |
| `src/install.tp` | 依赖展开（平铺去重）+ 符号链接 + 锁文件 |

## 设计要点

- **依赖平铺**，不嵌套。tap 没有 ABI、没有 `dyn`，同一个包不需要多版本共存，
  所以平铺是安全的。
- **`packages/<名字>` 的目录名必须等于清单里的 `name`**。这是和编译器之间的契约：
  编译器只按目录名解析，不读清单。
- **符号链接优先**（本地改动实时生效）。Windows 上创建符号链接需要管理员权限或
  开启开发者模式。

## 文档

- [docs/design.md](docs/design.md) —— 完整的包管理设计规范：目录布局、清单格式、
  锁文件、分阶段计划、**设计决定记录（含被否方案和理由）**、已知限制、还没做的事。

tap 编译器那一侧的包相关行为（模块解析顺序、包边界规则、`entry` 读取、`tap build` /
`tap run` 包模式）记在 tap 仓库的 `docs/module.md`。

## 状态

阶段 1（本地 path 依赖）可用，端到端跑通。

还没做：

- 锁文件的 `version` 字段是空的（读依赖版本的代码会段错误，见 `install.tp` 的 TODO）
- `add` / `remove` / `update` 命令
- 非 path 依赖（注册表版本号）
- 符号链接失败时回退到复制
- `tapm` 需要从包根目录运行，不向上找
