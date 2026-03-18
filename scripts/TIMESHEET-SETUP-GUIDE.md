# Timesheet & Labor Cost Optimization — Setup Guide

Complete setup for Salesforce Field Service Timesheets & Labor Cost Optimization.
Estimated time: ~15 minutes (manual steps) + ~2 minutes (script).

---

## Prerequisites

- Field Service managed package installed (FSL / sf_fieldservice)
- `sf` CLI authenticated to the target org
- At least one Service Resource with a Service Territory membership
- Operating Hours configured on the Service Territory

---

## Order of Operations

```
1. Manual Steps (UI)        ← Do these FIRST
2. Run setup script (CLI)   ← Automates data/config
3. Verification (Mobile)    ← Test on Field Service Mobile
```

---

## PART A: Manual Steps (Setup UI)

### A1. Enable Timesheets & Labor Cost Optimization

1. Setup > Search "Field Service Settings"
2. Go to the **Timesheets** section (or "Advanced Timesheets and Labor Cost Optimization Settings")
3. Enable **Timesheets and Labor Cost Optimization**
4. Set **Start Time Rounding Threshold** = 15 min
5. Set **End Time Rounding Threshold** = 15 min
6. Save

### A2. Create Flows from Templates

Go to **Setup > Flows** and create a new flow from each template below.
For each: click the template > Save As > enter a name > Save > **Activate**.

| Template Name | Your Flow Name (suggestion) | Type | Required? |
|---|---|---|---|
| ProcessTimesheet | Process_Timesheet | Record-Triggered | **YES** |
| ProcessApprovedTmsht | Process_Approved_Timesheet | Record-Triggered | **YES** |
| ApproveTimeSheets | Approve_Time_Sheets | Screen | For demo |
| ApproveTimeSheetEntries | Approve_Time_Sheet_Entries | Screen | For demo |
| ApproveTimeSheetEntryItem | Approve_Time_Sheet_Entry_Items | Screen | For demo |
| RejectTimeSheets | Reject_Time_Sheets | Screen | For demo |
| RejectTimeSheetEntries | Reject_Time_Sheet_Entries | Screen | For demo |
| RejectTimeSheetEntryItems | Reject_Time_Sheet_Entry_Items | Screen | For demo |
| CreateAbsnTimeSheetEntry | Create_Absence_TSE | Record-Triggered | Optional |
| RemoveAbsnTimeSheetEntry | Remove_Absence_TSE | Record-Triggered | Optional |

**Minimum required:** ProcessTimesheet + ProcessApprovedTmsht

### A3. Create Expression Sets from Templates

Go to **App Launcher > Expression Set Templates**.

| Template Name | Rank | Required? |
|---|---|---|
| **Timesheet Entry Item Computation Rule** | 1 | **YES — this is critical** |
| Timesheet Meals And Gifts Computation Rule | 1 | For meal computation |
| Timesheet Vehicle Validation Rule | 1 | Optional |

For each: Click the template > Set Rank = 1 > **Save and Activate**.

### A4. Sharing Settings (OWD)

Go to **Setup > Sharing Settings** and set:

| Object | Internal Access |
|---|---|
| Time Sheet | Public Read/Write |
| Cost Center | Public Read/Write |
| Geolocation Based Action | Public Read/Write |
| Job Expense Type | Public Read/Write |
| Supplemental Compensation | Public Read Only |

### A5. Default Picklist Values

Go to **Setup > Object Manager** and set "New" as the default status for:

| Object | Field | Default Value |
|---|---|---|
| Time Sheet | Status | New |
| Time Sheet Entry | Status | New |
| Time Sheet Entry Item | Status | New |

For each: Object Manager > [Object] > Fields & Relationships > Status > Edit "New" value > Check "Make this value the default for the master picklist" > Save

---

## PART B: Run the Automated Script

After completing all manual steps above:

```bash
cd D25/scripts
./setup-timesheets.sh <org-alias>
```

The script will:
- Update Pay Type WageType values (RegularTime, TimeAndAHalf, DoubleTime)
- Create/update Service Resource Cost Rules (Compute Time Breakdown, Compute Meals & Gifts)
- Assign permission sets (prompts for usernames)
- Deploy SDO_Timesheet_Data_Rules expression set
- Set expression set UsageType to Timesheet
- Print verification summary

---

## PART C: Page Layouts & Actions (Optional — for full demo)

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

## PART D: Verification

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
| 0h 0m for all totals | Missing "Timesheet Entry Item Computation Rule" expression set | Create from template (Step A3) |
| Stuck at "Validation In Progress" | Missing StandardApexClass on cost rule | Run setup script (sets ifstmsht.TimeSheetEntryItemRuleDataHandler) |
| "Start/end time doesn't match" error | TimeSheet boundaries don't align with entries | Ensure first entry start = TS start, last entry end = TS end |
| All hours show as Regular Time | Operating Hours define full day as regular | Adjust Operating Hours timeslots for OT windows |
| No Time Sheet Entry Items object | Feature not enabled | Enable in Field Service Settings (Step A1) |
