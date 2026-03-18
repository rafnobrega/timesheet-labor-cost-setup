#!/bin/bash
# =============================================================================
# Timesheet & Labor Cost Optimization — Automated Setup Script
# =============================================================================
# This script configures the CLI-automatable parts of Timesheets & Labor Cost
# Optimization in a Salesforce org. Run the manual steps in TIMESHEET-SETUP-GUIDE.md
# BEFORE running this script (expression set templates + flows must exist first).
#
# Usage:
#   ./setup-timesheets.sh <org-alias>
#   ./setup-timesheets.sh D25
#
# Prerequisites:
#   - sf CLI authenticated to the target org
#   - Manual steps 1-3 from TIMESHEET-SETUP-GUIDE.md completed
# =============================================================================

set -euo pipefail

# --- Validate input ---
if [ -z "${1:-}" ]; then
  echo "Usage: ./setup-timesheets.sh <org-alias>"
  echo "Example: ./setup-timesheets.sh D25"
  exit 1
fi

ORG="$1"
echo "=== Timesheet & Labor Cost Optimization Setup ==="
echo "Target org: $ORG"
echo ""

# --- Helper: run SOQL and return JSON records ---
query() {
  sf data query --query "$1" --target-org "$ORG" --json 2>/dev/null
}

# --- Helper: extract records from query result ---
get_records() {
  echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('result',{}).get('records',[])))"
}

# --- Helper: get single field value from first record ---
get_field() {
  echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); recs=d.get('result',{}).get('records',[]); print(recs[0]['$2'] if recs else '')"
}

# =============================================================================
# STEP 1: Update Pay Types — set WageType values
# =============================================================================
echo "--- Step 1: Updating Pay Type WageType values ---"

update_pay_type() {
  local name="$1"
  local wage_type="$2"
  local result
  result=$(query "SELECT Id FROM PayType WHERE Name = '$name' LIMIT 1")
  local id
  id=$(get_field "$result" "Id")
  if [ -n "$id" ]; then
    sf data update record --sobject PayType --record-id "$id" --values "WageType=$wage_type" --target-org "$ORG" --json >/dev/null 2>&1
    echo "  Updated '$name' -> WageType=$wage_type"
  else
    echo "  WARNING: Pay Type '$name' not found. Create it manually."
  fi
}

update_pay_type "Regular Time" "RegularTime"
update_pay_type "Over Time" "TimeAndAHalf"
update_pay_type "Double Time" "DoubleTime"
update_pay_type "Vacation Time" "TimeAndAHalf"
echo ""

# =============================================================================
# STEP 2: Create/Update Service Resource Cost Rules
# =============================================================================
echo "--- Step 2: Configuring Service Resource Cost Rules ---"

# Check if "Compute Time Breakdown" exists
BREAKDOWN_RESULT=$(query "SELECT Id FROM ServiceResourceCostRule WHERE Name = 'Compute Time Breakdown' LIMIT 1")
BREAKDOWN_ID=$(get_field "$BREAKDOWN_RESULT" "Id")

if [ -n "$BREAKDOWN_ID" ]; then
  echo "  Found 'Compute Time Breakdown' ($BREAKDOWN_ID) — updating..."
  sf data update record --sobject ServiceResourceCostRule --record-id "$BREAKDOWN_ID" \
    --values "Type=TimesheetEntryItemCalculation Rule=TimesheetEntryItemComputationRule StandardApexClass=ifstmsht.TimeSheetEntryItemRuleDataHandler IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
  echo "  Updated: Type=TimesheetEntryItemCalculation, Rule=TimesheetEntryItemComputationRule, StandardApexClass=ifstmsht.TimeSheetEntryItemRuleDataHandler"
else
  echo "  'Compute Time Breakdown' not found — creating..."
  sf data create record --sobject ServiceResourceCostRule \
    --values "Name='Compute Time Breakdown' Type=TimesheetEntryItemCalculation Rule=TimesheetEntryItemComputationRule StandardApexClass=ifstmsht.TimeSheetEntryItemRuleDataHandler IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
  echo "  Created 'Compute Time Breakdown'"
fi

# Check if "Compute Meals & Gifts" exists
MEALS_RESULT=$(query "SELECT Id FROM ServiceResourceCostRule WHERE Name = 'Compute Meals & Gifts' LIMIT 1")
MEALS_ID=$(get_field "$MEALS_RESULT" "Id")

if [ -n "$MEALS_ID" ]; then
  echo "  Found 'Compute Meals & Gifts' ($MEALS_ID) — updating..."
  sf data update record --sobject ServiceResourceCostRule --record-id "$MEALS_ID" \
    --values "Type=MealCalculation Rule=TimesheetMealsAndGiftsComputationRule IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
  echo "  Updated: Type=MealCalculation, Rule=TimesheetMealsAndGiftsComputationRule"
else
  echo "  'Compute Meals & Gifts' not found — creating..."
  sf data create record --sobject ServiceResourceCostRule \
    --values "Name='Compute Meals & Gifts' Type=MealCalculation Rule=TimesheetMealsAndGiftsComputationRule IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
  echo "  Created 'Compute Meals & Gifts'"
