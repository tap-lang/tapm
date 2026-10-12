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

需要 tap 编译器在 `PATH` 里（或用完整路径）。在**包根目录**下执行：

```bash
tap run <tapm 仓库路径>/main.tp -- install   # 装依赖
tap run <tapm 仓库路径>/main.tp -- list      # 列出已接上的依赖
tap run <tapm 仓库路径>/main.tp -- help
```

发布后会编译成 `tapm` 二进制，直接 `tapm install` 即可。

## 源码

| 文件 | 内容 |
|---|---|
| `main.tp` | 命令分派 |
| `toml.tp` | TOML 子集解析（扁平点分键表示，绕开 tap 没有 map） |
| `package.tp` | 清单加载、路径拼接 |
| `install.tp` | 依赖展开（平铺去重）+ 符号链接 + 锁文件 |

## 设计要点

- **依赖平铺**，不嵌套。tap 没有 ABI、没有 `dyn`，同一个包不需要多版本共存，
  所以平铺是安全的。
- **`packages/<名字>` 的目录名必须等于清单里的 `name`**。这是和编译器之间的契约：
  编译器只按目录名解析，不读清单。
- **符号链接优先**（本地改动实时生效）。Windows 上创建符号链接需要管理员权限或
  开启开发者模式。

完整的包管理规范见 tap 仓库的 `docs/package.md`。

## 状态

阶段 1（本地 path 依赖）可用，端到端跑通。

还没做：

- 锁文件的 `version` 字段是空的（读依赖版本的代码会段错误，见 `install.tp` 的 TODO）
- `add` / `remove` / `update` 命令
- 非 path 依赖（注册表版本号）
- 符号链接失败时回退到复制
- `tapm` 需要从包根目录运行，不向上找
