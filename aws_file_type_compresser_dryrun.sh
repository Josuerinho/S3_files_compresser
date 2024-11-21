#!/bin/bash

# program to download a series of files that match a specific pattern from a bucket, compress and upload them back into the same place and 
# finishing by deleting the initial file that was downloaded.

# Function to display usage
show_usage() {
    echo "Usage: $0 -b BUCKET -p PROFILE -o OUTPUT_FILE -d OUTPUT_DIR -e ENDING1 [-e ENDING2 ...]"
    echo
    echo "Arguments:"
    echo "  -b    S3 bucket name"
    echo "  -p    AWS profile name"
    echo "  -o    Output file name for S3 listing"
    echo "  -d    Output directory for downloaded files"
    echo "  -e    File ending(s) to filter (can be specified multiple times)"
    echo "  -n    Runs commands in DRY-RUN mode to show what it would have done"
    echo "  -h    Show this help message"
    echo
    echo "Example:"
    echo "  $0 -b my-bucket -p my-profile -o s3_files.txt -d /tmp/output -e filt.txt -e matrix.txt"
    exit 1
}

# Initialize arrays and variables
file_endings=()
BUCKET=""
PROFILE=""
FILE_NAME_OUTPUT=""
OUTPUT_DIR=""

# Add dry-run flag to variables initialization
DRY_RUN=false

# Parse command line arguments
while getopts "b:p:o:d:e:hn" opt; do
    case $opt in
        b) BUCKET="$OPTARG";;
        p) PROFILE="$OPTARG";;
        o) FILE_NAME_OUTPUT="$OPTARG";;
        d) OUTPUT_DIR="$OPTARG";;
        e) file_endings+=("$OPTARG");;
        n) DRY_RUN=true;;
        h) show_usage;;
        ?) show_usage;;
    esac
done

# Validate required arguments
if [ -z "$BUCKET" ] || [ -z "$PROFILE" ] || [ -z "$FILE_NAME_OUTPUT" ] || [ -z "$OUTPUT_DIR" ] || [ ${#file_endings[@]} -eq 0 ]; then
    echo "Error: Missing required arguments"
    show_usage
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create output directory: $OUTPUT_DIR"
    exit 1
fi

# Get S3 objects
echo "Fetching objects from S3 bucket: $BUCKET"
aws s3api list-objects-v2 --bucket "$BUCKET" --profile "$PROFILE" --query 'Contents[].Key' --output text > "$FILE_NAME_OUTPUT"

if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch S3 objects"
    exit 1
fi

# Build the grep pattern
pattern=""
for ending in "${file_endings[@]}"; do
    if [ -z "$pattern" ]; then
        pattern="${ending}\$"
    else
        pattern="${pattern}|${ending}\$"
    fi
done

echo "Filtering files with pattern: $pattern"

# Execute the command and store results in a temporary file
temp_output=$(mktemp)
cat "$FILE_NAME_OUTPUT" | sed 's/\t/\n/g' | grep -E "$pattern" > "$temp_output"

# Check if any matches were found
if [ ! -s "$temp_output" ]; then
    echo "No files found matching the specified pattern(s)"
    rm "$temp_output"
    exit 0
fi

echo "Found matching files:"
cat "$temp_output"

# Process each file
echo "Processing files..."
while IFS= read -r file; do
    echo "Processing: $file"

    # Check if compressed version already exists
    TAR_BZIP="${file}.tar.bz2"
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would check if $TAR_BZIP exists in S3"
    else
        aws s3 ls "s3://${BUCKET}/${TAR_BZIP}" --profile "$PROFILE" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "  Skipping: Compressed version already exists for $file"
            continue
        fi
    fi
    
    # Download file from S3
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would download: s3://${BUCKET}/$file to ${OUTPUT_DIR}/"
    else
        echo "  Downloading from S3..."
        aws s3 cp "s3://${BUCKET}/$file" "${OUTPUT_DIR}/" --profile "$PROFILE" || {
            echo "  Error: Failed to download file: $file"
            continue
        }
    fi

    # Create compressed archive
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would create compressed archive: $TAR_BZIP from $file"
    else
        echo "  Creating compressed archive..."
        current_dir=$(pwd)
        cd "${OUTPUT_DIR}"
        tar cf "$(basename "$TAR_BZIP")" --use-compress-prog=pbzip2 "$(basename "$file")" || {
            echo "  Error: Failed to create compressed archive for: $file"
            cd "$current_dir"
            continue
        }
        cd "$current_dir"
    fi

    # Upload compressed file to S3
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would upload: ${OUTPUT_DIR}/$(basename "$TAR_BZIP") to s3://${BUCKET}/$(dirname "$file")/$(basename "$TAR_BZIP")"
    else
        echo "  Uploading compressed file to S3..."
        aws s3 cp "${OUTPUT_DIR}/$(basename "$TAR_BZIP")" "s3://${BUCKET}/$(dirname "$file")/$(basename "$TAR_BZIP")" --profile "$PROFILE" || {
            echo "  Error: Failed to upload compressed file: $TAR_BZIP"
            continue
        }
    fi

    # Remove original file from S3
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would remove: s3://${BUCKET}/$file"
    else
        echo "  Removing original file from S3..."
        aws s3 rm "s3://${BUCKET}/$file" --profile "$PROFILE" || {
            echo "  Error: Failed to remove original file: $file"
            continue
        }
    fi

    # Clean up local files
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would remove local files: ${OUTPUT_DIR}/$(basename "$file") and ${OUTPUT_DIR}/$(basename "$TAR_BZIP")"
    else
        echo "  Cleaning up local files..."
        rm "${OUTPUT_DIR}/$(basename "$file")" "${OUTPUT_DIR}/$(basename "$TAR_BZIP")"
        echo "  Successfully processed: $file"
    fi
    
    echo

done < "$temp_output"

# Cleanup
rm "$temp_output"
echo "All processing complete!"