#!/bin/bash

# Default values
WORK_DIR="grafana"
GRAFANA_HOST=${GRAFANA_HOST:-"http://localhost:3000"}
GRAFANA_API_KEY=${GRAFANA_API_KEY:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Validate required environment variables
check_env() {
    if [ -z "$GRAFANA_API_KEY" ]; then
        log_error "GRAFANA_API_KEY environment variable is not set"
        exit 1
    fi
}

# Make API request with retry
make_request() {
    local url=$1
    local method=${2:-"GET"}
    local data=$3
    local retries=3
    local delay=5

    for ((i=1; i<=retries; i++)); do
        if [ -z "$data" ]; then
            response=$(curl -s -w "\n%{http_code}" \
                -H "Authorization: Bearer $GRAFANA_API_KEY" \
                -H "Content-Type: application/json" \
                -X "$method" \
                "$GRAFANA_HOST$url")
        else
            response=$(curl -s -w "\n%{http_code}" \
                -H "Authorization: Bearer $GRAFANA_API_KEY" \
                -H "Content-Type: application/json" \
                -X "$method" \
                -d "$data" \
                "$GRAFANA_HOST$url")
        fi

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
            echo "$body"
            return 0
        elif [ "$http_code" -eq 404 ]; then
            echo "$body"
            return 2
        elif [ "$http_code" -eq 403 ]; then
            log_error "Permission denied: $body"
            return 1
        else
            log_warning "Attempt $i failed: $body"
            if [ $i -lt $retries ]; then
                sleep $delay
            fi
        fi
    done

    log_error "All retry attempts failed"
    return 1
}

# Export functions
export_folder() {
    local folder_uid=$1
    local export_dir=$2
    local dry_run=$3
    local total_exported=0
    local failed_exports=0

    # Check if folder_uid is a path
    if [[ "$folder_uid" == *"/"* ]]; then
        if [ ! -f "$folder_uid" ]; then
            log_error "Folder file not found: $folder_uid"
            return 1
        fi
        # Read folder data from file
        folder_data=$(cat "$folder_uid")
        if ! echo "$folder_data" | jq -e . >/dev/null 2>&1; then
            log_error "Invalid JSON in folder file: $folder_uid"
            return 1
        fi
        folder_uid=$(echo "$folder_data" | jq -r '.uid')
        if [ "$folder_uid" = "null" ]; then
            log_error "Invalid folder format: missing UID"
            return 1
        fi
    fi

    # Get folder details
    if ! folder_data=$(make_request "/api/folders/$folder_uid"); then
        return 1
    fi

    # Extract folder title
    folder_title=$(echo "$folder_data" | jq -r '.title')
    folder_name=$(echo "$folder_title" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')

    # Create folder structure
    folder_export_dir="$export_dir/folders"
    mkdir -p "$folder_export_dir"

    # Export folder metadata
    if [ "$dry_run" = true ]; then
        log_warning "Would export folder '$folder_title' with uid '$folder_uid'"
    else
        echo "$folder_data" | jq '{
            uid: .uid,
            title: .title,
            parentUid: .parentUid,
            overwrite: true
        }' > "$folder_export_dir/$folder_name.json"
        log_success "Exported folder '$folder_title' to $folder_export_dir/$folder_name.json"
    fi

    # Export dashboards in this folder using the search API with folderUids parameter
    if ! dashboards=$(make_request "/api/search?query=&type=dash-db&folderUids=$folder_uid"); then
        return 1
    fi

    # Process each dashboard and verify it belongs to the correct folder
    while IFS= read -r dashboard; do
        dash_uid=$(echo "$dashboard" | jq -r '.uid')
        dash_folder_uid=$(echo "$dashboard" | jq -r '.folderUid')

        # Only export if the dashboard belongs to the specified folder
        if [ "$dash_folder_uid" = "$folder_uid" ]; then
            if [ -n "$dash_uid" ]; then
                if export_dashboard "$dash_uid" "$export_dir" "$dry_run"; then
                    ((total_exported++))
                else
                    ((failed_exports++))
                fi
            fi
        fi
    done < <(echo "$dashboards" | jq -c '.[]')

    if [ "$dry_run" = false ]; then
        echo -e "\nFolder Export Summary for '$folder_title':"
        echo "Successfully exported: $total_exported dashboards"
        if [ $failed_exports -gt 0 ]; then
            echo "Failed to export: $failed_exports dashboards"
        fi
    fi
}

export_dashboard() {
    local dashboard_uid=$1
    local export_dir=$2
    local dry_run=$3

    # Get dashboard details
    if ! dashboard_data=$(make_request "/api/dashboards/uid/$dashboard_uid"); then
        return 1
    fi

    # Check if dashboard is provisioned
    is_provisioned=$(echo "$dashboard_data" | jq -r '.meta.provisioned')
    if [ "$is_provisioned" = "true" ]; then
        dashboard_title=$(echo "$dashboard_data" | jq -r '.dashboard.title')
        log_warning "Skipping provisioned dashboard '$dashboard_title'"
        return 0
    fi

    # Extract folder information
    folder_uid=$(echo "$dashboard_data" | jq -r '.meta.folderUid')
    folder_title=$(echo "$dashboard_data" | jq -r '.meta.folderTitle')
    if [ "$folder_uid" = "null" ]; then
        folder_uid="general"
        folder_title="General"
    fi

    # Create sanitized names
    folder_name=$(echo "$folder_title" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')
    dashboard_title=$(echo "$dashboard_data" | jq -r '.dashboard.title')
    dashboard_name=$(echo "$dashboard_title" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')

    # Create directory structure
    dashboard_dir="$export_dir/dashboards/$folder_name"
    mkdir -p "$dashboard_dir"

    # Check if folder metadata exists, if not export it
    folder_export_dir="$export_dir/folders"
    folder_file="$folder_export_dir/$folder_name.json"
    if [ ! -f "$folder_file" ]; then
        if [ "$folder_uid" != "general" ]; then
            # Get folder details
            if folder_data=$(make_request "/api/folders/$folder_uid"); then
                mkdir -p "$folder_export_dir"
                if [ "$dry_run" = true ]; then
                    log_warning "Would export folder '$folder_title' with uid '$folder_uid'"
                else
                    echo "$folder_data" | jq '{
                        uid: .uid,
                        title: .title,
                        parentUid: .parentUid,
                        overwrite: true
                    }' > "$folder_file"
                    log_success "Exported folder '$folder_title' to $folder_file"
                fi
            else
                log_warning "Could not export folder '$folder_title', using default folder"
                folder_uid="general"
                folder_title="General"
                folder_name="general"
            fi
        else
            # Create general folder metadata
            mkdir -p "$folder_export_dir"
            if [ "$dry_run" = true ]; then
                log_warning "Would create general folder metadata"
            else
                echo '{
                    "uid": "general",
                    "title": "General",
                    "overwrite": true
                }' > "$folder_file"
                log_success "Created general folder metadata"
            fi
        fi
    fi

    # Prepare dashboard data
    dashboard_json=$(echo "$dashboard_data" | jq '{
        dashboard: (.dashboard + {id: null}),
        folderUid: .meta.folderUid,
        overwrite: true
    }')

    if [ "$dry_run" = true ]; then
        log_warning "Would export dashboard '$dashboard_title' to $dashboard_dir/$dashboard_name.json"
    else
        echo "$dashboard_json" > "$dashboard_dir/$dashboard_name.json"
        log_success "Exported dashboard '$dashboard_title' to $dashboard_dir/$dashboard_name.json"
    fi

    return 0
}

export_all_dashboards() {
    local export_dir=$1
    local dry_run=$2
    local page=1
    local limit=100
    local total_exported=0
    local failed_exports=0

    # Create base directories
    mkdir -p "$export_dir/folders"
    mkdir -p "$export_dir/dashboards"

    # First, export all folders
    log_success "Exporting all folders..."
    if folders=$(make_request "/api/folders"); then
        while IFS= read -r folder; do
            folder_uid=$(echo "$folder" | jq -r '.uid')
            folder_title=$(echo "$folder" | jq -r '.title')
            folder_name=$(echo "$folder_title" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_')

            if [ "$dry_run" = true ]; then
                log_warning "Would export folder '$folder_title' with uid '$folder_uid'"
            else
                echo "$folder" | jq '{
                    uid: .uid,
                    title: .title,
                    parentUid: .parentUid,
                    overwrite: true
                }' > "$export_dir/folders/$folder_name.json"
                log_success "Exported folder '$folder_title' to $export_dir/folders/$folder_name.json"
            fi
        done < <(echo "$folders" | jq -c '.[]')
    else
        log_error "Failed to export folders"
    fi

    # Then export all dashboards
    log_success "Exporting all dashboards..."
    while true; do
        # Get dashboards with pagination
        if ! dashboards=$(make_request "/api/search?query=&type=dash-db&limit=$limit&page=$page"); then
            break
        fi

        # Check if we got any dashboards
        if [ "$(echo "$dashboards" | jq 'length')" -eq 0 ]; then
            break
        fi

        # Process each dashboard
        while IFS= read -r dashboard; do
            dash_uid=$(echo "$dashboard" | jq -r '.uid')
            if [ -n "$dash_uid" ]; then
                if export_dashboard "$dash_uid" "$export_dir" "$dry_run"; then
                    ((total_exported++))
                else
                    ((failed_exports++))
                fi
            fi
        done < <(echo "$dashboards" | jq -c '.[]')

        # Check if we got fewer results than the limit (last page)
        if [ "$(echo "$dashboards" | jq 'length')" -lt "$limit" ]; then
            break
        fi

        ((page++))
    done

    if [ "$dry_run" = false ]; then
        echo -e "\nExport Summary:"
        echo "Successfully exported: $total_exported dashboards"
        if [ $failed_exports -gt 0 ]; then
            echo "Failed to export: $failed_exports dashboards"
        fi
    fi
}

# Import functions
import_folder() {
    local folder_file=$1
    local dry_run=$2
    local import_dashboards=$3

    if [ ! -f "$folder_file" ]; then
        log_error "Folder file not found: $folder_file"
        return 1
    fi

    # Read and validate folder data
    folder_data=$(cat "$folder_file")
    if ! echo "$folder_data" | jq -e . >/dev/null 2>&1; then
        log_error "Invalid JSON in folder file: $folder_file"
        return 1
    fi

    folder_title=$(echo "$folder_data" | jq -r '.title')
    if [ "$folder_title" = "null" ]; then
        log_error "Invalid folder format: missing title"
        return 1
    fi

    folder_uid=$(echo "$folder_data" | jq -r '.uid')
    if [ "$folder_uid" = "null" ]; then
        log_error "Invalid folder format: missing UID"
        return 1
    fi

    # Check if folder already exists
    if make_request "/api/folders/$folder_uid" >/dev/null; then
        log_warning "Folder '$folder_title' already exists, skipping"
        return 0
    fi

    # Check if parent folder exists
    parent_uid=$(echo "$folder_data" | jq -r '.parentUid')
    if [ "$parent_uid" != "null" ] && [ -n "$parent_uid" ]; then
        if ! make_request "/api/folders/$parent_uid" >/dev/null; then
            log_warning "Parent folder with UID '$parent_uid' not found, will create folder at root level"
            # Remove parentUid from folder data
            folder_data=$(echo "$folder_data" | jq 'del(.parentUid)')
        fi
    fi

    if [ "$dry_run" = true ]; then
        log_warning "Would import folder '$folder_title'"
        # In dry run mode, just log what would be imported and return
        if [ "$import_dashboards" = true ]; then
            folder_name=$(basename "$folder_file" .json)
            if [ -d "$WORK_DIR/dashboards/$folder_name" ]; then
                log_warning "Would import dashboards for folder '$folder_title'"
            fi
        fi
        return 0
    fi

    # Only proceed with actual import if not in dry run mode
    if response=$(make_request "/api/folders" "POST" "$folder_data"); then
        log_success "Imported folder '$folder_title'"
        
        # Import associated dashboards if requested
        if [ "$import_dashboards" = true ]; then
            # Get the folder name from the file path
            folder_name=$(basename "$folder_file" .json)
            if [ -d "$WORK_DIR/dashboards/$folder_name" ]; then
                log_success "Importing dashboards for folder '$folder_title'..."
                for dashboard_file in "$WORK_DIR/dashboards/$folder_name"/*.json; do
                    if [ -f "$dashboard_file" ]; then
                        import_dashboard "$dashboard_file" "$dry_run"
                    fi
                done
            fi
        fi
        return 0
    else
        log_error "Failed to import folder '$folder_title'"
        return 1
    fi
}

# Add new function for dashboard version rollback
rollback_dashboard() {
    local dashboard_uid=$1
    local dry_run=$2

    # Get dashboard versions
    if ! versions=$(make_request "/api/dashboards/uid/$dashboard_uid/versions"); then
        log_error "Failed to get versions for dashboard '$dashboard_uid'"
        return 1
    fi

    # Get the previous version
    previous_version=$(echo "$versions" | jq -r '.[1].version')
    if [ "$previous_version" = "null" ]; then
        log_error "No previous version found for dashboard '$dashboard_uid'"
        return 1
    fi

    # Get the dashboard title for logging
    if ! dashboard_data=$(make_request "/api/dashboards/uid/$dashboard_uid"); then
        log_error "Failed to get dashboard data for '$dashboard_uid'"
        return 1
    fi
    dashboard_title=$(echo "$dashboard_data" | jq -r '.dashboard.title')

    if [ "$dry_run" = true ]; then
        log_warning "Would rollback dashboard '$dashboard_title' to version $previous_version"
    else
        # Restore the previous version
        if response=$(make_request "/api/dashboards/uid/$dashboard_uid/restore" "POST" "{\"version\": $previous_version}"); then
            log_success "Rolled back dashboard '$dashboard_title' to version $previous_version"
            return 0
        else
            log_error "Failed to rollback dashboard '$dashboard_title'"
            return 1
        fi
    fi
}

# Update import_dashboard function to remove rollback
import_dashboard() {
    local dashboard_file=$1
    local dry_run=$2

    if [ ! -f "$dashboard_file" ]; then
        log_error "Dashboard file not found: $dashboard_file"
        return 1
    fi

    # Read and validate dashboard data
    dashboard_data=$(cat "$dashboard_file")
    if ! echo "$dashboard_data" | jq -e . >/dev/null 2>&1; then
        log_error "Invalid JSON in dashboard file: $dashboard_file"
        return 1
    fi

    dashboard_title=$(echo "$dashboard_data" | jq -r '.dashboard.title')
    if [ "$dashboard_title" = "null" ]; then
        log_error "Invalid dashboard format: missing title"
        return 1
    fi

    dashboard_uid=$(echo "$dashboard_data" | jq -r '.dashboard.uid')
    folder_uid=$(echo "$dashboard_data" | jq -r '.folderUid')
    if [ "$folder_uid" = "null" ]; then
        folder_uid="general"
    fi

    # Check if dashboard already exists and if it's provisioned
    if [ -n "$dashboard_uid" ] && [ "$dashboard_uid" != "null" ]; then
        existing_dashboard=$(make_request "/api/dashboards/uid/$dashboard_uid")
        local status=$?
        if [ $status -eq 0 ]; then
            is_provisioned=$(echo "$existing_dashboard" | jq -r '.meta.provisioned')
            if [ "$is_provisioned" = "true" ]; then
                log_warning "Skipping import of provisioned dashboard '$dashboard_title'"
                return 0
            fi
            log_warning "Dashboard '$dashboard_title' already exists, will be updated"
        elif [ $status -eq 2 ]; then
            log_warning "Dashboard '$dashboard_title' does not exist, will be created"
        else
            log_error "Failed to check dashboard status"
            return 1
        fi
    fi

    # Ensure folder exists before importing dashboard
    if [ "$folder_uid" != "general" ]; then
        if ! make_request "/api/folders/$folder_uid" >/dev/null; then
            log_warning "Folder with UID '$folder_uid' not found, will be created"
            # Create folder if it doesn't exist
            folder_data=$(echo "$dashboard_data" | jq '{
                uid: .folderUid,
                title: (.dashboard.folderTitle // "New Folder"),
                overwrite: true
            }')
            if ! make_request "/api/folders" "POST" "$folder_data" >/dev/null; then
                log_error "Failed to create folder for dashboard '$dashboard_title'"
                return 1
            fi
        fi
    fi

    if [ "$dry_run" = true ]; then
        log_warning "Would import dashboard '$dashboard_title'"
    else
        if response=$(make_request "/api/dashboards/db" "POST" "$dashboard_data"); then
            log_success "Imported dashboard '$dashboard_title'"
            return 0
        else
            log_error "Failed to import dashboard '$dashboard_title'"
            return 1
        fi
    fi
}

import_all() {
    local export_dir=$1
    local dry_run=$2
    local total_imported=0
    local failed_imports=0

    # First, import all folders
    log_success "Importing folders..."
    if [ -d "$export_dir/folders" ]; then
        for folder_file in "$export_dir/folders"/*.json; do
            if [ -f "$folder_file" ]; then
                if import_folder "$folder_file" "$dry_run" true; then
                    ((total_imported++))
                else
                    ((failed_imports++))
                fi
            fi
        done
    else
        log_warning "No folders directory found at $export_dir/folders"
    fi

    # Then import all dashboards
    log_success "Importing dashboards..."
    if [ -d "$export_dir/dashboards" ]; then
        while IFS= read -r dashboard_file; do
            if import_dashboard "$dashboard_file" "$dry_run"; then
                ((total_imported++))
            else
                ((failed_imports++))
            fi
        done < <(find "$export_dir/dashboards" -type f -name "*.json")
    else
        log_warning "No dashboards directory found at $export_dir/dashboards"
    fi

    if [ "$dry_run" = false ]; then
        echo -e "\nImport Summary:"
        echo "Successfully imported: $total_imported items"
        if [ $failed_imports -gt 0 ]; then
            echo "Failed to import: $failed_imports items"
        fi
    fi
}

# Main script
main() {
    # Check environment
    check_env

    # Parse command line arguments
    local action=""
    local folders=""
    local dashboard_id=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            export|import|rollback)
                action=$1
                shift
                ;;
            --folders)
                folders=$2
                shift 2
                ;;
            --dashboard-id)
                dashboard_id=$2
                shift 2
                ;;
            --work-dir)
                WORK_DIR=$2
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [ -z "$action" ]; then
        log_error "Action (export/import/rollback) is required"
        exit 1
    fi

    case $action in
        export)
            if [ -n "$folders" ]; then
                IFS=',' read -ra FOLDER_UIDS <<< "$folders"
                for folder_uid in "${FOLDER_UIDS[@]}"; do
                    export_folder "$folder_uid" "$WORK_DIR" "$dry_run"
                done
            elif [ -n "$dashboard_id" ]; then
                export_dashboard "$dashboard_id" "$WORK_DIR" "$dry_run"
            else
                export_all_dashboards "$WORK_DIR" "$dry_run"
            fi
            ;;
        import)
            if [ -n "$folders" ]; then
                # Handle folder imports
                IFS=',' read -ra FOLDER_ITEMS <<< "$folders"
                for folder_item in "${FOLDER_ITEMS[@]}"; do
                    if [ -f "$folder_item" ]; then
                        # If folder_item is a file path, import it directly with dashboards
                        import_folder "$folder_item" "$dry_run" true
                    else
                        # Try to find the folder in the export directory
                        folder_file=$(find "$WORK_DIR/folders" -type f -name "*.json" -exec grep -l "\"uid\":\"$folder_item\"" {} \;)
                        if [ -n "$folder_file" ]; then
                            import_folder "$folder_file" "$dry_run" true
                        else
                            log_warning "Folder with UID '$folder_item' not found in export directory"
                            log_warning "To import a new folder, provide the path to the folder JSON file"
                            return 1
                        fi
                    fi
                done
            elif [ -n "$dashboard_id" ]; then
                # Handle single dashboard import
                if [ -f "$dashboard_id" ]; then
                    # If dashboard_id is a file path, import it directly
                    import_dashboard "$dashboard_id" "$dry_run"
                else
                    # Try to find the dashboard in the export directory
                    dashboard_file=$(find "$WORK_DIR/dashboards" -type f -name "*.json" -exec grep -l "\"uid\":\"$dashboard_id\"" {} \;)
                    if [ -n "$dashboard_file" ]; then
                        import_dashboard "$dashboard_file" "$dry_run"
                    else
                        log_warning "Dashboard with UID '$dashboard_id' not found in export directory"
                        log_warning "To import a new dashboard, provide the path to the dashboard JSON file"
                        return 1
                    fi
                fi
            else
                # Import everything
                import_all "$WORK_DIR" "$dry_run"
            fi
            ;;
        rollback)
            if [ -z "$dashboard_id" ]; then
                log_error "Dashboard ID is required for rollback"
                exit 1
            fi
            rollback_dashboard "$dashboard_id" "$dry_run"
            ;;
    esac
}

# Run the script
main "$@"