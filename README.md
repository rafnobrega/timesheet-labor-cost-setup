# Timesheet & Labor Cost Optimization — Setup Kit

Repeatable setup kit for configuring **Salesforce Field Service Timesheets & Labor Cost Optimization** in any demo org.

## What's Included

| Component | Description |
|---|---|
| `scripts/setup-timesheets.sh` | Automated script — configures Pay Types, Cost Rules, Permission Sets, Expression Set deployment |
| `scripts/TIMESHEET-SETUP-GUIDE.md` | Complete step-by-step guide (manual + automated steps, troubleshooting) |
| `force-app/.../SDO_Timesheet_Data_Rules` | Expression set defining pay type time windows (Regular, OT, Double Time) |
| `force-app/.../RN_Process_Timesheet` | Record-triggered flow for timesheet submission processing |
| `force-app/.../RN_Process_Approved_Timesheet` | Record-triggered flow for approved timesheet processing |

## Quick Start

### 1. Complete manual steps first

See [`scripts/TIMESHEET-SETUP-GUIDE.md`](scripts/TIMESHEET-SETUP-GUIDE.md) — Part A (Steps A1–A5).

**Critical manual steps:**
- Enable Timesheets & Labor Cost Optimization in Field Service Settings
- Create **"Timesheet Entry Item Computation Rule"** expression set from template
- Create **ProcessTimesheet** and **ProcessApprovedTmsht** flows from templates
- Update Sharing Settings (OWD)

### 2. Run the automated script

```bash
# Authenticate to your org
sf org login web --set-default --alias MY_ORG

# Run setup
cd scripts
./setup-timesheets.sh MY_ORG
```

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
