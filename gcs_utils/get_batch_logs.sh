#!/bin/bash

# Enhanced script to fetch Google Batch job logs
# Usage: ./get_batch_logs.sh [job_name] [options]

set -euo pipefail

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - update these for your project
PROJECT="${BATCH_PROJECT:-lasagna-199723}"
REGION="${BATCH_REGION:-us-west1}"
OUTPUT_DIR="./batch_logs"

# Default options
FILTER_STATE=""
LIMIT=10
SEARCH_PATTERN=""
TIME_FILTER="24h"

# Show help
show_help() {
    echo "Usage: $0 [job_name] [options]"
    echo ""
    echo "Fetch logs for Google Batch jobs"
    echo ""
    echo "Arguments:"
    echo "  job_name          Specific job name to fetch logs for (optional)"
    echo ""
    echo "Options:"
    echo "  -s, --state STATE Filter jobs by state (FAILED, SUCCEEDED, RUNNING, etc.)"
    echo "  -l, --limit N     Limit to N jobs (default: 10, randomly selected if more available)"
    echo "  -t, --time HOURS  Filter jobs from last N hours (default: 24h)"
    echo "  -p, --pattern PAT Search logs for pattern"
    echo "  -o, --output DIR  Output directory (default: ./batch_logs)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Find all failed jobs, randomly select 10"
    echo "  $0 snakejob-abc123           # Fetch logs for specific job"
    echo "  $0 --state FAILED --limit 5  # Find all failed jobs, randomly select 5"
    echo "  $0 --state SUCCEEDED         # Fetch logs for successful jobs (up to 10)"
    echo "  $0 --pattern 'ERROR' -s FAILED  # Search for ERROR in random failed jobs"
    echo ""
    echo "Environment variables:"
    echo "  BATCH_PROJECT    GCP project ID (default: lasagna-199723)"
    echo "  BATCH_REGION     GCP region (default: us-west1)"
    exit 0
}

