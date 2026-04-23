#!/bin/bash

# Mount Google Drive via rclone to /workspace
#
# Required environment variables (set via Vast.ai instance env):
#   RCLONE_CONFIG_CONTENT  - base64-encoded rclone.conf content
#   (OR)
#   GDRIVE_SA_JSON         - Google Service Account JSON content
#
# Optional:
#   GDRIVE_MOUNT_PATH      - Mount point (default: /workspace)
#   GDRIVE_REMOTE_PATH     - Remote path within GDrive (default: root)
#   GDRIVE_MOUNT_ENABLED   - Set to "true" to enable (default: false)

gdrive_mount() {
    [[ "${GDRIVE_MOUNT_ENABLED:-false}" != "true" ]] && return 0

    local mount_path="${GDRIVE_MOUNT_PATH:-/workspace}"
    local remote_path="${GDRIVE_REMOTE_PATH:-}"

    mkdir -p "${mount_path}"

    local rclone_config_dir="/root/.config/rclone"
    mkdir -p "${rclone_config_dir}"

    if [[ -n "${RCLONE_CONFIG_CONTENT:-}" ]]; then
        # Extract only the [gdrive] section to avoid interference from other remotes
        local decoded
        decoded=$(echo "${RCLONE_CONFIG_CONTENT}" | base64 -d)
        local gdrive_section
        gdrive_section=$(echo "${decoded}" | awk '/^\[gdrive\]/{found=1; print; next} found && /^\[/{exit} found{print}')
        if [[ -z "${gdrive_section}" ]]; then
            echo "rclone: no [gdrive] section found in RCLONE_CONFIG_CONTENT"
            return 1
        fi
        echo "${gdrive_section}" > "${rclone_config_dir}/rclone.conf"
        echo "rclone: extracted [gdrive] section from RCLONE_CONFIG_CONTENT"

    elif [[ -n "${GDRIVE_SA_JSON:-}" ]]; then
        local sa_file="/tmp/gdrive-sa.json"
        echo "${GDRIVE_SA_JSON}" > "${sa_file}"
        cat > "${rclone_config_dir}/rclone.conf" <<EOF
[gdrive]
type = drive
scope = drive
service_account_file = ${sa_file}
EOF
        echo "rclone: configured with service account JSON"
    else
        echo "rclone: No credentials provided (RCLONE_CONFIG_CONTENT or GDRIVE_SA_JSON), skipping GDrive mount"
        return 0
    fi

    # Check FUSE availability
    if ! ls /dev/fuse > /dev/null 2>&1; then
        echo "rclone: /dev/fuse not available, cannot mount GDrive"
        echo "rclone: container must be started with --device /dev/fuse or --privileged"
        return 1
    fi

    local remote_str="gdrive:${remote_path}"
    echo "rclone: mounting ${remote_str} -> ${mount_path}"

    rclone mount "${remote_str}" "${mount_path}" \
        --daemon \
        --vfs-cache-mode full \
        --vfs-cache-max-size 10G \
        --dir-cache-time 5m \
        --vfs-read-chunk-size 128M \
        --buffer-size 64M \
        --transfers 8 \
        --log-file /var/log/rclone-gdrive.log \
        --log-level INFO

    # Wait for mount to be ready
    local retries=15
    while [[ $retries -gt 0 ]]; do
        if mountpoint -q "${mount_path}"; then
            echo "rclone: GDrive mounted at ${mount_path}"
            return 0
        fi
        sleep 2
        ((retries--))
    done

    echo "rclone: WARNING - mount may not be ready, check /var/log/rclone-gdrive.log"
}

gdrive_mount
