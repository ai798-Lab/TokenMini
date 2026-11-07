# DeepSeek 项目 / Agent 用量接入

TokenMini 每 60 秒自动读取此目录的 `.jsonl` 用量文件，并将去重后的数字保存到独立账本。
官方余额在监控台单独显示，不用余额差额推算 Token。

把 `tokenmini_deepseek.py` 放在项目可导入的位置，在现有 API 请求完成后加入：

```python
from tokenmini_deepseek import record_response

response = client.chat.completions.create(...)  # 原有 DeepSeek 调用
record_response(response, project="项目简称", session="本次任务编号")
```

流式调用请开启 `stream_options={"include_usage": True}`，并将含有真实 `usage` 的最终 chunk 交给 `record_response`。
不包含 usage 的中间 chunk 不可计量。此辅助文件只处理 Chat Completions 返回字段，不向网络发送请求。

其他语言也可向此目录追加一行 JSON（下列仅为字段说明，不要直接写入示例用量）：

```json
{"id":"真实请求ID","timestamp":"实际请求时间的ISO8601格式","model":"实际模型ID","input":0,"output":0,"cacheRead":0,"cacheWrite":0,"project":"项目简称","session":"任务编号"}
```

`input` 是未命中缓存的输入；`cacheRead` 单独记录缓存命中，二者不能重复。不要再加 reasoning_tokens，它已包含在输出内。
使用真实请求 ID 去重，费用缺省按公开 API 价格估算；只有明确的美元账单费用才可填 `costUSD`。
只写计量信息，不要写提示词、回答、API 密钥或个人目录。

接入前没有保存 usage 的旧请求，无法凭字符数或官方当前余额还原。可以从官方导出有凭据的历史用量再导入。
