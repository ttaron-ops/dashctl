# dashctl - Grafana Dashboard Import/Export Tool

A command-line tool for importing and exporting Grafana dashboards and folders while maintaining the directory structure.

## Author

- [LinkedIn](https://www.linkedin.com/in/taron-hovsepyan-00013/)
- [Buy Me a Coffee](https://buymeacoffee.com/taron)

## Features

- Export/import dashboards and folders with their structure
- Support for both UID-based and file-based operations
- Automatic folder creation and management
- Dry-run mode for testing
- Rollback support for failed imports
- Detailed logging and error handling
- Support for parent folder relationships
- Automatic dashboard import with folder import

## Prerequisites

- Bash shell
- `curl` command-line tool
- `jq` for JSON processing
- Grafana instance with API access

## Installation

### Basic Installation
1. Clone the repository or download the script
2. Make the script executable:
   ```bash
   chmod +x dashctl.sh
   ```

### System-wide Installation (Recommended)

1. Copy the script to the system bin directory:
   ```bash
   # Copy the script and rename it
   sudo cp dashctl.sh /usr/local/bin/dashctl
   
   # Make it executable
   sudo chmod +x /usr/local/bin/dashctl
   ```

2. Set up bash completion:
   ```bash
   # Copy the completion script
   sudo cp dashctl-completion.bash /etc/bash_completion.d/dashctl
   
   # Reload your shell configuration
   source ~/.bashrc
   ```

After installation, you can use the tool simply as:
```bash
dashctl export
dashctl import --folders "abc123"
```

### Dry Run Mode

The dry run mode allows you to preview changes without actually making them. This is useful for:
- Testing import/export operations
- Verifying folder and dashboard selections
- Checking for potential issues

```bash
# Preview export operations
dashctl export --dry-run
dashctl export --folders "abc123" --dry-run
dashctl export --dashboard-id "xyz789" --dry-run

# Preview import operations
dashctl import --dry-run
dashctl import --folders "abc123" --dry-run
dashctl import --dashboard-id "xyz789" --dry-run
```

### Rollback Support

The tool includes dashboard version rollback functionality:

- Rollback a dashboard to its previous version
- Use the standalone rollback command: `dashctl rollback --dashboard-id "xyz789"`
- Works with both UID-based and file-based operations
- Supports dry-run mode to preview changes

Example of dashboard version rollback:
```bash
# Rollback a dashboard to its previous version
dashctl rollback --dashboard-id "xyz789"

# The tool will show version rollback in the logs
# Example log output:
# Rolling back dashboard 'My Dashboard' to version 2
# Successfully rolled back dashboard
```

You can use dry-run to preview changes:
```bash
# Preview rollback without making changes
dashctl rollback --dashboard-id "xyz789" --dry-run
```

## Configuration

Set the following environment variables:
```bash
export GRAFANA_HOST="http://your-grafana-host:3000"
export GRAFANA_API_KEY="your-api-key"
```

## Usage

### Export Operations

#### 1. Export All Dashboards and Folders
```bash
./dashctl.sh export
```
This will export all dashboards and folders to the default `grafana` directory.

#### 2. Export Specific Folders
```bash
# Export by folder UIDs
./dashctl.sh export --folders "folder1_uid,folder2_uid"

# Export by folder JSON files
./dashctl.sh export --folders "/path/to/folder1.json,/path/to/folder2.json"
```

#### 3. Export Specific Dashboard
```bash
# Export by dashboard UID
./dashctl.sh export --dashboard-id "dashboard_uid"

# Export by dashboard JSON file
./dashctl.sh export --dashboard-id "/path/to/dashboard.json"
```

#### 4. Custom Working Directory
```bash
./dashctl.sh export --work-dir "custom_dir"
```

### Import Operations

#### 1. Import All Dashboards and Folders
```bash
./dashctl.sh import
```
This will import all dashboards and folders from the default `grafana` directory.

#### 2. Import Specific Folders
```bash
# Import by folder UIDs
./dashctl.sh import --folders "folder1_uid,folder2_uid"

# Import by folder JSON files
./dashctl.sh import --folders "/path/to/folder1.json,/path/to/folder2.json"
```
Note: When importing folders, the tool will automatically import all dashboards from the corresponding dashboard directory.

#### 3. Import Specific Dashboard
```bash
# Import by dashboard UID
./dashctl.sh import --dashboard-id "dashboard_uid"

# Import by dashboard JSON file
./dashctl.sh import --dashboard-id "/path/to/dashboard.json"
```

#### 4. Custom Working Directory
```bash
./dashctl.sh import --work-dir "custom_dir"
```

### Dry Run Mode

Add `--dry-run` to any command to see what would be imported/exported without making changes:
```bash
./dashctl.sh export --dry-run
./dashctl.sh import --folders "folder1_uid" --dry-run
```

## Directory Structure

The tool maintains the following structure:
```
grafana/
├── folders/
│   ├── folder1.json
│   └── folder2.json
└── dashboards/
    ├── folder1/
    │   ├── dashboard1.json
    │   └── dashboard2.json
    └── folder2/
        └── dashboard3.json
```

## File Format

### Folder JSON Format
```json
{
    "uid": "folder_uid",
    "title": "Folder Title",
    "parentUid": "parent_folder_uid",  // Optional
    "overwrite": true
}
```

### Dashboard JSON Format
```json
{
    "dashboard": {
        "uid": "dashboard_uid",
        "title": "Dashboard Title",
        // ... other dashboard properties
    },
    "folderUid": "folder_uid",
    "overwrite": true
}
```

## Error Handling

The tool handles various error cases:
- Invalid JSON format
- Missing required fields
- Non-existent folders/dashboards
- API errors
- Permission issues

## Examples

### Export Examples

1. Export all dashboards and folders:
   ```bash
   ./dashctl.sh export
   ```

2. Export specific folders by UID:
   ```bash
   ./dashctl.sh export --folders "abc123,def456"
   ```

3. Export specific folders by file:
   ```bash
   ./dashctl.sh export --folders "/path/to/folder1.json,/path/to/folder2.json"
   ```

4. Export specific dashboard by UID:
   ```bash
   ./dashctl.sh export --dashboard-id "xyz789"
   ```

5. Export specific dashboard by file:
   ```bash
   ./dashctl.sh export --dashboard-id "/path/to/dashboard.json"
   ```

### Import Examples

1. Import all dashboards and folders:
   ```bash
   ./dashctl.sh import
   ```

2. Import specific folders by UID:
   ```bash
   ./dashctl.sh import --folders "abc123,def456"
   ```

3. Import specific folders by file:
   ```bash
   ./dashctl.sh import --folders "/path/to/folder1.json,/path/to/folder2.json"
   ```

4. Import specific dashboard by UID:
   ```bash
   ./dashctl.sh import --dashboard-id "xyz789"
   ```

5. Import with custom directory:
   ```bash
   ./dashctl.sh import --work-dir "my_grafana" --folders "abc123"
   ```

6. Dry run import:
   ```bash
   ./dashctl.sh import --folders "abc123" --dry-run
   ```

## Notes

- The tool automatically creates missing folders when importing dashboards
- Existing folders are skipped during import
- Existing dashboards are updated during import
- Parent folder relationships are maintained when possible
- If a parent folder doesn't exist, the folder will be created at the root level
- All operations are logged with clear success/error messages
- The tool uses human-readable names for exported files
- Dashboard files are organized in folders matching their parent folder names

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Finding Grafana IDs

### Finding Folder IDs
1. Open your Grafana instance in a web browser
2. Navigate to Dashboards
3. Click on the folder you want to work with
4. The folder UID is in the URL: `https://your-grafana/dashboards/f/{folder_uid}`
   - Example: If URL is `https://grafana.example.com/dashboards/f/abc123`, the folder UID is `abc123`

### Finding Dashboard IDs
1. Open your Grafana instance in a web browser
2. Navigate to the dashboard you want to work with
3. The dashboard UID is in the URL: `https://your-grafana/d/{dashboard_uid}`
   - Example: If URL is `https://grafana.example.com/d/xyz789`, the dashboard UID is `xyz789`

## Important Note About IDs and Paths

The tool works in two modes:

1. **First-time Export Mode**:
   - Use folder and dashboard UIDs to export from Grafana
   - Example: `./dashctl.sh export --folders "abc123,def456"`
   - This creates the initial directory structure in your working directory

2. **Subsequent Operations Mode**:
   - After the first export, you can use either:
     - UIDs (which will be looked up in the exported files)
     - Direct paths to JSON files
   - Example: `./dashctl.sh import --folders "folder1.json,folder2.json"`

### Workflow Example

1. First-time export using UIDs:
   ```bash
   # Export specific folders using their UIDs
   ./dashctl.sh export --folders "abc123,def456"

   # Or export all dashboards and folders
   ./dashctl.sh export
   ```

2. Subsequent operations can use either UIDs or file paths:
   ```bash
   # Using UIDs (looks up in exported files)
   ./dashctl.sh import --folders "abc123,def456"

   # Using file paths (direct access to JSON files)
   ./dashctl.sh import --folders "grafana/folders/folder1.json,grafana/folders/folder2.json"
   ```

### Directory Structure After Export

After the first export, the tool creates this structure:
```
grafana/
├── folders/
│   ├── folder1.json    # Contains folder metadata including UID
│   └── folder2.json
└── dashboards/
    ├── folder1/
    │   ├── dashboard1.json
    │   └── dashboard2.json
    └── folder2/
        └── dashboard3.json
```

You can then:
1. Use UIDs to reference items (tool will look them up in the exported files)
2. Use direct paths to the JSON files
3. Modify the JSON files and reimport them
4. Use the exported files as templates for new dashboards/folders