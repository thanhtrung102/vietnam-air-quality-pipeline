# QuickSight — Disabled

These Terraform files and helper artifacts define an Amazon QuickSight BI layer
(1 Athena data source, 9 SPICE datasets, an analysis, a template, a dashboard,
and a service IAM role) for the air-quality marts.

## Why it is disabled
The target AWS account (703668403514) is on **QuickSight Standard edition**.
The QuickSight *asset-as-code* Terraform resources used here
(`aws_quicksight_data_set`, `aws_quicksight_analysis`, `aws_quicksight_dashboard`,
`aws_quicksight_template`) require **Enterprise edition**. Applying them on a
Standard account fails. The files were moved out of the active module
(`terraform/`) into this directory so the rest of the stack plans/applies cleanly.

The matching outputs in `../outputs.tf` are commented out (see the QuickSight note
near the bottom of that file).

## Files
| File | Purpose |
|---|---|
| `quicksight_iam.tf` | `QuickSightServiceRole-openaq` + Athena/Glue/S3 access policy |
| `quicksight_datasource.tf` | Single ATHENA data source over `openaq_workgroup` |
| `quicksight_datasets.tf` | 9 SPICE datasets (daily_aqi, health_summary, annual_monthly_trend, monthly_profile, diurnal_profile, aq_weather_daily, exceedance_stats, pollutant_ratio, forecast_accuracy) |
| `quicksight_analysis.tf` | `aws_quicksight_analysis` |
| `quicksight_dashboard.tf` | `aws_quicksight_template` + `aws_quicksight_dashboard` |
| `create_analysis.py` | Out-of-band analysis builder script |
| `quicksight_analysis_definition.json` | Exported analysis definition consumed by the script |

## To re-enable (requires QuickSight Enterprise)
1. Subscribe the account to QuickSight **Enterprise** edition.
2. Set `quicksight_admin_email` in `terraform.tfvars`.
3. Move the five `quicksight_*.tf` files back into `terraform/`.
4. Restore the QuickSight `output` block in `terraform/outputs.tf`
   (uncomment the section flagged with the QuickSight note).
5. `terraform plan` / `apply`.
6. Re-add the QuickSight node to `docs/architecture.yaml` if removed.

> The 8 marts that feed only QuickSight (health_summary, exceedance_stats,
> annual_monthly_trend, monthly_profile, diurnal_profile, pollutant_ratio,
> forecast_accuracy, feature_stats) have no other live consumer while QuickSight
> is off — see `docs/DEPLOYED-SPECS-AND-AUDIT.md`.