# Function to get logs for a single job
get_job_logs() {
    local job_name=$1
    local job_short_name=$(basename "$job_name")

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}Fetching logs for: $job_short_name${NC}"
    echo -e "${BLUE}==================================================${NC}"

    # Create a subdirectory for this job
    local job_dir="$OUTPUT_DIR/$job_short_name"
    mkdir -p "$job_dir"

    # Get job description
    echo "Getting job details..."
    gcloud batch jobs describe "$job_name" \
        --project="$PROJECT" \
        --format=json > "$job_dir/job_details.json" 2>&1 || {
        echo -e "${YELLOW}Warning: Could not get job description${NC}"
        return 1
    }

    # Extract key info from job description
    local job_state=$(jq -r '.status.state' "$job_dir/job_details.json" 2>/dev/null || echo "UNKNOWN")
    local job_uid=$(jq -r '.uid' "$job_dir/job_details.json" 2>/dev/null)
    local create_time=$(jq -r '.createTime' "$job_dir/job_details.json" 2>/dev/null || echo "Unknown")

    if [ -z "$job_uid" ] || [ "$job_uid" = "null" ]; then
        echo -e "${YELLOW}Warning: Could not get job UID${NC}"
        return 1
    fi

    echo -e "  Job UID: ${GREEN}$job_uid${NC}"
    echo -e "  State: ${GREEN}$job_state${NC}"
    echo -e "  Created: ${GREEN}$create_time${NC}"

    # Get batch task logs (this is where snakemake output goes)
    echo "Getting batch task logs..."
    local task_log_file="$job_dir/batch_task_logs.txt"
    gcloud logging read \
        "logName=\"projects/$PROJECT/logs/batch_task_logs\" AND labels.job_uid=\"$job_uid\"" \
        --project="$PROJECT" \
        --limit=10000 \
        --format="table(timestamp,severity,textPayload)" > "$task_log_file" 2>&1

    if [ -s "$task_log_file" ]; then
        local line_count=$(wc -l < "$task_log_file")
        echo -e "  ${GREEN}Found batch task logs ($line_count lines)${NC}"
    else
        echo -e "  ${YELLOW}No batch task logs found${NC}"
    fi

    # Get batch agent logs (system-level logs)
    echo "Getting batch agent logs..."
    local agent_log_file="$job_dir/batch_agent_logs.txt"
    gcloud logging read \
        "logName=\"projects/$PROJECT/logs/batch_agent_logs\" AND labels.job_uid=\"$job_uid\"" \
        --project="$PROJECT" \
        --limit=10000 \
        --format="table(timestamp,severity,textPayload)" > "$agent_log_file" 2>&1

    if [ -s "$agent_log_file" ]; then
        local line_count=$(wc -l < "$agent_log_file")
        echo -e "  ${GREEN}Found batch agent logs ($line_count lines)${NC}"
    else
        echo -e "  ${YELLOW}No batch agent logs found${NC}"
    fi

    # Get Cloud Logging logs for this job
    echo "Getting Cloud Logging logs..."
    local cloud_log_file="$job_dir/cloud_logs.txt"
    gcloud logging read \
        "resource.type=\"batch.googleapis.com/Job\" AND resource.labels.job_uid=\"$job_uid\"" \
        --project="$PROJECT" \
        --limit=10000 \
        --format="table(timestamp,severity,jsonPayload.message)" > "$cloud_log_file" 2>&1

    if [ -s "$cloud_log_file" ]; then
        local line_count=$(wc -l < "$cloud_log_file")
        echo -e "  ${GREEN}Found cloud logs ($line_count lines)${NC}"
    else
        echo -e "  ${YELLOW}No cloud logs found${NC}"
    fi

    # Search for pattern if specified
    if [ -n "$SEARCH_PATTERN" ]; then
        echo -e "Searching for pattern: ${BLUE}$SEARCH_PATTERN${NC}"
        local search_file="$job_dir/search_results.txt"
        {
            echo "Search results for pattern: $SEARCH_PATTERN"
            echo "=========================================="
            echo ""
            echo "=== Task Logs ==="
            grep -i "$SEARCH_PATTERN" "$task_log_file" 2>/dev/null || echo "No matches in task logs"
            echo ""
            echo "=== Agent Logs ==="
            grep -i "$SEARCH_PATTERN" "$agent_log_file" 2>/dev/null || echo "No matches in agent logs"
            echo ""
            echo "=== Cloud Logs ==="
            grep -i "$SEARCH_PATTERN" "$cloud_log_file" 2>/dev/null || echo "No matches in cloud logs"
        } > "$search_file"
        echo -e "  ${GREEN}Search results saved to search_results.txt${NC}"
    fi

    # Create a summary file
    local summary_file="$job_dir/SUMMARY.txt"
    {
        echo "=============================================="
        echo "Job Summary: $job_short_name"
        echo "=============================================="
        echo "Full name: $job_name"
        echo "Job UID: $job_uid"
        echo "State: $job_state"
        echo "Created: $create_time"
        echo "Fetched at: $(date)"
        echo ""
        echo "Files in this directory:"
        echo "  - job_details.json: Full job configuration and status"
        echo "  - batch_task_logs.txt: Batch task logs (snakemake output)"
        echo "  - batch_agent_logs.txt: Batch agent logs (system logs)"
        echo "  - cloud_logs.txt: Cloud logging messages"
        if [ -n "$SEARCH_PATTERN" ]; then
            echo "  - search_results.txt: Search results for '$SEARCH_PATTERN'"
        fi
        echo ""
        echo "Log file sizes:"
        find "$job_dir" -name "*.txt" -o -name "*.json" | while read -r file; do
            if [ -s "$file" ]; then
                local size=$(wc -l < "$file" 2>/dev/null || echo "0")
                echo "  - $(basename "$file"): $size lines"
            fi
        done
        echo ""
        echo "Key errors and warnings (from batch_task_logs.txt):"
        if [ -s "$task_log_file" ]; then
            grep -iE "error|fail|exception|traceback" "$task_log_file" | head -10 || echo "  No errors found"
        else
            echo "  No task logs available"
        fi
    } > "$summary_file"

    echo ""
    echo -e "${GREEN}Logs saved to: $job_dir${NC}"
    echo -e "${BLUE}Summary:${NC}"
    cat "$summary_file"
    echo ""

    return 0
}

