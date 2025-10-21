#!/bin/bash
# Delete output files from Google Cloud Storage and optionally batch jobs
# Usage: ./delete_output.sh <gcs_path> [options]
# Example: ./delete_output.sh gs://my-bucket/brieflow_output/

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

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo "Usage: $0 <gcs_path> [options]"
    echo ""
    echo "Examples:"
    echo "  $0 gs://my-bucket/brieflow_output/"
    echo "  $0 gs://my-bucket/brieflow_output/ --force"
    echo "  $0 gs://my-bucket/brieflow_output/ --delete-jobs --job-state FAILED"
    echo ""
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompt"
    echo "  -n, --dry-run         Show what would be deleted without actually deleting"
    echo "  -j, --delete-jobs     Also delete batch jobs"
    echo "  -s, --job-state STATE Filter jobs by state (SUCCEEDED, FAILED, ALL)"
    echo "                        Only used with --delete-jobs (default: ALL)"
    echo ""
    echo "Environment variables:"
    echo "  BATCH_PROJECT    GCP project ID (default: lasagna-199723)"
    echo "  BATCH_REGION     GCP region (default: us-west1)"
    exit 1
fi

GCS_PATH="$1"
FORCE=false
DRY_RUN=false
DELETE_JOBS=false
JOB_STATE="ALL"

# Parse options
shift
while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)
            FORCE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -j|--delete-jobs)
            DELETE_JOBS=true
            shift
            ;;
        -s|--job-state)
            JOB_STATE="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate GCS path format
if [[ ! "$GCS_PATH" =~ ^gs:// ]]; then
    echo -e "${RED}Error: GCS path must start with gs://${NC}"
    echo "Got: $GCS_PATH"
    exit 1
fi

# Check if path exists
if ! gsutil ls "$GCS_PATH" &>/dev/null; then
    echo -e "${YELLOW}Warning: Path does not exist or is empty: $GCS_PATH${NC}"
    exit 0
fi

# Show what we're about to delete
echo -e "${BLUE}Delete Configuration:${NC}"
echo "  Path: $GCS_PATH"

if [ "$DRY_RUN" = true ]; then
    echo -e "  Mode: ${BLUE}DRY RUN (no actual deletion)${NC}"
fi
echo ""

# List files to be deleted
echo -e "${BLUE}Files/directories to be deleted:${NC}"
gsutil ls -lh "$GCS_PATH" 2>/dev/null | head -20

# Count files
FILE_COUNT=$(gsutil ls -r "$GCS_PATH" 2>/dev/null | wc -l)
echo ""
echo "Total objects: $FILE_COUNT"
echo ""

# Warn about deletion
if [ "$FILE_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}WARNING: This will permanently delete $FILE_COUNT objects!${NC}"
    echo -e "${YELLOW}This action CANNOT be undone.${NC}"
    echo ""
fi

# Confirm unless --force or dry-run
if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    echo -e "${RED}Are you absolutely sure you want to delete these files?${NC}"
    read -p "Type 'DELETE' to confirm: " CONFIRM
    if [ "$CONFIRM" != "DELETE" ]; then
        echo "Deletion cancelled."
        exit 0
    fi
    echo ""
fi

# Delete files
if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}Files that would be deleted:${NC}"
    gsutil ls -r "$GCS_PATH" | head -50
    echo "..."
    echo -e "${GREEN}Dry run complete. No files were deleted.${NC}"
else
    echo -e "${BLUE}Deleting files...${NC}"
    gsutil -m rm -r "$GCS_PATH"
    echo ""
    echo -e "${GREEN}GCS deletion complete!${NC}"

    # Verify deletion
    if gsutil ls "$GCS_PATH" &>/dev/null; then
        echo -e "${YELLOW}Warning: Some files may still exist at $GCS_PATH${NC}"
    else
        echo "Path successfully deleted: $GCS_PATH"
    fi
fi

# Delete batch jobs if requested
if [ "$DELETE_JOBS" = true ]; then
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}Deleting Batch Jobs${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""

    # Build filter for gcloud command
    GCLOUD_FILTER=""
    if [ "$JOB_STATE" != "ALL" ]; then
        GCLOUD_FILTER="--filter=status.state=$JOB_STATE"
    fi

    # Get list of jobs to delete
    echo -e "${BLUE}Fetching batch jobs...${NC}"
    mapfile -t jobs < <(gcloud batch jobs list \
        --location="$REGION" \
        --project="$PROJECT" \
        $GCLOUD_FILTER \
        --format="value(name)")

    if [ ${#jobs[@]} -eq 0 ]; then
        echo -e "${GREEN}No batch jobs found matching criteria.${NC}"
    else
        echo -e "${YELLOW}Found ${#jobs[@]} batch job(s) to delete${NC}"

        if [ "$JOB_STATE" != "ALL" ]; then
            echo "  State filter: $JOB_STATE"
        else
            echo "  State filter: All states"
        fi
        echo ""

        # Show jobs
        echo -e "${BLUE}Batch jobs to be deleted:${NC}"
        for job in "${jobs[@]}"; do
            job_name=$(basename "$job")
            job_state=$(gcloud batch jobs describe "$job" \
                --project="$PROJECT" \
                --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
            echo "  - $job_name ($job_state)"
        done
        echo ""

        if [ "$DRY_RUN" = true ]; then
            echo -e "${GREEN}Dry run: No jobs were deleted.${NC}"
        else
            # Additional confirmation for job deletion unless --force
            if [ "$FORCE" = false ]; then
                echo -e "${YELLOW}WARNING: This will delete ${#jobs[@]} batch job(s)!${NC}"
                read -p "Type 'DELETE JOBS' to confirm: " CONFIRM_JOBS
                if [ "$CONFIRM_JOBS" != "DELETE JOBS" ]; then
                    echo "Job deletion cancelled."
                else
                    echo ""
                    echo -e "${BLUE}Deleting batch jobs...${NC}"

                    deleted_count=0
                    for job in "${jobs[@]}"; do
                        job_name=$(basename "$job")
                        echo -n "  Deleting $job_name... "

                        if gcloud batch jobs delete "$job" \
                            --location="$REGION" \
                            --project="$PROJECT" \
                            --quiet 2>/dev/null; then
                            echo -e "${GREEN}✓${NC}"
                            ((deleted_count++))
                        else
                            echo -e "${RED}✗${NC}"
                        fi
                    done

                    echo ""
                    echo -e "${GREEN}Batch job deletion complete!${NC}"
                    echo "  Successfully deleted: $deleted_count job(s)"
                fi
            else
                # Force mode - delete without additional confirmation
                echo -e "${BLUE}Deleting batch jobs (force mode)...${NC}"

                deleted_count=0
                for job in "${jobs[@]}"; do
                    job_name=$(basename "$job")
                    echo -n "  Deleting $job_name... "

                    if gcloud batch jobs delete "$job" \
                        --location="$REGION" \
                        --project="$PROJECT" \
                        --quiet 2>/dev/null; then
                        echo -e "${GREEN}✓${NC}"
                        ((deleted_count++))
                    else
                        echo -e "${RED}✗${NC}"
                    fi
                done

                echo ""
                echo -e "${GREEN}Batch job deletion complete!${NC}"
                echo "  Successfully deleted: $deleted_count job(s)"
            fi
        fi
    fi
fi

echo ""
echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}==================================================${NC}"
