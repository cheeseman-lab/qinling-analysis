#!/bin/bash
# Upload data to Google Cloud Storage
# Usage: ./upload_data.sh <local_path> <gcs_destination>
# Example: ./upload_data.sh /path/to/data gs://my-bucket/data/

set -euo pipefail

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo "Usage: $0 <local_path> <gcs_destination>"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/data gs://my-bucket/data/"
    echo "  $0 ./my_file.txt gs://my-bucket/files/my_file.txt"
    echo ""
    echo "Options:"
    echo "  -n  Dry run - show what would be copied without actually copying"
    exit 1
fi

LOCAL_PATH="$1"
GCS_DEST="$2"

# Check if dry run
DRY_RUN=false
if [ "${3:-}" = "-n" ] || [ "${3:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

# Validate local path exists
if [ ! -e "$LOCAL_PATH" ]; then
    echo -e "${RED}Error: Local path does not exist: $LOCAL_PATH${NC}"
    exit 1
fi

# Validate GCS path format
if [[ ! "$GCS_DEST" =~ ^gs:// ]]; then
    echo -e "${RED}Error: GCS destination must start with gs://${NC}"
    echo "Got: $GCS_DEST"
    exit 1
fi

# Show what we're about to do
echo -e "${BLUE}Upload Configuration:${NC}"
echo "  Source:      $LOCAL_PATH"
echo "  Destination: $GCS_DEST"

if [ -d "$LOCAL_PATH" ]; then
    echo "  Type:        Directory (recursive)"
else
    echo "  Type:        File"
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}  Mode:        DRY RUN (no actual upload)${NC}"
fi
echo ""

# Calculate size
echo -e "${BLUE}Calculating size...${NC}"
if [ -d "$LOCAL_PATH" ]; then
    SIZE=$(du -sh "$LOCAL_PATH" | cut -f1)
    echo "  Total size: $SIZE"
else
    SIZE=$(ls -lh "$LOCAL_PATH" | awk '{print $5}')
    echo "  File size: $SIZE"
fi
echo ""

# Confirm unless dry run
if [ "$DRY_RUN" = false ]; then
    read -p "Proceed with upload? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Upload cancelled."
        exit 0
    fi
fi

# Upload with progress
echo -e "${BLUE}Uploading...${NC}"

if [ "$DRY_RUN" = true ]; then
    # Dry run - just list files
    if [ -d "$LOCAL_PATH" ]; then
        find "$LOCAL_PATH" -type f | head -20
        echo "..."
    else
        echo "$LOCAL_PATH"
    fi
    echo -e "${GREEN}Dry run complete. No files were uploaded.${NC}"
else
    # Actual upload
    if [ -d "$LOCAL_PATH" ]; then
        # Directory - use parallel upload with progress
        gsutil -m cp -r "$LOCAL_PATH" "$GCS_DEST"
    else
        # Single file
        gsutil cp "$LOCAL_PATH" "$GCS_DEST"
    fi

    echo ""
    echo -e "${GREEN}Upload complete!${NC}"
    echo ""
    echo "Verifying upload..."
    gsutil ls -lh "$GCS_DEST" | head -10
fi
