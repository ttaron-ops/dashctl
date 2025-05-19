#!/bin/bash

_dashctl_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands
    opts="export import rollback"

    # Options
    local options="--folders --dashboard-id --work-dir --dry-run"

    # If we're completing the first argument
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
        return 0
    fi

    # Handle options based on the previous argument
    case "${prev}" in
        --folders)
            # Complete with both UIDs and file paths
            if [[ -d "grafana/folders" ]]; then
                # Get folder UIDs from JSON files
                local folder_uids
                folder_uids=$(grep -r "\"uid\":" grafana/folders/*.json 2>/dev/null | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')

                # Get JSON files in current directory and subdirectories
                local json_files
                json_files=$(find . -type f -name "*.json" 2>/dev/null)

                # Get JSON files in grafana/folders
                local grafana_files
                grafana_files=$(find grafana/folders -type f -name "*.json" 2>/dev/null)

                mapfile -t COMPREPLY < <(compgen -W "${folder_uids} ${json_files} ${grafana_files}" -- "${cur}")
            else
                # Complete with all JSON files
                mapfile -t COMPREPLY < <(compgen -f -X "!*.json" -- "${cur}")
            fi
            return 0
            ;;
        --dashboard-id)
            # Complete with both UIDs and file paths
            if [[ -d "grafana/dashboards" ]]; then
                # Get dashboard UIDs from JSON files
                local dashboard_uids
                dashboard_uids=$(grep -r "\"uid\":" grafana/dashboards/*/*.json 2>/dev/null | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')

                # Get JSON files in current directory and subdirectories
                local json_files
                json_files=$(find . -type f -name "*.json" 2>/dev/null)

                # Get JSON files in grafana/dashboards
                local grafana_files
                grafana_files=$(find grafana/dashboards -type f -name "*.json" 2>/dev/null)

                mapfile -t COMPREPLY < <(compgen -W "${dashboard_uids} ${json_files} ${grafana_files}" -- "${cur}")
            else
                # Complete with all JSON files
                mapfile -t COMPREPLY < <(compgen -f -X "!*.json" -- "${cur}")
            fi
            return 0
            ;;
        --work-dir)
            # Complete with directory names
            mapfile -t COMPREPLY < <(compgen -d -- "${cur}")
            return 0
            ;;
        export|import|rollback)
            # Complete with options
            mapfile -t COMPREPLY < <(compgen -W "${options}" -- "${cur}")
            return 0
            ;;
        *)
            # Complete with options if we're not completing a specific option
            if [[ ${cur} == -* ]]; then
                mapfile -t COMPREPLY < <(compgen -W "${options}" -- "${cur}")
                return 0
            fi
            ;;
    esac
}

# Register the completion function for both dashctl and dashctl.sh
complete -F _dashctl_completion dashctl
complete -F _dashctl_completion dashctl.sh
