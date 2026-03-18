#!/bin/bash
# =============================================================================
# Timesheet & Labor Cost Optimization — Automated Setup Script
# =============================================================================
# This script configures Timesheets & Labor Cost Optimization in a Salesforce
# org. Only 3 manual steps are required before running (see README.md).
#
# Usage:
#   ./setup-timesheets.sh <org-alias>
#   ./setup-timesheets.sh KINETIC
#
# Prerequisites:
#   - sf CLI authenticated to the target org
#   - Manual steps completed (see README.md):
#     1. Enable Timesheets in Field Service Settings
#     2. Create expression sets from templates
#     3. Set TimeSheetEntryItem Status default to "New"
# =============================================================================

set -euo pipefail

# --- Validate input ---
if [ -z "${1:-}" ]; then
  echo "Usage: ./setup-timesheets.sh <org-alias>"
  echo "Example: ./setup-timesheets.sh KINETIC"
  exit 1
fi

ORG="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Timesheet & Labor Cost Optimization Setup ==="
echo "Target org: $ORG"
echo ""

# --- Helper: run SOQL and return JSON records ---
query() {
  sf data query --query "$1" --target-org "$ORG" --json 2>/dev/null
}

# --- Helper: get single field value from first record ---
get_field() {
  echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); recs=d.get('result',{}).get('records',[]); print(recs[0]['$2'] if recs else '')"
}

# --- Helper: deploy metadata via MDAPI format ---
mdapi_deploy() {
  local deploy_dir="$1"
  local description="$2"
  local result
  result=$(cd "$deploy_dir" && sf project deploy start --metadata-dir . --target-org "$ORG" --json 2>/dev/null)
  local status
  status=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',{}).get('status','Failed'))")
  if [ "$status" = "Succeeded" ]; then
    echo "  Deployed $description successfully"
    return 0
  else
    local errors
    errors=$(echo "$result" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for f in d.get('result',{}).get('details',{}).get('componentFailures',[]):
    print(f'    {f.get(\"fullName\",\"?\")}: {f.get(\"problem\",\"unknown error\")}')
")
    echo "  WARNING: Failed to deploy $description"
    echo "$errors"
    return 1
  fi
}

# =============================================================================
# STEP 1: Deploy Flows (ProcessTimesheet + ProcessApprovedTmsht)
# =============================================================================
echo "--- Step 1: Deploying Timesheet Flows ---"

FLOW_DIR="$PROJECT_DIR/force-app/main/default/flows"
if [ -d "$FLOW_DIR" ]; then
  (cd "$PROJECT_DIR" && sf project deploy start \
    --source-dir "force-app/main/default/flows" \
    --target-org "$ORG" --json >/dev/null 2>&1) && \
    echo "  Deployed RN_Process_Timesheet and RN_Process_Approved_Timesheet (Active)" || \
    echo "  WARNING: Flow deployment failed. Check API version compatibility."
else
  echo "  WARNING: Flows not found locally at $FLOW_DIR"
fi
echo ""

# =============================================================================
# STEP 2: Update Pay Types — set WageType values
# =============================================================================
echo "--- Step 2: Configuring Pay Types ---"

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
    echo "  Pay Type '$name' not found — creating..."
    sf data create record --sobject PayType --values "Name='$name' WageType=$wage_type IsActive=true EffectiveStartDate=2025-01-01" --target-org "$ORG" --json >/dev/null 2>&1
    echo "  Created '$name' -> WageType=$wage_type"
  fi
}

update_pay_type "Regular Time" "RegularTime"
update_pay_type "Over Time" "TimeAndAHalf"
update_pay_type "Double Time" "DoubleTime"
update_pay_type "Vacation Time" "TimeAndAHalf"
echo ""

# =============================================================================
# STEP 3: Create/Update Service Resource Cost Rules
# =============================================================================
echo "--- Step 3: Configuring Service Resource Cost Rules ---"

# Compute Time Breakdown
BREAKDOWN_RESULT=$(query "SELECT Id FROM ServiceResourceCostRule WHERE Name = 'Compute Time Breakdown' LIMIT 1")
BREAKDOWN_ID=$(get_field "$BREAKDOWN_RESULT" "Id")

if [ -n "$BREAKDOWN_ID" ]; then
  echo "  Found 'Compute Time Breakdown' ($BREAKDOWN_ID) — updating..."
  sf data update record --sobject ServiceResourceCostRule --record-id "$BREAKDOWN_ID" \
    --values "Type=TimesheetEntryItemCalculation Rule=TimesheetEntryItemComputationRule StandardApexClass=ifstmsht.TimeSheetEntryItemRuleDataHandler IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
else
  echo "  Creating 'Compute Time Breakdown'..."
  sf data create record --sobject ServiceResourceCostRule \
    --values "Name='Compute Time Breakdown' Type=TimesheetEntryItemCalculation Rule=TimesheetEntryItemComputationRule StandardApexClass=ifstmsht.TimeSheetEntryItemRuleDataHandler IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
fi
echo "  Configured: Type=TimesheetEntryItemCalculation, StandardApexClass=ifstmsht.TimeSheetEntryItemRuleDataHandler"

# Compute Meals & Gifts
MEALS_RESULT=$(query "SELECT Id FROM ServiceResourceCostRule WHERE Name = 'Compute Meals & Gifts' LIMIT 1")
MEALS_ID=$(get_field "$MEALS_RESULT" "Id")

if [ -n "$MEALS_ID" ]; then
  echo "  Found 'Compute Meals & Gifts' ($MEALS_ID) — updating..."
  sf data update record --sobject ServiceResourceCostRule --record-id "$MEALS_ID" \
    --values "Type=MealCalculation Rule=TimesheetMealsAndGiftsComputationRule IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
