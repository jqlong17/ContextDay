# Skill：会议纪要 → 飞书（lark-cli）

## 何时用
用户明确要求「写到飞书」「同步纪要到飞书文档/知识库」时。飞书**只用 lark-cli**，不用其他飞书 MCP。

## 前置
- 已用 `meeting-minutes.md` 产出纪要正文（或用户粘贴定稿）
- 目标文档由用户指定，或读本机本地配置中的占位：
  - `{FEISHU_MINUTES_DOC_URL}` 或 `{FEISHU_MINUTES_DOC_TOKEN}`
  - 未配置则先问用户要链接，**不要猜测**

## 流程
1. 预览正文给用户确认（标题、待办列表）  
2. 用户说可以写之后，再用 lark-cli 追加/更新到目标文档  
3. 回传文档链接；失败则保留本地 Markdown，不重试刷屏

## 脱敏
- 模版与仓库内**禁止**写死个人姓名、手机、内部 wiki ID  
- 示例命令形状（参数以本机 `lark-cli` 帮助为准）：

```bash
# 示意：把定稿 Markdown 写入用户指定的文档
lark-cli <subcommand> --doc "{FEISHU_MINUTES_DOC_TOKEN}" --content-file ./minutes-draft.md
```

具体子命令以当前 lark-cli 版本为准；先 `lark-cli --help` / 文档，再执行。
