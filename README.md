# Timesheet & Labor Cost Optimization — Setup Kit

Repeatable setup kit for configuring **Salesforce Field Service Timesheets & Labor Cost Optimization** in any demo org.

## What's Included

| Component | Description |
|---|---|
| `scripts/setup-timesheets.sh` | Automated script — deploys flows, expression sets, configures Pay Types, Cost Rules, OWD sharing, Permission Sets |
| `scripts/TIMESHEET-SETUP-GUIDE.md` | Complete reference guide (manual steps, troubleshooting) |
| `force-app/.../flows/` | **RN_Process_Timesheet** + **RN_Process_Approved_Timesheet** — deployed and activated by the script |
| `force-app/.../expressionSetDefinition/` | **TimesheetEntryItemComputationRule** (critical computation rule) + **SDO_Timesheet_Data_Rules** (pay type time windows) |

## Quick Start

### 1. Complete manual steps first (2 steps)

These cannot be automated via CLI:

1. **Enable Timesheets** — Setup > Field Service Settings > Timesheets section > Enable "Timesheets and Labor Cost Optimization". Set rounding thresholds to 15 min.
2. **Set TimeSheetEntryItem Status default** — Object Manager > Time Sheet Entry Item > Fields > Status > Edit "New" value > Check "Make this value the default" > Save.

### 2. Run the automated script

```bash
# Authenticate to your org
sf org login web --set-default --alias MY_ORG

# Run setup
cd scripts
./setup-timesheets.sh MY_ORG
```

The script handles everything else:
- Deploys **ProcessTimesheet** and **ProcessApprovedTmsht** flows (active)
- Creates/updates **Pay Types** (Regular Time, Over Time, Double Time, Vacation Time)
- Configures **Service Resource Cost Rules** (Compute Time Breakdown, Compute Meals & Gifts)
- Sets **OWD sharing** (TimeSheet, CostCenter, GeolocationBasedAction, JobExpenseType → ReadWrite; SupplementalCompensation → Read)
- Assigns **Permission Sets** (prompts for usernames)
- Deploys **Expression Sets** — TimesheetEntryItemComputationRule (Rank 1, Active) + SDO_Timesheet_Data_Rules
- Runs **verification** queries

### 3. Verify on mobile

1. Open Field Service Mobile App
2. Create a timesheet with time entries
3. Submit — verify Regular Time / Time & Half / Double Time totals appear

## Pay Type Time Windows (SDO Timesheet Data Rules)

| Pay Type | Window | When |
|---|---|---|
| Regular Time | 09:00 – 17:00 | Weekdays |
| Over Time (Time & Half) | 17:00 – 24:00 | Weekdays |
| Double Time | 00:00 – 24:00 | Weekends/Holidays |

## Prerequisites

- Salesforce org with Field Service managed package (FSL / sf_fieldservice)
- `sf` CLI v2.x authenticated to the target org
- Service Resources with Service Territory membership and Operating Hours

## Reference

Based on the internal "Timesheet & Labor Cost Optimization Documentation & Learning Org" guide.
