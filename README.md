# tapm

[tap](https://github.com/) 的依赖管理器，用 tap 自己写。

## 它做什么

- `tapm new <名字>` —— 按模板生成一个新项目的骨架
- `tapm install` —— 读项目根目录的 `package.toml`，把依赖接进 `packages/`，并写一份
  `package.lock.toml`

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

需要 tap 编译器在 `PATH` 里（或用完整路径）。

```bash
tap run <tapm 仓库路径>/src/main.tp -- new demo    # 新建项目 demo/
cd demo
tap run <tapm 仓库路径>/src/main.tp -- install      # 装依赖（在项目根目录）
tap run <tapm 仓库路径>/src/main.tp -- list         # 列出已接上的依赖
tap run <tapm 仓库路径>/src/main.tp -- help
```

发布后会编译成 `tapm` 二进制，装到 `PATH` 里直接 `tapm new demo` 即可。

## tapm new

`tapm new demo` 在当前目录下建 `demo/`，内容取自 tap 仓库的 `hello` 包：

```text
demo/
├─ package.toml          name = "demo", entry = "src/main.tp"
├─ .gitignore            build/ 和 packages/
├─ README.md
└─ src/main.tp
```

接着就能直接构建：

```bash
cd demo
tap build && ./build/demo     # 或 tap run
```

**`tap new demo` 是它的转发**——参数和退出码原样透传，两者完全等价。编译器按「自己旁边 →
`PATH`」找 tapm，找不到就明确报错。这条只是为了让新人不用先知道有 tapm 这回事；
**构建路径不依赖 tapm**。

两条约束：

- **目标目录已存在就报错，绝不覆盖。** 宁可失败也不要冲掉别人的东西。
- 项目名里不能有路径分隔符（`/`、`\`）或引号——前者会把文件写到目标目录之外，
  后者会破坏生成的 `package.toml`。

**不做 `git init`**：tapm 的定位是「不调用任何外部命令，只操作文件系统」。

## tapm 自己也是一个 tap 包

它遵守自己推行的那套约定：

```text
tapm/
├─ package.toml          name = "tapm", entry = "src/main.tp"
├─ src/                  main.tp / toml.tp / package.tp / install.tp / new.tp
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
| `src/new.tp` | `tapm new`：内嵌的 hello 模板 + 脚手架 |

## 设计要点

- **依赖平铺**，不嵌套。tap 没有 ABI、没有 `dyn`，同一个包不需要多版本共存，
  所以平铺是安全的。
- **`packages/<名字>` 的目录名必须等于清单里的 `name`**。这是和编译器之间的契约：
  编译器只按目录名解析，不读清单。
- **符号链接优先**（本地改动实时生效）。Windows 上创建符号链接需要管理员权限或
  开启开发者模式。

## 测试

```sh
tapm test                        # 全部
TEST_FILTER=new tapm test        # 只跑名字含 new 的用例
TAPM=/path/to/tapm tapm test     # 指定要测的二进制
```

**在包根或任意子目录都能跑**：`install` / `list` / `test` 会从当前目录向上找
`package.toml` 来确定包根（和 cargo 一样），所以 `cd src && tapm test` 也行。

**在包根或任意子目录都能跑**：`install` / `list` / `test` 会从当前目录向上找
`package.toml` 来确定包根（和 cargo 一样），所以 `cd src && tapm test` 也行。

**运行器和用例都是 tap 写的**：

- `src/test.tp` —— 扫描 `tests/cases/*.tp`、给每个用例建独立临时目录、
  用 `tap run` 起进程执行、统计、报告；
- `tests/lib.tp` —— 断言库：`Case` + `expect_*`，链式返回、失败累加（一条用例里的
  多个断言都会跑到，不会第一个失败就停）；
- `tests/cases/*.tp` —— 每个用例一个 tap 程序，`main` 返回 0 表示通过。

```tap
fn main(): i32 {
    let c: Case = lib.case();
    let args: Vec<String> = vec.new<String>();
    args = args.push("new");
    args = args.push("demo");
    c = lib.run(c, env.var("TAPM"), args, ".");
    c = lib.expect_exit(c, 0);
    c = lib.expect_file(c, "demo/package.toml");
    return lib.finish(c);
}
```

**为什么每个用例起独立进程**：用例会 `new` 出目录、改文件系统，进程隔离是最省事的
隔离方式；`import lib` 靠 `TAP_MODULE_PATH` 指向 `tests/`，跑在独立进程里路径不会串。

**为什么不用 tap 自己的 `run-tests.sh`**：那套只比对 stdout/stderr/exit（用例内嵌期望），
而 tapm 的命令会改文件系统——覆盖检查、生成物完整性、manifest 内容都得看文件。

**子进程输出怎么拿**：用 [`process`](../process) 库（`fork` + `poll`），stdout/stderr
直接拿到，不再重定向到 `out.txt`。`process` 是 tapm 的第一个外部依赖 ——
`package.toml` 里声明 `process = { path = "../process" }`，`tapm install` 建符号链接。
临时目录在 `tests/.work/`，跑完即删。

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
