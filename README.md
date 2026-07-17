# post_resource

產生明顯可辨識的假 FHIR Patient 測試資料,並可選擇性 POST 到 FHIR server,給部署環境測試用。

## 需求

- bash + `jq`
- 部署環境沒裝 `jq` 也沒關係：找不到系統 `jq` 時,腳本會自動退回 [vendor/jq-linux-amd64](vendor/jq-linux-amd64)（官方靜態二進制檔,已核對 sha256,見 [vendor/jq-linux-amd64.sha256](vendor/jq-linux-amd64.sha256)）。目前只 vendor 了 linux-amd64,如果部署環境是其他平台（例如 ARM64）需另外準備對應版本。
- `bin/post` 另外需要 `curl`

## 產生假資料

```bash
./bin/generate [--template <path>] [--count <N>] [--out <dir>]
```

| 參數 | 說明 | 預設 |
|---|---|---|
| `--template` | Patient 模板路徑 | `data/template.json` |
| `--count` | 產生幾筆 | 1 |
| `--out` | 輸出目錄 | `./output` |

每次執行會依 [data/field-map.json](data/field-map.json) 定義的欄位,從 [data/fake-pools/](data/fake-pools/) 抽假資料填回模板,輸出成 `pat-fake-001.json`、`pat-fake-002.json`...。

## POST 到 FHIR server

```bash
./bin/post --url <FHIR base URL> [--dir <output dir>] [--resource-type <type>] [--token <bearer token>]
```

| 參數 | 說明 | 預設 |
|---|---|---|
| `--url` | FHIR server base URL（也可用 `FHIR_BASE_URL` 環境變數） | 必填 |
| `--dir` | 要 POST 的 JSON 檔案目錄 | `./output` |
| `--resource-type` | resource 類型,決定 POST 到哪個 endpoint | `Patient` |
| `--token` | Bearer token,帶了才會加 `Authorization` header（也可用 `FHIR_TOKEN` 環境變數） | 無 |

`--url` 結尾要不要加 `/` 都可以,腳本會自動處理（`http://host/fhir` 和 `http://host/fhir/` 都會接成 `http://host/fhir/Patient`）。但 `http://`／`https://` 這段**建議明確帶上**,不要省略——雖然 curl 在沒給 scheme 時會預設補成 `http://`,但那是 curl 的實作細節而不是這支腳本保證的行為,漏寫容易在該用 `https` 的地方誤送明文請求。

會把目錄裡每個 `.json` 逐一 POST 過去,印出每筆的 HTTP status;有任何一筆失敗（非 2xx）會印出 response body,並在結束時以非 0 exit code 回報。

**目前只支援單一 resource type、沒有 reference 依賴的情境**（例如單獨的 Patient）。如果之後要 POST 有依賴關係的 resource（Encounter 需要 Patient 的真實 id 才能建),要另外處理「先 POST 拿到 id、再帶入下一個 resource」的邏輯,目前還沒做。

## 假資料的設計

假資料刻意做得一眼就看得出是測試資料,而非長得像真人：

- **姓名**：固定用「測試」當名字,姓氏隨機（[data/fake-pools/names.txt](data/fake-pools/names.txt)），英文名字音譯照翻（[data/fake-pools/given-names.txt](data/fake-pools/given-names.txt)）
- **地址**：路名固定是「測試路」「測試街」等假路名（[data/fake-pools/addresses.tsv](data/fake-pools/addresses.tsv)），樓層、門牌號碼隨機產生；行政區與郵遞區號維持真實對應,因為 TW Core 的 `postal-code3-tw` 是真實存在的 FHIR CodeSystem,亂填會驗證失敗
- **身分證字號**：格式為 1 碼英文字母 + 9 碼數字,第二碼是性別碼（1 男 / 2 女),跟同一筆資料的 `Patient.gender` 保證一致;不追求符合真實檢查碼演算法
- **緊急聯絡人關係**：`FTH`（父親）／`MTH`（母親）隨機

## 自訂欄位對應

[data/field-map.json](data/field-map.json) 定義「模板裡的哪個欄位 → 用哪種假資料類型」,`path` 是 jq 的路徑表達式（可以是任意深度的巢狀路徑）,`type` 對應 [scripts/substitute.sh](scripts/substitute.sh) 裡 `resolve_value()` 認得的類型。要新增欄位替換,加一筆 `{ "path": ..., "type": ... }`,並確認 `resolve_value()` 有處理該 `type` 即可。

## 目錄結構

```
post_resource/
├── bin/
│   ├── generate           # 產生假資料
│   └── post                # POST 到 FHIR server
├── data/
│   ├── template.json       # FHIR Patient 模板
│   ├── field-map.json      # 欄位 → 假資料類型對應表
│   └── fake-pools/         # 各類假資料池
├── scripts/
│   └── substitute.sh       # 核心替換邏輯
└── vendor/
    └── jq-linux-amd64      # 離線環境用的 jq 靜態二進制檔
```
