#!/bin/bash
# List data in Google Cloud Storage with various options
# Usage: ./list_data.sh <gcs_path> [options]
# Example: ./list_data.sh gs://my-bucket/data/

set -euo pipefail

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default options
RECURSIVE=false
LONG_FORMAT=true
HUMAN_READABLE=true
FILTER=""

# Show help
show_help() {
    echo "Usage: $0 <gcs_path> [options]"
    echo ""
    echo "List contents of a GCS bucket or directory"
    echo ""
    echo "Arguments:"
    echo "  gcs_path          GCS path to list (e.g., gs://my-bucket/data/)"
    echo ""
    echo "Options:"
    echo "  -r, --recursive   List recursively"
    echo "  -s, --summary     Show summary only (total size and count)"
    echo "  -f, --filter PATTERN  Filter results by pattern"
    echo "  -n, --limit N     Limit output to N items"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 gs://my-bucket/data/"
    echo "  $0 gs://my-bucket/data/ -r"
    echo "  $0 gs://my-bucket/data/ -f '*.tiff'"
    echo "  $0 gs://my-bucket/data/ -s"
    exit 0
}

# Check arguments
if [ $# -lt 1 ]; then
    show_help
fi

GCS_PATH="$1"
shift

SUMMARY_ONLY=false
LIMIT=""

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -s|--summary)
            SUMMARY_ONLY=true
            shift
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -n|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            show_help
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
    echo -e "${YELLOW}Path does not exist or is empty: $GCS_PATH${NC}"
    exit 1
fi

echo -e "${BLUE}Listing: $GCS_PATH${NC}"
if [ "$RECURSIVE" = true ]; then
    echo -e "${BLUE}Mode: Recursive${NC}"
fi
if [ -n "$FILTER" ]; then
    echo -e "${BLUE}Filter: $FILTER${NC}"
fi
echo ""

# Build gsutil command
CMD="gsutil ls"
if [ "$LONG_FORMAT" = true ]; then
    CMD="$CMD -l"
fi
if [ "$HUMAN_READABLE" = true ]; then
    CMD="$CMD -h"
fi
if [ "$RECURSIVE" = true ]; then
    CMD="$CMD -r"
fi
CMD="$CMD \"$GCS_PATH\""

# Execute and optionally filter
if [ -n "$FILTER" ]; then
    if [ -n "$LIMIT" ]; then
        eval $CMD | grep "$FILTER" | head -n "$LIMIT"
    else
        eval $CMD | grep "$FILTER"
    fi
else
    if [ -n "$LIMIT" ]; then
        eval $CMD | head -n "$LIMIT"
    else
        eval $CMD
    fi
fi

# Always show summary
echo ""
echo -e "${GREEN}Summary:${NC}"

# Get total size and count
STATS=$(gsutil du -s -h "$GCS_PATH" 2>/dev/null)
TOTAL_SIZE=$(echo "$STATS" | awk '{print $1, $2}')

if [ "$RECURSIVE" = true ]; then
    FILE_COUNT=$(gsutil ls -r "$GCS_PATH" 2>/dev/null | grep -v ':$' | wc -l)
else
    FILE_COUNT=$(gsutil ls "$GCS_PATH" 2>/dev/null | wc -l)
fi

echo -e "  ${YELLOW}Total size:${NC} $TOTAL_SIZE"
echo -e "  ${YELLOW}Total items:${NC} $FILE_COUNT"
