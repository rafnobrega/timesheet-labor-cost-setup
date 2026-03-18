# Timesheet & Labor Cost Optimization — Setup Guide

Complete setup for Salesforce Field Service Timesheets & Labor Cost Optimization.

---

## Prerequisites

- Field Service managed package installed (FSL / sf_fieldservice)
- `sf` CLI authenticated to the target org
- At least one Service Resource with a Service Territory membership
- Operating Hours configured on the Service Territory

---

## Order of Operations

```
1. Manual Steps (UI)        ← 2 steps, do these FIRST
2. Run setup script (CLI)   ← Automates everything else
3. Verification (Mobile)    ← Test on Field Service Mobile
```

---

## PART A: Manual Steps (2 steps — UI only)

### A1. Enable Timesheets & Labor Cost Optimization

1. Setup > Search "Field Service Settings"
2. Go to the **Timesheets** section (or "Advanced Timesheets and Labor Cost Optimization Settings")
3. Enable **Timesheets and Labor Cost Optimization**
4. Set **Start Time Rounding Threshold** = 15 min
5. Set **End Time Rounding Threshold** = 15 min
6. Save

### A2. Set TimeSheetEntryItem Status Default

Object Manager > **Time Sheet Entry Item** > Fields & Relationships > **Status** > Edit "New" value > Check **"Make this value the default for the master picklist"** > Save.

> **Note:** TimeSheet and TimeSheetEntry already default to "New" in most orgs. This step is only needed for TimeSheetEntryItem.

---

## PART B: Run the Automated Script

After completing the 3 manual steps above:

```bash
cd scripts
./setup-timesheets.sh <org-alias>
```

### What the script automates:

| Step | What It Does |
|---|---|
| **1. Flows** | Deploys RN_Process_Timesheet + RN_Process_Approved_Timesheet (Active) |
| **2. Pay Types** | Creates/updates Regular Time, Over Time, Double Time, Vacation Time with correct WageType values |
| **3. Cost Rules** | Creates/updates Compute Time Breakdown + Compute Meals & Gifts with correct Type, Rule, and StandardApexClass |
| **4. OWD Sharing** | Sets TimeSheet, CostCenter, GeolocationBasedAction, JobExpenseType to ReadWrite; SupplementalCompensation to Read |
| **5. Permission Sets** | Prompts for usernames, assigns LaborCostOptimAdmin/Supervisor/Resource |
| **6. Expression Sets** | Deploys TimesheetEntryItemComputationRule (Rank 1, Active) + SDO_Timesheet_Data_Rules |
| **7. Verification** | Queries Pay Types, Cost Rules, and OWD settings to confirm |

---

## PART C: Add Timesheets to Field Service Mobile App

The Timesheets component is not included in the mobile layout by default and cannot be deployed via metadata. You must add it manually:

1. Setup > Search **"Field Service Mobile App Builder"**
2. Create a new configuration or edit an existing one
3. Add the **LWC Attributes** component
4. Select the **timeSheetLandingPage** LWC
5. Save and publish

> **Note:** Without this step, technicians will not see the Timesheets tab in the Field Service Mobile App.

---

## PART D: Page Layouts & Actions (Optional — for full demo)

### C1. Approve/Reject Actions on Record Pages

For Time Sheet, Time Sheet Entry, and Time Sheet Entry Item:

1. Object Manager > [Object] > Buttons, Links, and Actions > New Action
2. Action Type = Flow, select the Approve/Reject flow
3. Object Manager > [Object] > Page Layout > Mobile & Lightning Actions
4. Override predefined actions and drag the new actions in

### C2. Approve/Reject Buttons on List Views

For bulk approve/reject:

1. Object Manager > [Object] > Buttons, Links, and Actions > New Button or Link
2. Label = "Approve", Display Type = List Button (with checkboxes)
3. Link = `/flow/YOUR_APPROVE_FLOW_API_NAME?retURL=1ts?recent`
4. Object Manager > [Object] > List View Button Layout > Edit > Add button

### C3. Time Sheet Entry Items Related List

1. Object Manager > Time Sheet Entry > Page Layout
2. Add "Time Sheet Entry Items" related list

### C4. Create TSE Actions on Service Appointments

1. Object Manager > Service Appointment > Buttons, Links, and Actions > New Action
2. Action Type = Flow, select "Create Time Sheet Entries on Appointment Start/End"
3. Add to Service Appointment page layout

---

## PART E: Verification

1. Log into Field Service Mobile as a technician
2. Go to Time Sheets > Create a new timesheet for today
3. Add a time entry (e.g., 7:00 AM - 5:00 PM)
4. Submit the timesheet
5. Verify:
   - Status changes to "Approval Pending"
   - Regular Time hours appear in the summary
   - Hourly Breakdown shows work/break time splits
6. For Double Time: create a weekend timesheet
7. For Time & Half: adjust Operating Hours to define overtime windows

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| 0h 0m for all totals | Missing "Timesheet Entry Item Computation Rule" expression set | Create from template (Step A2) |
| Stuck at "Validation In Progress" | Missing StandardApexClass on cost rule | Run setup script (sets ifstmsht.TimeSheetEntryItemRuleDataHandler) |
| "Start/end time doesn't match" error | TimeSheet boundaries don't align with entries | Ensure first entry start = TS start, last entry end = TS end |
| All hours show as Regular Time | Operating Hours define full day as regular | Adjust Operating Hours timeslots for OT windows |
| No Time Sheet Entry Items object | Feature not enabled | Enable in Field Service Settings (Step A1) |
| Expression set deploy conflicts | Expression set already exists from template | Delete the existing one in the org, then re-run the script |