# Parse arguments
JOB_NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -s|--state)
            FILTER_STATE="$2"
            shift 2
            ;;
        -l|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -t|--time)
            TIME_FILTER="$2"
            shift 2
            ;;
        -p|--pattern)
            SEARCH_PATTERN="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            if [ -z "$JOB_NAME" ]; then
                JOB_NAME="$1"
            else
                echo -e "${RED}Error: Unknown option: $1${NC}"
                show_help
            fi
            shift
            ;;
    esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Main logic
if [ -n "$JOB_NAME" ]; then
    # Specific job provided
    if [[ ! "$JOB_NAME" =~ ^projects/ ]]; then
        JOB_NAME="projects/$PROJECT/locations/$REGION/jobs/$JOB_NAME"
    fi

    get_job_logs "$JOB_NAME"
else
    # No specific job, get recent jobs based on filter
    echo -e "${BLUE}Fetching recent batch jobs...${NC}"
    echo "  Project: $PROJECT"
    echo "  Region: $REGION"
    if [ -n "$FILTER_STATE" ]; then
        echo "  State filter: $FILTER_STATE"
    fi
    echo "  Limit: $LIMIT jobs"
    echo ""

    # Build filter
    FILTER_ARGS=""
    if [ -n "$FILTER_STATE" ]; then
        FILTER_ARGS="--filter=status.state=$FILTER_STATE"
    fi

    # Get ALL jobs matching the filter (up to 1000 to search through)
    # This allows us to find all failed jobs, then randomly select from them
    echo -e "${BLUE}Searching for jobs matching criteria...${NC}"
    mapfile -t all_jobs < <(gcloud batch jobs list \
        --project="$PROJECT" \
        --location="$REGION" \
        $FILTER_ARGS \
        --limit=1000 \
        --format="value(name)" \
        --sort-by=~createTime)

    if [ ${#all_jobs[@]} -eq 0 ]; then
        echo -e "${YELLOW}No jobs found matching criteria${NC}"
        exit 0
    fi

    echo -e "${GREEN}Found ${#all_jobs[@]} job(s) matching criteria${NC}"

    # If we found more jobs than the limit, randomly select from them
    if [ ${#all_jobs[@]} -gt "$LIMIT" ]; then
        echo -e "${BLUE}Randomly selecting $LIMIT jobs from ${#all_jobs[@]} available...${NC}"
        # Use shuf to randomly select jobs
        mapfile -t jobs < <(printf '%s\n' "${all_jobs[@]}" | shuf -n "$LIMIT")
    else
        jobs=("${all_jobs[@]}")
    fi

    echo -e "${GREEN}Will fetch logs for ${#jobs[@]} job(s)${NC}"
    echo ""

    # Fetch logs for each job
    for job in "${jobs[@]}"; do
        get_job_logs "$job" || echo -e "${YELLOW}Skipping job due to errors${NC}"
    done

    # Create an index file
    {
        echo "=============================================="
        echo "Batch Job Logs Index"
        echo "=============================================="
        echo "Fetched at: $(date)"
        echo "Project: $PROJECT"
        echo "Region: $REGION"
        if [ -n "$FILTER_STATE" ]; then
            echo "State filter: $FILTER_STATE"
        fi
        echo ""
        echo "Jobs (${#jobs[@]}):"
        for job in "${jobs[@]}"; do
            local short_name=$(basename "$job")
            local state=$(gcloud batch jobs describe "$job" --project="$PROJECT" --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
            echo "  - $short_name ($state)"
        done
        echo ""
        echo "Directories:"
        for job in "${jobs[@]}"; do
            local short_name=$(basename "$job")
            echo "  - $OUTPUT_DIR/$short_name/"
        done
    } > "$OUTPUT_DIR/INDEX.txt"

    echo ""
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}All logs saved to: $OUTPUT_DIR${NC}"
    echo -e "${GREEN}See INDEX.txt for a summary${NC}"
    echo -e "${GREEN}==================================================${NC}"
fi

# Print helpful next steps
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Check $OUTPUT_DIR/INDEX.txt for an overview"
echo "  2. Look at individual job directories for detailed logs"
echo "  3. Check SUMMARY.txt in each directory for key errors"
if [ -n "$SEARCH_PATTERN" ]; then
    echo "  4. Check search_results.txt for matches to '$SEARCH_PATTERN'"
fi
echo ""