else
  echo "  Creating 'Compute Meals & Gifts'..."
  sf data create record --sobject ServiceResourceCostRule \
    --values "Name='Compute Meals & Gifts' Type=MealCalculation Rule=TimesheetMealsAndGiftsComputationRule IsActive=true" \
    --target-org "$ORG" --json >/dev/null 2>&1
fi
echo "  Configured: Type=MealCalculation, Rule=TimesheetMealsAndGiftsComputationRule"
echo ""

# =============================================================================
# STEP 4: Deploy OWD Sharing Settings
# =============================================================================
echo "--- Step 4: Setting Organization-Wide Defaults (OWD) ---"

OWD_DIR=$(mktemp -d)
mkdir -p "$OWD_DIR/objects"

for obj in TimeSheet CostCenter GeolocationBasedAction JobExpenseType; do
cat > "$OWD_DIR/objects/${obj}.object" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <sharingModel>ReadWrite</sharingModel>
    <externalSharingModel>ReadWrite</externalSharingModel>
</CustomObject>
EOF
done

cat > "$OWD_DIR/objects/SupplementalCompensation.object" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <sharingModel>Read</sharingModel>
    <externalSharingModel>Read</externalSharingModel>
</CustomObject>
EOF

cat > "$OWD_DIR/package.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>TimeSheet</members>
        <members>CostCenter</members>
        <members>GeolocationBasedAction</members>
        <members>JobExpenseType</members>
        <members>SupplementalCompensation</members>
        <name>CustomObject</name>
    </types>
    <version>66.0</version>
</Package>
EOF

mdapi_deploy "$OWD_DIR" "OWD sharing settings"
rm -rf "$OWD_DIR"
echo ""

# =============================================================================
# STEP 5: Assign Permission Sets
# =============================================================================
echo "--- Step 5: Assigning Permission Sets ---"
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

if [ -n "${SUPERVISOR_USER:-}" ]; then
  assign_permset "LaborCostOptimAdmin" "$SUPERVISOR_USER"
  assign_permset "LaborCostOptimSupervisor" "$SUPERVISOR_USER"
fi

if [ -n "${RESOURCE_USER:-}" ]; then
  assign_permset "LaborCostOptimResource" "$RESOURCE_USER"
fi

if [ -n "${RESOURCE_USER:-}" ] && [ -n "${SUPERVISOR_USER:-}" ] && [ "$RESOURCE_USER" != "$SUPERVISOR_USER" ]; then
  assign_permset "LaborCostOptimResource" "$SUPERVISOR_USER"
fi
echo ""

# =============================================================================
# STEP 6: Deploy SDO Timesheet Data Rules expression set
# =============================================================================
echo "--- Step 6: Deploying SDO Timesheet Data Rules expression set ---"

EXPR_SET_FILE="$PROJECT_DIR/force-app/main/default/expressionSetDefinition/SDO_Timesheet_Data_Rules.expressionSetDefinition-meta.xml"

if [ -f "$EXPR_SET_FILE" ]; then
  echo "  Found local expression set metadata — deploying..."
  (cd "$PROJECT_DIR" && sf project deploy start \
    --source-dir "force-app/main/default/expressionSetDefinition" \
    --target-org "$ORG" --json >/dev/null 2>&1) && \
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

EXPR_ID=$(curl -s "${INSTANCE_URL}/services/data/v66.0/tooling/query/?q=SELECT+Id+FROM+ExpressionSetDefinition+WHERE+DeveloperName='SDO_Timesheet_Data_Rules'" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['records'][0]['Id'] if d.get('records') else '')" 2>/dev/null)

if [ -n "$EXPR_ID" ]; then
  curl -s -X PATCH "${INSTANCE_URL}/services/data/v66.0/tooling/sobjects/ExpressionSetDefinition/${EXPR_ID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"Metadata":{"processType":"Timesheet","label":"SDO Timesheet Data Rules","template":false}}' >/dev/null 2>&1 && \
    echo "  Set processType to Timesheet" || \
    echo "  NOTE: processType may already be set (cannot change after creation)."
fi
echo ""

# =============================================================================
# STEP 7: Verification
# =============================================================================
echo "--- Step 7: Verification ---"

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

echo "  OWD Sharing:"
ACCESS_TOKEN=$(sf org display --target-org "$ORG" --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['accessToken'])")
INSTANCE_URL=$(sf org display --target-org "$ORG" --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['instanceUrl'])")
for obj in TimeSheet CostCenter GeolocationBasedAction JobExpenseType SupplementalCompensation; do
  curl -s "${INSTANCE_URL}/services/data/v66.0/tooling/query/?q=SELECT+Id,InternalSharingModel,ExternalSharingModel+FROM+EntityDefinition+WHERE+QualifiedApiName='${obj}'" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
recs=d.get('records',[])
if recs:
    print(f'    $obj: Internal={recs[0].get(\"InternalSharingModel\")}, External={recs[0].get(\"ExternalSharingModel\")}')
" 2>/dev/null
done

echo ""
echo "=== Automated setup complete ==="
echo ""
echo "REMAINING MANUAL STEPS (if not done already):"
echo "  1. Enable Timesheets in Field Service Settings (Setup > Field Service Settings)"
echo "  2. Create expression sets from templates (App Launcher > Expression Set Templates)"
echo "  3. Set TimeSheetEntryItem Status default to 'New' (Object Manager > TimeSheetEntryItem > Status)"
echo "  4. Page layout actions — optional (see TIMESHEET-SETUP-GUIDE.md Part C)"
