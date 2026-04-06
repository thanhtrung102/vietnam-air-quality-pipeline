# lambda/streaming — OpenAQ Streaming Producer

Fetches latest readings from the OpenAQ v3 REST API for all 21 Vietnamese
stations and publishes them to the Kinesis Data Stream `openaq_stream`.

---

## IoT Lens Gap Fixes

### Gap 2 — Secrets Manager (API key)

The Lambda reads the OpenAQ API key from AWS Secrets Manager at cold start
and caches it for the container lifetime:

1. Reads `OPENAQ_SECRET_NAME` env var to find the secret name
2. Calls `secretsmanager:GetSecretValue` via boto3
3. Falls back to `OPENAQ_API_KEY` env var if Secrets Manager is unavailable
   or returns the placeholder `"REPLACE_ME"` value

**Post-deploy:** inject the real key once:
```bash
aws secretsmanager put-secret-value \
    --secret-id openaq/api_key \
    --secret-string "YOUR_REAL_OPENAQ_API_KEY"
```

### Gap 3 — Ingestion-time validation (two-phase rollout)

`_validate_reading(value, parameter)` checks each reading before it is
appended to the Kinesis payload. Invalid readings emit a CloudWatch metric
`ValidationRejections` (namespace: `OpenAQ/Pipeline`, dimension: `parameter`).

**Phase A — log-and-pass** (`VALIDATION_BLOCK=false`, default):
- Invalid readings are logged and metricked but still forwarded to Kinesis
- Run for at least 2 weeks to establish baseline rejection rates
- Validate that rejection counts match historical sentinel/outlier counts

**Phase B — log-and-block** (`VALIDATION_BLOCK=true`):
- Invalid readings are dropped before Kinesis `PutRecord`
- Switch by updating the Lambda env var: `VALIDATION_BLOCK = true`

Validation rules:
| Rule | Reason |
|------|--------|
| `value == -999.0` | Sentinel for missing readings |
| `value < 0` | Physically impossible concentration |
| `value >= 500` | Implausible for any ambient pollutant at hourly resolution |
| `parameter not in known set` | Unknown parameter — likely API schema change |

Known parameters: `pm25`, `pm10`, `no2`, `o3`, `co`, `so2`, `temperature`,
`relativehumidity`, `um003`, `pm1`.

### Gap 4 — Retry with exponential backoff

`_api_get()` wraps all OpenAQ API calls with retry logic:
- Max 3 retries
- Base delay 5s, doubles per attempt, capped at 20s
- Retries on: HTTP 429 (rate limit), HTTP 5xx (server errors)
- Immediate failure (no retry) on: HTTP 400/401/403/404 (client errors)
