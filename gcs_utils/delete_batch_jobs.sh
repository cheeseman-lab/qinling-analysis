#!/bin/bash
# Delete Google Batch jobs
# Usage: ./delete_batch_jobs.sh [options]

set -euo pipefail

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT="${BATCH_PROJECT:-lasagna-199723}"
REGION="${BATCH_REGION:-us-west1}"

# Default options
FILTER_STATE=""
FORCE=false
DRY_RUN=false
OLDER_THAN_DAYS=""

# Show help
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Delete Google Batch jobs"
    echo ""
    echo "Options:"
    echo "  -s, --state STATE     Delete only jobs in specific state"
    echo "                        (SUCCEEDED, FAILED, RUNNING, ALL)"
    echo "  -d, --days N          Delete only jobs older than N days"
    echo "  -f, --force           Skip confirmation prompt"
    echo "  -n, --dry-run         Show what would be deleted without deleting"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --state FAILED              # Delete all failed jobs"
    echo "  $0 --state SUCCEEDED --days 7  # Delete succeeded jobs older than 7 days"
    echo "  $0 --state ALL --force         # Delete all jobs (no confirmation)"
    echo "  $0 --dry-run                   # Preview all jobs that would be deleted"
    echo ""
    echo "Environment variables:"
    echo "  BATCH_PROJECT    GCP project ID (default: lasagna-199723)"
    echo "  BATCH_REGION     GCP region (default: us-west1)"
    echo ""
    echo "WARNING: Deleted jobs cannot be recovered!"
    exit 0
}

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -s|--state)
            FILTER_STATE="$2"
            shift 2
            ;;
        -d|--days)
            OLDER_THAN_DAYS="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            show_help
            ;;
    esac
done

echo -e "${BLUE}Delete Batch Jobs Configuration:${NC}"
echo "  Project: $PROJECT"
echo "  Region: $REGION"
if [ -n "$FILTER_STATE" ]; then
    echo "  State filter: $FILTER_STATE"
else
    echo "  State filter: All states"
fi
if [ -n "$OLDER_THAN_DAYS" ]; then
    echo "  Age filter: Older than $OLDER_THAN_DAYS days"
fi
if [ "$DRY_RUN" = true ]; then
    echo -e "  Mode: ${BLUE}DRY RUN (no actual deletion)${NC}"
fi
echo ""

# Build filter for gcloud command
GCLOUD_FILTER=""
if [ -n "$FILTER_STATE" ] && [ "$FILTER_STATE" != "ALL" ]; then
    GCLOUD_FILTER="--filter=status.state=$FILTER_STATE"
fi

# Add time filter if specified
if [ -n "$OLDER_THAN_DAYS" ]; then
    # Calculate the cutoff date
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        CUTOFF_DATE=$(date -u -v-${OLDER_THAN_DAYS}d +"%Y-%m-%dT%H:%M:%SZ")
    else
        # Linux
        CUTOFF_DATE=$(date -u -d "$OLDER_THAN_DAYS days ago" +"%Y-%m-%dT%H:%M:%SZ")
    fi

    if [ -n "$GCLOUD_FILTER" ]; then
        GCLOUD_FILTER="$GCLOUD_FILTER AND createTime<$CUTOFF_DATE"
    else
        GCLOUD_FILTER="--filter=createTime<$CUTOFF_DATE"
    fi
fi

# Get list of jobs to delete
echo -e "${BLUE}Fetching jobs...${NC}"
mapfile -t jobs < <(gcloud batch jobs list \
    --location="$REGION" \
    --project="$PROJECT" \
    $GCLOUD_FILTER \
    --format="value(name)")

if [ ${#jobs[@]} -eq 0 ]; then
    echo -e "${GREEN}No jobs found matching criteria.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found ${#jobs[@]} job(s) to delete:${NC}"
echo ""

# Show jobs with their states
echo -e "${BLUE}Jobs to be deleted:${NC}"
for job in "${jobs[@]}"; do
    job_name=$(basename "$job")
    job_state=$(gcloud batch jobs describe "$job" \
        --project="$PROJECT" \
        --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
    job_created=$(gcloud batch jobs describe "$job" \
        --project="$PROJECT" \
        --format="value(createTime)" 2>/dev/null || echo "Unknown")

    echo "  - $job_name (State: $job_state, Created: $job_created)"
done

echo ""
echo -e "${YELLOW}Total: ${#jobs[@]} job(s)${NC}"
echo ""

# Warn about deletion
if [ ${#jobs[@]} -gt 0 ]; then
    echo -e "${YELLOW}WARNING: This will permanently delete ${#jobs[@]} batch job(s)!${NC}"
    echo -e "${YELLOW}Job history and logs will be removed from Google Batch.${NC}"
    echo -e "${YELLOW}This action CANNOT be undone.${NC}"
    echo ""
fi

# Confirm unless --force or dry-run
if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    echo -e "${RED}Are you absolutely sure you want to delete these jobs?${NC}"
    read -p "Type 'DELETE' to confirm: " CONFIRM
    if [ "$CONFIRM" != "DELETE" ]; then
        echo "Deletion cancelled."
        exit 0
    fi
    echo ""
fi

# Delete jobs
if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}Dry run complete. No jobs were deleted.${NC}"
    echo ""
    echo "To actually delete these jobs, run without --dry-run:"
    if [ -n "$FILTER_STATE" ]; then
        echo "  $0 --state $FILTER_STATE"
    else
        echo "  $0"
    fi
else
    echo -e "${BLUE}Deleting jobs...${NC}"

    deleted_count=0
    failed_count=0

    for job in "${jobs[@]}"; do
        job_name=$(basename "$job")
        echo -n "  Deleting $job_name... "

        if gcloud batch jobs delete "$job" \
            --location="$REGION" \
            --project="$PROJECT" \
            --quiet 2>/dev/null; then
            echo -e "${GREEN}✓ deleted${NC}"
            ((deleted_count++))
        else
            echo -e "${RED}✗ failed${NC}"
            ((failed_count++))
        fi
    done

    echo ""
    echo -e "${GREEN}Deletion complete!${NC}"
    echo "  Successfully deleted: $deleted_count job(s)"
    if [ $failed_count -gt 0 ]; then
        echo -e "  ${YELLOW}Failed to delete: $failed_count job(s)${NC}"
    fi

    # Verify deletion
    echo ""
    echo "Verifying..."
    remaining=$(gcloud batch jobs list \
        --location="$REGION" \
        --project="$PROJECT" \
        $GCLOUD_FILTER \
        --format="value(name)" | wc -l)

    if [ "$remaining" -eq 0 ]; then
        echo -e "${GREEN}All jobs successfully deleted.${NC}"
    else
        echo -e "${YELLOW}Warning: $remaining job(s) still exist${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Current job count by state:${NC}"
for state in SUCCEEDED FAILED RUNNING QUEUED; do
    count=$(gcloud batch jobs list \
        --location="$REGION" \
        --project="$PROJECT" \
        --filter="status.state=$state" \
        --format="value(name)" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo "  $state: $count"
    fi
done
