#!/bin/bash
# Upload analysis/config/ to GCS and prepare config.yml for batch execution
#
# This script does 3 things:
#   1. Uploads config files (TSV, models, etc.) to GCS
#   2. Updates config.yml paths to reference GCS locations
#   3. Copies the GCS-updated config.yml to brieflow/workflow/
#
# Usage from analysis/:
#   ../gcs_utils/upload_config.sh [screen_name]
#
# Usage from project root:
#   gcs_utils/upload_config.sh [screen_name]

set -euo pipefail

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source and destination configuration
LOCAL_CONFIG="$SCRIPT_DIR/../analysis/config"
WORKFLOW_DIR="$SCRIPT_DIR/../brieflow/workflow"
GCS_BUCKET="gs://scale1"

# Check if config directory exists
if [ ! -d "$LOCAL_CONFIG" ]; then
    echo -e "${RED}Error: Config directory not found at $LOCAL_CONFIG${NC}"
    echo ""
    echo "Run a configuration notebook first to generate config files"
    exit 1
fi

# Check if config.yml exists
if [ ! -f "$LOCAL_CONFIG/config.yml" ]; then
    echo -e "${RED}Error: config.yml not found at $LOCAL_CONFIG/config.yml${NC}"
    exit 1
fi

# Check if workflow directory exists
if [ ! -d "$WORKFLOW_DIR" ]; then
    echo -e "${RED}Error: Workflow directory not found at $WORKFLOW_DIR${NC}"
    exit 1
fi

# Get screen name from argument or prompt
if [ $# -ge 1 ]; then
    SCREEN_NAME="$1"
else
    echo -e "${BLUE}Enter your screen name:${NC}"
    echo "  GCS path: ${GCS_BUCKET}/SCREEN_NAME/config/"
    echo ""
    read -p "Screen name: " SCREEN_NAME

    if [ -z "$SCREEN_NAME" ]; then
        echo -e "${RED}Error: Screen name cannot be empty${NC}"
        exit 1
    fi
fi

# Build GCS destination path
GCS_DEST="${GCS_BUCKET}/${SCREEN_NAME}/config/"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Prepare Config for Google Batch${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "  Local config:  $LOCAL_CONFIG/"
echo "  GCS upload:    $GCS_DEST"
echo "  Workflow copy: $WORKFLOW_DIR/config.yml"
echo ""

# Show what files will be uploaded
echo -e "${BLUE}Files to upload to GCS:${NC}"
ls -lh "$LOCAL_CONFIG" | tail -n +2 | grep -v "config.yml" | awk '{printf "  %-30s %8s\n", $9, $5}'
echo ""

# Calculate total size
SIZE=$(du -sh "$LOCAL_CONFIG" | cut -f1)
echo "  Total size: $SIZE"
echo ""

# Confirm
read -p "Proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1: Upload config files to GCS${NC}"
echo -e "${YELLOW}(Uploading all files except config.yml)${NC}"
echo ""

# Upload all files except config.yml
for file in "$LOCAL_CONFIG"/*; do
    filename=$(basename "$file")

    # Skip config.yml - we'll handle it separately
    if [ "$filename" == "config.yml" ]; then
        continue
    fi

    # Upload file or directory
    if [ -d "$file" ]; then
        echo "  Uploading directory: $filename/"
        gsutil -m cp -r "$file" "${GCS_DEST}"
    else
        echo "  Uploading file: $filename"
        gsutil cp "$file" "${GCS_DEST}${filename}"
    fi
done

echo -e "${GREEN}✓ Files uploaded to GCS${NC}"
echo ""

echo -e "${BLUE}Step 2: Update config.yml with GCS paths${NC}"
echo ""

# Create a temporary file for the modified config
TEMP_CONFIG=$(mktemp)

# Read config.yml and replace config file paths with GCS paths
# This handles paths like:
#   sbs_samples_fp: config/sbs_samples.tsv  → gs://bucket/screen/config/sbs_samples.tsv
#   phenotype_combo_fp: /full/path/to/file.tsv → gs://bucket/screen/config/file.tsv

while IFS= read -r line; do
    # Check if line contains a path to a config file (ends with _fp: or _path:)
    if [[ $line =~ (_fp:|_path:)[[:space:]]+ ]]; then
        # Extract the key and value
        key=$(echo "$line" | cut -d':' -f1 | xargs)
        value=$(echo "$line" | cut -d':' -f2- | xargs)

        # Skip if value is null or already a GCS path
        if [[ "$value" == "null" ]] || [[ "$value" =~ ^gs:// ]]; then
            echo "$line"
        else
            # Normalize the path (remove "config/" prefix if present)
            normalized_path="$value"
            if [[ "$normalized_path" =~ ^config/ ]]; then
                normalized_path="${normalized_path#config/}"
            fi

            # Check if this file exists in local config (supporting subdirectories)
            if [ -f "$LOCAL_CONFIG/$normalized_path" ] || [ -d "$LOCAL_CONFIG/$normalized_path" ]; then
                # Replace with GCS path (preserving subdirectory structure)
                new_line="  ${key}: ${GCS_DEST}${normalized_path}"
                echo "  Updated: $key → $normalized_path" >&2
                echo "$new_line"
            else
                # Keep original line if file not found in config
                echo "$line"
            fi
        fi
    else
        # Not a path line, keep as is
        echo "$line"
    fi
done < "$LOCAL_CONFIG/config.yml" > "$TEMP_CONFIG"

echo ""
echo -e "${GREEN}✓ Config paths updated${NC}"
echo ""

echo -e "${BLUE}Step 3: Copy updated config.yml to workflow directory${NC}"
echo ""

# Copy the modified config to workflow directory
cp "$TEMP_CONFIG" "$WORKFLOW_DIR/config.yml"
rm "$TEMP_CONFIG"

echo "  $WORKFLOW_DIR/config.yml"
echo ""
echo -e "${GREEN}✓ Config copied to workflow directory${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Config preparation complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}What happened:${NC}"
echo "  1. Uploaded config files to: ${GCS_DEST}"
echo "  2. Updated config.yml paths to reference GCS"
echo "  3. Copied config.yml to: $WORKFLOW_DIR/config.yml"
echo ""
echo -e "${YELLOW}Next step:${NC}"
echo "  Run batch script: cd analysis && ./1.run_preprocessing_batch.sh"
echo ""
echo -e "${BLUE}Verify upload:${NC}"
echo "  gcs_utils/list_data.sh $GCS_DEST"
echo "  cat $WORKFLOW_DIR/config.yml | grep _fp:"
echo ""