fi
echo ""

# =============================================================================
# STEP 3: Assign Permission Sets
# =============================================================================
echo "--- Step 3: Assigning Permission Sets ---"
echo "  Enter usernames to assign Labor Cost Optimization permission sets."
echo "  (Leave blank to skip)"
echo ""

read -r -p "  Supervisor username (e.g., admin@example.com): " SUPERVISOR_USER
read -r -p "  Resource username (e.g., tech@example.com): " RESOURCE_USER

assign_permset() {
  local permset="$1"
  local user="$2"
  if [ -n "$user" ]; then
    sf force user permset assign --permsetname "$permset" --onbehalfof "$user" --target-org "$ORG" --json >/dev/null 2>&1 && \
      echo "  Assigned $permset to $user" || \
      echo "  $permset already assigned to $user (or user not found)"
  fi
}

if [ -n "$SUPERVISOR_USER" ]; then
  assign_permset "LaborCostOptimAdmin" "$SUPERVISOR_USER"
  assign_permset "LaborCostOptimSupervisor" "$SUPERVISOR_USER"
fi

if [ -n "$RESOURCE_USER" ]; then
  assign_permset "LaborCostOptimResource" "$RESOURCE_USER"
fi

# If supervisor and resource are different, also give supervisor to resource user
if [ -n "$RESOURCE_USER" ] && [ -n "$SUPERVISOR_USER" ] && [ "$RESOURCE_USER" != "$SUPERVISOR_USER" ]; then
  assign_permset "LaborCostOptimResource" "$SUPERVISOR_USER"
fi

echo ""

# =============================================================================
# STEP 4: Deploy SDO Timesheet Data Rules expression set
# =============================================================================
echo "--- Step 4: Deploying SDO Timesheet Data Rules expression set ---"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$PROJECT_DIR/manifest/package.xml"

# Check if the expression set metadata exists locally
EXPR_SET_FILE="$PROJECT_DIR/force-app/main/default/expressionSetDefinition/SDO_Timesheet_Data_Rules.expressionSetDefinition-meta.xml"

if [ -f "$EXPR_SET_FILE" ]; then
  echo "  Found local expression set metadata — deploying..."
  sf project deploy start \
    --source-dir "$PROJECT_DIR/force-app/main/default/expressionSetDefinition" \
    --target-org "$ORG" --json >/dev/null 2>&1 && \
    echo "  Deployed SDO_Timesheet_Data_Rules successfully" || \
    echo "  WARNING: Deployment failed. Deploy manually or check the expression set in the org."
else
  echo "  WARNING: SDO_Timesheet_Data_Rules metadata not found locally."
  echo "  You may need to create it from the Timesheet Data Rules template in the org."
fi

# Update UsageType to Timesheet via Tooling API
echo "  Setting UsageType to Timesheet..."
ACCESS_TOKEN=$(sf org display --target-org "$ORG" --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['accessToken'])")
INSTANCE_URL=$(sf org display --target-org "$ORG" --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['instanceUrl'])")

EXPR_ID=$(curl -s "${INSTANCE_URL}/services/data/v62.0/tooling/query/?q=SELECT+Id+FROM+ExpressionSetDefinition+WHERE+DeveloperName='SDO_Timesheet_Data_Rules'" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['records'][0]['Id'] if d.get('records') else '')" 2>/dev/null)

if [ -n "$EXPR_ID" ]; then
  curl -s -X PATCH "${INSTANCE_URL}/services/data/v62.0/tooling/sobjects/ExpressionSetDefinition/${EXPR_ID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"Metadata":{"processType":"Timesheet","label":"SDO Timesheet Data Rules","template":false}}' >/dev/null 2>&1 && \
    echo "  Set processType to Timesheet" || \
    echo "  WARNING: Could not update processType. Set it manually in the expression set."
fi
echo ""

# =============================================================================
# STEP 5: Verification
# =============================================================================
echo "--- Step 5: Verification ---"

echo "  Pay Types:"
query "SELECT Name, WageType, IsActive FROM PayType ORDER BY Name" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('result',{}).get('records',[]):
    print(f'    {r[\"Name\"]}: WageType={r.get(\"WageType\")}, Active={r[\"IsActive\"]}')
" 2>/dev/null

echo "  Cost Rules:"
query "SELECT Name, Type, Rule, StandardApexClass, IsActive FROM ServiceResourceCostRule ORDER BY Name" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('result',{}).get('records',[]):
    print(f'    {r[\"Name\"]}: Type={r[\"Type\"]}, Rule={r[\"Rule\"]}, StdApex={r.get(\"StandardApexClass\",\"—\")}, Active={r[\"IsActive\"]}')
" 2>/dev/null

echo ""
echo "=== Automated setup complete ==="
echo ""
echo "IMPORTANT: Complete the remaining manual steps in TIMESHEET-SETUP-GUIDE.md"
echo "  - Sharing settings (OWD)"
echo "  - Field Service Settings toggle"
echo "  - Default picklist values"
echo "  - Page layout actions (optional)"
