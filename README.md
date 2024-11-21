# AWS S3 File Compression Script

A bash script that automates the process of downloading files matching specific patterns from an AWS S3 bucket, compressing them using tar/pbzip2, and replacing the original files with their compressed versions.

## Requirements

- Bash shell
- AWS CLI (configured with appropriate credentials)
- tar
- pbzip2
- UNIX-based operating system

## Installation

1. Ensure all requirements are installed on your system
2. Download the script
3. Make it executable:
   ```bash
   chmod +x aws_file_type_compresser.sh
   ```

## Usage

Basic syntax:
```bash
./aws_file_type_compresser.sh -b BUCKET -p PROFILE -o OUTPUT_FILE -d OUTPUT_DIR -e ENDING1 [-e ENDING2 ...] [-n]
```

### Arguments

- `-b` : S3 bucket name (base folder name only, without path prefixes)
- `-p` : AWS profile name (uses default if not specified)
- `-o` : Output file name for S3 listing
- `-d` : Temporary output directory for downloaded files
- `-e` : File ending(s) to filter (can be specified multiple times)
- `-n` : Optional - Runs in DRY-RUN mode to preview actions
- `-h` : Show help message

### Example

```bash
./aws_file_type_compresser.sh -b my-bucket -p my-profile -o s3_files.txt -d /tmp/output -e loom -e matrix.txt -n
```

## How It Works

1. Lists all objects in the specified S3 bucket
2. Filters objects based on specified file endings
3. For each matching file:
   - Downloads the file locally
   - Creates a tar.bz2 compressed archive
   - Uploads the compressed file back to S3
   - Deletes the original uncompressed file from S3
   - Cleans up local temporary files

## Notes

- The script will skip files that already have a compressed version (.tar.bz2) in the bucket
- Use the `-n` flag first to preview what the script will do
- Ensure your AWS credentials have appropriate permissions for the S3 bucket
- The temporary directory must have sufficient space for downloaded files

## Error Handling

- The script includes error checking for:
  - Missing required arguments
  - Failed S3 operations
  - Compression failures
  - File system operations

## License

This project is licensed under the [MIT License](LICENSE).
